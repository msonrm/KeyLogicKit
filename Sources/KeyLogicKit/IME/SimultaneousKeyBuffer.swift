import Foundation

/// 同時打鍵バッファ
///
/// 先行出力＋巻き戻し方式（eager mode）で同時打鍵を検出する。
/// - 1キー目押下 → 即座に単打面の文字を出力（遅延 0ms）
/// - 80ms 以内に2キー目 → 先行出力を削除し同時打鍵結果に差し替え
/// - 2キー受付後（マッチ有無問わず）80ms 以内に3キー目 → 3キーテーブルを検索
/// - タイマー満了 → 確定
///
/// 3キー同時打鍵は濁音拗音（J+R+H=じゃ 等）、半濁拗音（M+X+H=ぴゃ 等）、
/// 外来音（M+E+K=てぃ 等）、ゔ（F+L+SCLN）で使用する。
///
/// 2キーがテーブルにない組み合わせでも3キー目を待つことで、
/// 押下順序に依存せず3キー同時打鍵を検出できる。
/// 例: I(る)+J(あ) は2キーテーブルにないが、I+J+R → J|R|I = じょ が成立する。
///
/// `replaceCount` は ComposingText 上の **文字数** を表す。
/// `insertAtCursorPosition(_:inputStyle:.direct)` は文字ごとに入力ピースを作るため、
/// "しょ"（2文字）は2ピースになる。差し替え時は文字数分を削除する必要がある。
///
/// シフトキー（センターシフト / 親指シフト）は先行出力なし（タイマー待機してから判定）。
/// タイマー経過後もシフトキーが押されていればシフトホールド状態に遷移し、
/// 後続のキーをシフト面で出力する。
/// どのキーがシフトキーかは `shiftKeyConfigs` で設定する（データ駆動）。
@MainActor
public class SimultaneousKeyBuffer {

    // MARK: - 状態

    /// バッファの状態
    private enum State {
        /// キー入力待ち
        case idle
        /// 1キー目受付済み、2キー目待ち
        case waiting(firstKey: ChordKey, firstOutput: String?)
        /// 2キー受付済み、3キー目待ち
        ///
        /// 2キーマッチの有無に関わらずこの状態に遷移する。
        /// `bufferedKeys` はバッファ中の個別キー（同一キー判定に使用）。
        /// `bits` はビットOR結合値（テーブル検索に使用）。
        /// `charCount` は ComposingText に追加済みの **文字数**。
        /// `insertAtCursorPosition` は1文字=1入力ピースのため、
        /// 差し替え時は `charCount` 個の入力ピースを削除する。
        /// `pendingAction` は 2キー specialAction の遅延発火用。
        /// 3キー chord が成立すれば破棄し、タイマー満了時に発火する。
        case waitingThird(bufferedKeys: Set<ChordKey>, bits: UInt64, charCount: Int, pendingAction: KeyAction? = nil)
        /// シフトキーホールド中（タイマー経過後もシフトキーが押されている）
        ///
        /// `shiftKey` はホールド中のシフトキーの識別子。
        /// `used` が true の場合、シフト面の文字が出力済みなので
        /// シフトキーリリース時に単打アクションを発火しない。
        case shiftHeld(shiftKey: ChordKey, used: Bool)
    }

    // MARK: - Properties

    /// 同時打鍵判定ウィンドウ（秒）
    public var simultaneousWindow: TimeInterval = 0.080

    /// バッファの現在の状態
    private var state: State = .idle

    /// タイマー（Task + Task.sleep で実装）
    private var pendingTask: Task<Void, Never>?

    /// 現在押下中のキーの集合（シフトホールド判定に使用）
    private var pressedKeys: Set<ChordKey> = []

    /// 物理 Shift キーが押されているか（英数モードでの大文字入力用）
    ///
    /// chord buffer は ChordKey ビットのみで動作するため、UIKey の modifierFlags を直接参照できない。
    /// 呼び出し元が `keyDown` 前にこのフラグを設定し、lookup 時に shift ビットを合成する。
    /// 日本語モードでは常に false にすること（センターシフトと競合するため）。
    public var physicalShift: Bool = false

