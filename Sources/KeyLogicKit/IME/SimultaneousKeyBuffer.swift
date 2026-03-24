import Foundation

/// 同時打鍵バッファ（pressesEnded ベース）
///
/// 押下中キーの集合（heldKeys）で同時打鍵を判定する。タイマー不要。
///
/// - **単打**: keyDown → 待機、keyUp（全キーリリース）→ 出力
/// - **2キー chord**: 2キー目の keyDown で即出力（差し替えなし）
/// - **3キー chord**: 3キー目の keyDown で即出力（2キー結果を差し替え）
/// - **シフト+キー**: シフトキーが押されている間、後続キーをシフト面で即出力
///
/// 単打のみ keyUp まで遅延し、chord は keyDown 時に即出力するため、
/// chord のレスポンスは従来と同等。先行出力＋巻き戻しが不要になり、
/// 押下順序に依存しない自然な同時打鍵検出を実現する。
///
/// `replaceCount` は ComposingText 上の **文字数** を表す。
/// `insertAtCursorPosition(_:inputStyle:.direct)` は文字ごとに入力ピースを作るため、
/// "しょ"（2文字）は2ピースになる。差し替え時は文字数分を削除する必要がある。
@MainActor
public class SimultaneousKeyBuffer {

    // MARK: - フェーズ

    /// バッファのフェーズ
    private enum Phase {
        /// キー入力蓄積中（chord グループ形成中）
        case accumulating
        /// シフトキーホールド中（chord 確定後、シフトキーのみ残存）
        ///
        /// `used` が true の場合、シフト面の文字が出力済みなので
        /// シフトキーリリース時に単打アクションを発火しない。
        case shiftMode(shiftKey: ChordKey, used: Bool)
    }

    // MARK: - Properties

    /// 現在押下中のキーの集合
    private var heldKeys: Set<ChordKey> = []

    /// 現在の chord グループに含まれる全キー（リリース済み含む）
    ///
    /// heldKeys が空→非空になった時点で開始し、再び空になった時点で確定する。
    private var chordGroup: Set<ChordKey> = []

    /// 現在の chord グループで出力済みの文字数（差し替え用）
    private var outputCharCount: Int = 0

    /// 遅延中の特殊アクション（3キー chord で上書きされる可能性がある）
    private var pendingSpecialAction: KeyAction? = nil

    /// chord 出力が行われたか（finalize での判定に使用）
    private var chordOutputted: Bool = false

    /// 現在のフェーズ
    private var phase: Phase = .accumulating

    /// 同時打鍵判定ウィンドウ（秒）
    ///
    /// pressesEnded ベースではタイマーを使用しないため内部では未使用。
    /// キーマップ定義との互換性のために保持する。
    public var simultaneousWindow: TimeInterval = 0.080

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
    /// このマップに含まれるキーは単打出力なしの遅延判定になる。
    public var shiftKeyConfigs: [ChordKey: KeyAction?] = [:]

    /// 指定されたキーがシフトキーかどうか
    private func isShiftKey(_ key: ChordKey) -> Bool {
        shiftKeyConfigs.keys.contains(key)
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
        heldKeys.insert(key)

        switch phase {
        case .accumulating:
            chordGroup.insert(key)
            if chordGroup.count >= 2 {
                evaluateChord()
            }

        case .shiftMode(let shiftKey, _):
            guard key != shiftKey else { return } // シフトキーの重複ダウン → 無視
            handleShiftModeKey(key, shiftKey: shiftKey)
        }
    }

    /// キーアップイベント処理
    public func keyUp(_ key: ChordKey) {
        heldKeys.remove(key)

        switch phase {
        case .accumulating:
            if heldKeys.isEmpty {
                finalize()
            } else if chordGroup.count >= 2,
                      heldKeys.count == 1,
                      let remaining = heldKeys.first,
                      isShiftKey(remaining) {
                // chord 評価後にシフトキーだけ残っている → シフトモードに遷移
                let wasUsed = chordOutputted
                if let action = pendingSpecialAction {
                    onSpecialAction?(action)
                }
                resetChordState()
                phase = .shiftMode(shiftKey: remaining, used: wasUsed)
            }

        case .shiftMode(let shiftKey, let used):
            if key == shiftKey {
                // シフトキーリリース → 単打判定
                if !used, let action = shiftKeyConfigs[shiftKey] ?? nil {
                    onShiftSingle?(action)
                }
                resetAll()
            }
            // else: 非シフトキーリリース → シフトモード継続
        }
    }