    // MARK: - テーブル差し替え

    /// 文字出力テーブル（setupChordBuffer で注入）
    public var lookupFunction: (UInt64) -> String? = { _ in nil }

    /// 特殊アクションテーブル（setupChordBuffer で注入）
    public var specialActionFunction: (UInt64) -> KeyAction? = { _ in nil }

    // MARK: - シフトキー設定

    /// シフトキー設定（ChordKey → 単打時アクション）
    ///
    /// キーマップの `shiftKeys` から構築する。
    /// このマップに含まれるキーは先行出力なしの遅延判定になる。
    public var shiftKeyConfigs: [ChordKey: KeyAction?] = [:]

    /// 指定されたキーがシフトキーかどうか
    private func isShiftKey(_ key: ChordKey) -> Bool {
        shiftKeyConfigs.keys.contains(key)
    }

    /// シフトキー単打時のフォールバックアクションを取得
    private func shiftKeySingleTapAction(_ key: ChordKey) -> KeyAction? {
        shiftKeyConfigs[key] ?? nil
    }

    // MARK: - コールバック

    /// テキスト出力コールバック
    ///
    /// - Parameters:
    ///   - text: 出力する文字列（薙刀式ではひらがな、英数モードでは英数字）
    ///   - replaceCount: 0 の場合は追加、1以上の場合は直前の N 文字（入力ピース）を削除して出力
    public var onOutput: ((_ text: String, _ replaceCount: Int) -> Void)?

    /// シフトキー単打確定コールバック
    ///
    /// シフトキーが同時打鍵に使われずに離された場合に発火する。
    /// 引数の `KeyAction` は `shiftKeyConfigs` で定義されたフォールバックアクション。
    public var onShiftSingle: ((KeyAction) -> Void)?

    /// 特殊アクションコールバック（Backspace, 矢印, Enter 等）
    public var onSpecialAction: ((KeyAction) -> Void)?

    // MARK: - Public API

    /// 初期化
    public init() {}

    /// キーダウンイベント処理
    public func keyDown(_ key: ChordKey) {
        pressedKeys.insert(key)

        switch state {
        case .idle:
            handleFirstKey(key)

        case .waiting(let firstKey, let firstOutput):
            handleSecondKey(key, firstKey: firstKey, firstOutput: firstOutput)

        case .waitingThird(let bufferedKeys, let bits, let charCount, let pendingAction):
            handleThirdKey(key, bufferedKeys: bufferedKeys, existingBits: bits, charCount: charCount, pendingAction: pendingAction)

        case .shiftHeld(let shiftKey, let used):
            handleShiftHeldKey(key, shiftKey: shiftKey, used: used)
        }
    }

    /// キーアップイベント処理
    public func keyUp(_ key: ChordKey) {
        pressedKeys.remove(key)

        // シフトホールド中にシフトキーを離した場合
        if case .shiftHeld(shiftKey: key, let used) = state {
            if !used, let action = shiftKeySingleTapAction(key) {
                // シフト面を使わずにリリース → 単打アクション発火
                onShiftSingle?(action)
            }
            state = .idle
        }
    }

    /// バッファリセット（確定・キャンセル時に呼ぶ）
    public func reset() {
        cancelTimer()
        state = .idle
        physicalShift = false
    }

    // MARK: - 1キー目の処理

    private func handleFirstKey(_ key: ChordKey) {
        let bits = key.bit
        // 物理 Shift が押されていれば shift ビットを合成して lookup する
        let lookupBits = physicalShift ? (ChordKey.space.bit | bits) : bits

        // 特殊アクションの判定（U=BS, T=←, Y=→）
        // 生ビットで判定（物理 Shift で意図しないアクションが発動しないように）
        if let action = specialActionFunction(bits) {
            onSpecialAction?(action)
            state = .idle
            return
        }

        if isShiftKey(key) {
            // シフトキーは先行出力なし（タイマー待機してシフトか単打か判定）
            state = .waiting(firstKey: key, firstOutput: nil)
            startTimer()
        } else if let singleChar = lookupFunction(lookupBits) {
            // 文字キー → 先行出力して待機
            onOutput?(singleChar, 0)
            state = .waiting(firstKey: key, firstOutput: singleChar)
            startTimer()
        } else if physicalShift, let singleChar = lookupFunction(bits) {
            // 物理 Shift 付きでヒットしなかった場合、Shift なしで再試行
            onOutput?(singleChar, 0)
            state = .waiting(firstKey: key, firstOutput: singleChar)
            startTimer()
        } else {
            // テーブルにないキー（Q 単打など）→ 先行出力なしで待機
            // Q+H=ゃ 等の同時打鍵の1キー目になりうる
            state = .waiting(firstKey: key, firstOutput: nil)
            startTimer()
        }
    }

    // MARK: - 2キー目の処理

    private func handleSecondKey(_ key: ChordKey, firstKey: ChordKey, firstOutput: String?) {
        cancelTimer()

        // 同じキーの連打 → 同時打鍵ではない。1キー目を確定し、同じキーを新規1キー目として処理
        if key == firstKey {
            state = .idle
            handleFirstKey(key)
            return
        }

        let combined = firstKey.bit | key.bit
        let firstCharCount = firstOutput?.count ?? 0

        // 特殊アクションの判定（V+M=Enter, H+J=switchToJapanese 等）
        // 3キー chord と競合する可能性があるため、即発火せず waitingThird に遅延する。
        // 3キー目が来れば chord 優先、タイマー満了で specialAction を発火する。
        let pendingAction = specialActionFunction(combined)
        if let pendingAction {
            if firstCharCount > 0 {
                // 先行出力を巻き戻し
                onOutput?("", firstCharCount)
            }
            let keys: Set<ChordKey> = [firstKey, key]
            state = .waitingThird(bufferedKeys: keys, bits: combined, charCount: 0, pendingAction: pendingAction)
            startTimer()
            return
        }

        // 同時打鍵テーブルを検索
        let lookupCombined = physicalShift ? (ChordKey.space.bit | combined) : combined
        if let simultaneousResult = lookupFunction(lookupCombined) ?? (physicalShift ? lookupFunction(combined) : nil) {
            if firstCharCount > 0 {
                // 先行出力を差し替え（1キー目の文字数分を削除）
                onOutput?(simultaneousResult, firstCharCount)
            } else {
                // Space の先行出力なし → 新規出力
                onOutput?(simultaneousResult, 0)
            }
            // 3キー目を待機（2キー結果の文字数を記録）
            let keys: Set<ChordKey> = [firstKey, key]
            state = .waitingThird(bufferedKeys: keys, bits: combined, charCount: simultaneousResult.count)
            startTimer()
        } else {
            // 同時打鍵テーブルにない組み合わせ
            if isShiftKey(firstKey) && firstOutput == nil {
                // シフトキー待機中だったが同時打鍵なし → 単打アクション確定
                // シフトキーの3キー同時打鍵はないので、2キー目を新規1キー目として処理
                if let action = shiftKeySingleTapAction(firstKey) {
                    onShiftSingle?(action)
                }
                state = .idle
                handleFirstKey(key)
            } else {
                // 2キーマッチなし → 2キー目の単打を先行出力し、3キー目を待つ
                // （例: I+J はテーブルにないが、I+J+R → じょ が成立しうる）
                let keys: Set<ChordKey> = [firstKey, key]
                let keyLookupBits = physicalShift ? (ChordKey.space.bit | key.bit) : key.bit
                if let singleChar = lookupFunction(keyLookupBits) ?? (physicalShift ? lookupFunction(key.bit) : nil) {
                    onOutput?(singleChar, 0)
                    state = .waitingThird(bufferedKeys: keys, bits: combined, charCount: firstCharCount + singleChar.count)
                } else {
                    // 2キー目に単打もない（Q 等） → バッファに保持して3キー目を待つ
                    state = .waitingThird(bufferedKeys: keys, bits: combined, charCount: firstCharCount)
                }
                startTimer()
            }
        }
    }

    // MARK: - 3キー目の処理