    /// バッファリセット（確定・キャンセル時に呼ぶ）
    public func reset() {
        resetAll()
    }

    // MARK: - chord 評価

    /// 2キー以上の chord グループを評価する
    ///
    /// キーの組み合わせビットで lookup テーブルと specialAction テーブルを検索する。
    /// chord マッチは specialAction より優先。3キー目で既存出力を差し替え可能。
    private func evaluateChord() {
        let bits = chordGroup.reduce(UInt64(0)) { $0 | $1.bit }
        let lookupBits = physicalShift ? (ChordKey.space.bit | bits) : bits

        // chord lookup（優先）
        if let text = lookupFunction(lookupBits) ?? (physicalShift ? lookupFunction(bits) : nil) {
            onOutput?(text, outputCharCount)
            outputCharCount = text.count
            pendingSpecialAction = nil
            chordOutputted = true
            return
        }

        // 特殊アクション（遅延: 3キー chord で上書きされる可能性がある）
        if let action = specialActionFunction(bits) {
            // 先行出力があれば巻き戻し（2キー chord → 2キー specialAction の場合）
            if outputCharCount > 0 {
                onOutput?("", outputCharCount)
                outputCharCount = 0
            }
            pendingSpecialAction = action
            chordOutputted = false
        }
    }

    // MARK: - シフトモード

    /// シフトキーホールド中のキーダウン処理
    ///
    /// シフト面の文字を出力し、used フラグを立てる。
    private func handleShiftModeKey(_ key: ChordKey, shiftKey: ChordKey) {
        let bits = shiftKey.bit | key.bit

        // 特殊アクション（SHFT+V=、, SHFT+M=。 等）
        if let action = specialActionFunction(bits) {
            onSpecialAction?(action)
            phase = .shiftMode(shiftKey: shiftKey, used: true)
            return
        }

        // シフト面の文字
        if let text = lookupFunction(bits) {
            onOutput?(text, 0)
            phase = .shiftMode(shiftKey: shiftKey, used: true)
            return
        }

        // シフト面にない組み合わせ → シフトが未使用なら単打アクション確定し、
        // キーを新規の chord グループとして処理
        if case .shiftMode(_, let used) = phase, !used,
           let action = shiftKeyConfigs[shiftKey] ?? nil {
            onShiftSingle?(action)
        }
        // シフトモード解除、新しい accumulating グループを開始
        // （シフトキーはまだ heldKeys にあるが chordGroup には含めない）
        chordGroup = [key]
        outputCharCount = 0
        pendingSpecialAction = nil
        chordOutputted = false
        phase = .accumulating
    }

    // MARK: - finalize（全キーリリース時）

    /// chord グループを確定する
    ///
    /// 全キーがリリースされた時に呼ばれる。
    /// 単打は keyUp 時にここで出力される。chord は既に keyDown 時に出力済み。
    private func finalize() {
        defer { resetAll() }

        if chordGroup.count == 1, let key = chordGroup.first {
            // 単打
            handleSingleTap(key)
        } else if chordGroup.count >= 2 {
            // 複数キー: 遅延中の特殊アクションを発火
            if let action = pendingSpecialAction {
                onSpecialAction?(action)
            }
        }
    }

    /// 単打出力（keyUp 時に発火）
    private func handleSingleTap(_ key: ChordKey) {
        if isShiftKey(key) {
            if let action = shiftKeyConfigs[key] ?? nil {
                onShiftSingle?(action)
            }
            return
        }

        let bits = key.bit

        // 特殊アクション（U=BS, T=←, Y=→ 等）
        if let action = specialActionFunction(bits) {
            onSpecialAction?(action)
            return
        }

        // 文字出力
        let lookupBits = physicalShift ? (ChordKey.space.bit | bits) : bits
        if let text = lookupFunction(lookupBits) ?? (physicalShift ? lookupFunction(bits) : nil) {
            onOutput?(text, 0)
        }
    }

    // MARK: - リセット

    /// chord グループの状態のみリセット（shiftMode 遷移時に使用）
    private func resetChordState() {
        chordGroup.removeAll()
        outputCharCount = 0
        pendingSpecialAction = nil
        chordOutputted = false
    }

    /// 全状態をリセット
    private func resetAll() {
        heldKeys.removeAll()
        resetChordState()
        phase = .accumulating
        physicalShift = false
    }
}