    /// 2キー受付後の3キー目処理
    ///
    /// 同じキーの再打鍵は同時打鍵ではないので、バッファを確定して新規入力にする。
    /// 異なるキーなら3キー同時打鍵テーブルを検索し、マッチすれば既存出力を差し替える。
    /// `charCount` 文字（入力ピース）を削除して3キー結果に置換する。
    /// マッチしなければ既存出力は確定済みとし、3キー目を新規の1キー目とする。
    private func handleThirdKey(_ key: ChordKey, bufferedKeys: Set<ChordKey>, existingBits: UInt64, charCount: Int, pendingAction: KeyAction? = nil) {
        cancelTimer()

        // 同じキーの再打鍵 → 同時打鍵ではない。遅延アクションがあれば発火してからバッファ確定
        if bufferedKeys.contains(key) {
            if let pendingAction {
                onSpecialAction?(pendingAction)
            }
            state = .idle
            handleFirstKey(key)
            return
        }

        let tripleKeys = existingBits | key.bit

        // 3キー同時打鍵テーブルを検索
        let lookupTriple = physicalShift ? (ChordKey.space.bit | tripleKeys) : tripleKeys
        if let tripleResult = lookupFunction(lookupTriple) ?? (physicalShift ? lookupFunction(tripleKeys) : nil) {
            // 3キー同時打鍵成立 → 既存出力を差し替え（遅延 specialAction は破棄）
            onOutput?(tripleResult, charCount)
            state = .idle
        } else {
            // 3キー同時打鍵なし → 遅延 specialAction があれば発火
            if let pendingAction {
                onSpecialAction?(pendingAction)
            }
            // 既存出力は確定済み（先行出力済み）
            // 3キー目を新規の1キー目として処理
            state = .idle
            handleFirstKey(key)
        }
    }

    // MARK: - シフトホールド中のキー処理

    /// シフトキーホールド中のキーダウン処理
    ///
    /// タイマー満了後もシフトキーが押され続けている場合に呼ばれる。
    /// シフト面の文字を出力し、used フラグを立てる。
    private func handleShiftHeldKey(_ key: ChordKey, shiftKey: ChordKey, used: Bool) {
        if key == shiftKey {
            // シフトキーの重複ダウン → 無視
            return
        }

        let combined = shiftKey.bit | key.bit

        // 特殊アクション（SHFT+V=、, SHFT+M=。 等）
        if let action = specialActionFunction(combined) {
            onSpecialAction?(action)
            state = .shiftHeld(shiftKey: shiftKey, used: true)
            return
        }

        // シフト面の文字
        if let shifted = lookupFunction(combined) {
            onOutput?(shifted, 0)
            state = .shiftHeld(shiftKey: shiftKey, used: true)
            return
        }

        // シフト面にない組み合わせ → シフトが未使用なら単打アクション確定し、
        // キーを新規の1キー目として処理
        if !used, let action = shiftKeySingleTapAction(shiftKey) {
            onShiftSingle?(action)
        }
        state = .idle
        handleFirstKey(key)
    }

    // MARK: - タイマー管理

    private func startTimer() {
        cancelTimer()
        let window = simultaneousWindow
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled else { return }
            self?.onTimerExpired()
        }
    }

    private func cancelTimer() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    private func onTimerExpired() {
        switch state {
        case .waiting(let firstKey, _):
            if isShiftKey(firstKey) {
                if pressedKeys.contains(firstKey) {
                    // シフトキーがまだ押されている → シフトホールド状態に遷移
                    // （単打アクションはリリース時に判定する）
                    state = .shiftHeld(shiftKey: firstKey, used: false)
                } else {
                    // シフトキーは既にリリース済み → 単打アクション確定
                    if let action = shiftKeySingleTapAction(firstKey) {
                        onShiftSingle?(action)
                    }
                    state = .idle
                }
            } else {
                // 文字キーの場合は先行出力済みなのでそのまま確定
                state = .idle
            }

        case .waitingThird(_, _, _, let pendingAction):
            // 先行出力済みの結果をそのまま確定
            // 遅延 specialAction があれば発火（H+J=switchToJapanese 等）
            if let pendingAction {
                onSpecialAction?(pendingAction)
            }
            state = .idle

        default:
            break
        }
    }
}
