import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// 変換エンジン層。AzooKeyKanaKanjiConverter を使ったかな漢字変換を管理する。
///
/// 使い方:
///   1. handleSequentialInput("k") → 逐次入力バッファで解決、displayText が更新される
///   2. requestConversion() → かな漢字変換候補を取得
///   3. confirmConversion() → 確定テキストを返す（学習データ更新）
///   4. cancelConversion() → 全てリセット
@Observable
public class InputManager {

    // MARK: - 変換状態

    public enum ConversionState {
        /// ローマ字入力中（ひらがなを表示）
        case composing
        /// 第1候補をプレビュー表示中（候補ウィンドウなし）
        ///
        /// Space を押すとこの状態に遷移する。
        /// もう一度 Space で `.selecting`（候補ウィンドウ表示）に移る。
        case previewing
        /// 変換候補を表示中
        case selecting
    }

    /// 入力モード（システムキーボードの状態に連動）
    public enum InputMode {
        /// 日本語入力（IME 変換あり）
        case japanese
        /// 英語直接入力（IME バイパス）
        case english
    }

    /// 日本語入力方式（逐次入力 / 同時打鍵 / 英数直接入力）
    public enum InputMethod: Hashable {
        /// 逐次入力（ローマ字入力等）
        case sequential
        /// 同時打鍵（薙刀式、NICOLA 等）。name はキーマップ名（表示用）。
        case chord(name: String)
        /// 英数直接入力（chord の F+G で切り替わるモード。H+J で chord に復帰）
        case directEnglish

        /// chord 系かどうか（chord / directEnglish の判定に使用）
        public var isChord: Bool {
            switch self {
            case .sequential: return false
            case .chord, .directEnglish: return true
            }
        }
    }

    /// 日本語モード時のスペース幅
    public enum SpaceWidth: String, CaseIterable, Sendable {
        /// 全角スペース（U+3000）
        case fullWidth
        /// 半角スペース（U+0020）
        case halfWidth

        /// 表示用ラベル
        public var label: String {
            switch self {
            case .fullWidth: return "全角"
            case .halfWidth: return "半角"
            }
        }
    }

    /// markedText の表示セグメント
    public enum DisplaySegmentFocus {
        /// 部分確定済み（細下線、黒）
        case confirmed
        /// 選択中の候補（太下線、青）
        case focused
        /// 未変換の残り部分（細下線、灰色）
        case unfocused
    }

    public struct DisplaySegment {
        public let text: String
        public let focus: DisplaySegmentFocus
    }

    /// 追加候補（英数・全角英数・カタカナ・ひらがな）
    public struct AdditionalCandidate {
        public let text: String
        /// 注釈テキスト（"英数", "全角英数", "カタカナ", "ひらがな"）
        public let annotation: String
    }

    // MARK: - Public Properties

    /// 現在の変換状態
    public private(set) var state: ConversionState = .composing

    /// 現在の入力モード（システムキーボードの状態に連動、または fullControlMode 時はアプリ制御）
    public private(set) var inputMode: InputMode = .japanese

    /// キー入力完全制御モード
    ///
    /// true の場合、システム IME の切替を無効化し、アプリ独自の英数/かなモードを使用する。
    /// LANG1/LANG2/CAPS LOCK 等のシステム IME トリガーキーをインターセプトする。
    public var fullControlMode: Bool = true

    /// 現在の日本語入力方式（UserDefaults に永続化）
    public var inputMethod: InputMethod = .sequential

    /// 日本語モード時のスペース幅（デフォルト: 全角、Shift+Space で逆転）
    public var japaneseSpaceWidth: SpaceWidth = .fullWidth

    /// 現在のモードと Shift 状態に応じたスペース文字を返す
    ///
    /// - 日本語モード: `japaneseSpaceWidth` に従う。Shift で逆転。
    /// - 英数モード: 常に半角。Shift で全角。
    public func spaceCharacter(shifted: Bool) -> String {
        let useFullWidth: Bool
        if inputMethod == .directEnglish {
            useFullWidth = shifted
        } else {
            useFullWidth = shifted ? (japaneseSpaceWidth != .fullWidth) : (japaneseSpaceWidth == .fullWidth)
        }
        return useFullWidth ? "\u{3000}" : " "
    }

    /// markedText に表示するセグメント配列
    ///
    /// selecting 状態で候補が入力の一部のみをカバーする場合、
    /// [選択候補(focused), 残りひらがな(unfocused)] の2セグメントを返す。
    public var displaySegments: [DisplaySegment] {
        var segments: [DisplaySegment] = []

        // 部分確定済みテキストを先頭に追加
        if !confirmedPrefix.isEmpty {
            segments.append(DisplaySegment(text: confirmedPrefix, focus: .confirmed))
        }

        switch state {
        case .composing:
            let text = liveConversionText ?? resolvedPrefixForConversion().convertTarget
            if !text.isEmpty {
                segments.append(DisplaySegment(text: text, focus: .unfocused))
            }
        case .previewing:
            // 第1候補のテキストを表示（候補ウィンドウは非表示）
            let text = previewText ?? resolvedPrefixForConversion().convertTarget
            if !text.isEmpty {
                segments.append(DisplaySegment(text: text, focus: .unfocused))
            }
        case .selecting:
            // 追加候補が選択されている場合、選択中の候補を focused で表示
            if isAdditionalCandidateSelected {
                let visible = visibleAdditionalCandidates
                if selectedAdditionalCandidateIndex < visible.count {
                    segments.append(DisplaySegment(text: visible[selectedAdditionalCandidateIndex].text, focus: .focused))
                } else if let first = visible.first {
                    segments.append(DisplaySegment(text: first.text, focus: .focused))
                }
                return segments
            }
            guard !candidates.isEmpty else {
                segments.append(DisplaySegment(text: resolvedPrefixForConversion().convertTarget, focus: .unfocused))
                return segments
            }
            let selected = candidates[selectedCandidateIndex]
            // コピーに prefixComplete を適用して残りを計算（実際の状態は変更しない）
            var afterComposing = composingText
            afterComposing.prefixComplete(composingCount: selected.composingCount)
            let remaining = afterComposing.convertTarget
            segments.append(DisplaySegment(text: selected.text, focus: .focused))
            if !remaining.isEmpty {
                segments.append(DisplaySegment(text: remaining, focus: .unfocused))
            }
        }
        return segments
    }

    /// markedText に表示する文字列（全セグメントの結合）
    public var displayText: String {
        displaySegments.map(\.text).joined()
    }

    /// 変換候補のテキスト配列（UI 表示用）
    public var candidateTexts: [String] {
        candidates.map(\.text)
    }

    /// 変換候補の配列
    public private(set) var candidates: [Candidate] = []

    /// 選択中の候補インデックス（全候補中の絶対位置）
    public private(set) var selectedCandidateIndex: Int = 0

    /// 候補ウィンドウの最大表示件数
    private static let windowSize = 9

    /// 現在表示中の候補ウィンドウ範囲（スライディングウィンドウ）
    public private(set) var visibleCandidateRange: ClosedRange<Int> = 0...0

    /// 現在表示中の候補テキスト配列（ウィンドウ内のみ、UI 表示用）
    public var visibleCandidateTexts: [String] {
        guard !candidates.isEmpty else { return [] }
        let range = clampedVisibleRange
        return range.map { candidates[$0].text }
    }

    /// ウィンドウ内での選択位置（0-based、数字キーラベル用）
    public var selectedIndexInWindow: Int {
        selectedCandidateIndex - clampedVisibleRange.lowerBound
    }

    /// 入力が空かどうか（confirmedPrefix・逐次入力バッファも考慮）
    public var isEmpty: Bool { composingText.isEmpty && confirmedPrefix.isEmpty && sequentialBuffer.isEmpty }

    /// previewing 状態で表示する第1候補のテキスト
    public private(set) var previewText: String?

    // MARK: - 追加候補

    /// 追加候補が選択されているかどうか
    public private(set) var isAdditionalCandidateSelected: Bool = false

    /// 追加候補内の選択インデックス（visibleAdditionalCandidates 内の位置、0-based）
    public private(set) var selectedAdditionalCandidateIndex: Int = 0

    /// 現在表示中の追加候補（上から順に: 最後に展開された候補が先頭）
    public var visibleAdditionalCandidates: [AdditionalCandidate] {
        let count = min(showingAdditionalCandidateCount, allAdditionalCandidates.count)
        guard count > 0 else { return [] }
        let startIndex = allAdditionalCandidates.count - count
        return Array(allAdditionalCandidates[startIndex...])
    }

    /// 追加候補の全リスト（英数, 全角英数, カタカナ, ひらがな の順。展開は末尾から）
    private var allAdditionalCandidates: [AdditionalCandidate] = []

    /// 現在表示中の追加候補数（0 = 非表示）
    private var showingAdditionalCandidateCount: Int = 0

    /// 部分確定済みのテキスト（即座に commit され、通常は空）
    public private(set) var confirmedPrefix: String = ""

    /// ライブ変換の結果テキスト（nil の場合はひらがなを表示）
    public private(set) var liveConversionText: String?

    /// エディタのフォントサイズ（候補ポップアップのサイズ連動用）
    public private(set) var editorFontSize: CGFloat = 18

    /// 直前に確定されたテキスト（左側コンテキスト用）
    ///
    /// 確定操作で自動蓄積されるほか、`setLeftSideContext(_:)` で外部から設定可能。
    public private(set) var leftSideContext: String = ""

    // MARK: - 設定トグル

    /// ライブ変換の有効/無効（デフォルト無効。エディタ再利用時に有効化可能）
    public var liveConversionEnabled: Bool = false

    /// 予測変換の有効/無効（デフォルト無効。エディタ再利用時に有効化可能）
    public var predictionEnabled: Bool = false

    /// 予測候補（composing 中に表示。変換候補とは別に管理）
    public private(set) var predictionCandidates: [PredictionItem] = []

    /// Tab キーで巡回選択中の予測候補インデックス（nil = 未選択）
    public private(set) var selectedPredictionIndex: Int?

    /// 動的ショートカットのレジストリ（日時展開等）
    public var dynamicShortcuts: [DynamicShortcut] = BuiltInShortcuts.dateTimeShortcuts

    /// 動的ショートカットの有効/無効
    public var dynamicShortcutsEnabled: Bool = true

    /// 同時打鍵判定ウィンドウ（秒）。同時打鍵方式の判定に使用。
    public var simultaneousWindow: TimeInterval = 0.080

    // MARK: - Zenzai DI

    /// Zenzai モデルファイルの URL（有料版から注入。nil なら辞書変換のみ）
    public var zenzaiWeightURL: URL?

    // MARK: - 逐次入力バッファ（カスタムテーブル用）

    /// カスタムテーブルの逐次入力バッファ（未解決のキーシーケンス）
    ///
    /// AzooKey の trie に頼らず、こちら側で入力テーブルの trie 解決を行う。
    /// 月配列等のカスタムテーブルでは、プレフィクスキー（"q" → "ql" の先頭）の
    /// バックトラックを AzooKey が行えないため、自前で greedy longest-match を実装する。
    private var sequentialBuffer: String = ""

    /// バックトラックのフォールバックで composingText に追加された生キー
    ///
    /// BS でバッファが空になった際に composingText から引き戻してバッファに復元するために使う。
    /// 非フォールバック（マッピング解決）の挿入が起きると無効化される。
    private var fallbackFlushedKeys: [String] = []

    /// 事前展開済みキーマップ（nil = カスタムテーブルなし → AzooKey trie を使用）
    public private(set) var activeKeymap: ExpandedKeymap?

    /// アクティブなカスタム入力マッピング（`activeKeymap` から導出）
    public var activeInputMappings: [String: String]? { activeKeymap?.inputMappings }

    // MARK: - Private Properties

    private let converter: KanaKanjiConverter
    private var composingText = ComposingText()

    /// direct 入力で蓄積された元の入力文字列（英数候補の生成用）
    ///
    /// AzooKey trie 経由の入力は composingText.input から復元できるが、
    /// `.direct` スタイル（カスタムテーブル・同時打鍵）では intention が nil のため復元不可。
    /// この変数で元のキー文字列を別途保持する。
    private var directRawInput: String = ""

    /// 文節区切り編集が行われたかどうか
    private var didExperienceSegmentEdition = false

    /// 学習データの保存先
    private let memoryDirectoryURL: URL

    // MARK: - 初期化

    public init() {
        converter = KanaKanjiConverter.withDefaultDictionary()
        memoryDirectoryURL = Self.makeMemoryDirectoryURL()

        // UserDefaults から設定を復元
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "simultaneousWindow") != nil {
            simultaneousWindow = defaults.double(forKey: "simultaneousWindow")
        }
        if let chordName = defaults.string(forKey: "chordKeymapName") {
            inputMethod = .chord(name: chordName)
        }
    }

    // MARK: - 入力モード

    /// 入力モードを設定する（システムキーボードの状態変更時に呼ばれる）
    public func setInputMode(_ mode: InputMode) {
        inputMode = mode
    }

    /// エディタのフォントサイズを設定する（候補ポップアップのサイズ連動用）
    public func setEditorFontSize(_ size: CGFloat) {
        editorFontSize = size
    }

    /// 左側コンテキストを外部から設定する（カーソル移動・ファイル開封時等）
    ///
    /// composing 中でないときに、カーソル左側のテキストを設定する。
    /// 最大30文字に切り詰められる。確定操作による自動蓄積とは独立して使用可能。
    public func setLeftSideContext(_ context: String) {
        leftSideContext = String(context.suffix(30))
    }

    /// 事前展開済みキーマップを設定する
    ///
    /// `ExpandedKeymap` の事前計算済みデータ（マッピング + プレフィックスセット）を
    /// そのまま適用する。ランタイムでのフィルタリングやプレフィックスセット構築が不要。
    ///
    /// - Parameter keymap: 事前展開済みキーマップ。nil でカスタムテーブルをクリア。
    public func updateKeymap(_ keymap: ExpandedKeymap?) {
        activeKeymap = keymap
        // バッファクリア（キーマップ切替時）
        sequentialBuffer = ""
        fallbackFlushedKeys.removeAll()
    }

    // MARK: - 入力操作

    /// かな文字を直接追加する（変換テーブルで解決済みのかな、全角記号等）
    ///
    /// 同時打鍵キーの QWERTY 文字を蓄積する（英数候補の生成用）
    ///
    /// `IMETextView` の `.chordInput` ハンドラから、chord buffer にキーを渡す前に呼ぶ。
    /// シフトキー（`.chordShiftDown`）は呼ばないこと（英数候補に不要なため）。
    public func recordChordKey(_ key: ChordKey) {
        if let c = key.character {
            directRawInput.append(c)
        }
    }

    /// `inputStyle: .direct` で挿入するため、AzooKey の内部 trie を経由せず
    /// 文字がそのまま ComposingText に入る。
    public func appendDirectKana(_ kana: String) {
        fallbackFlushedKeys.removeAll()
        composingText.insertAtCursorPosition(kana, inputStyle: .direct)
        if state == .selecting || state == .previewing {
            resetToComposing()
        }
        requestLiveConversion()
        requestPrediction()
    }

    // MARK: - 逐次入力バッファ操作（カスタムテーブル用）

    /// カスタムテーブル用の逐次入力を処理する
    ///
    /// AzooKey の trie に頼らず、こちら側で inputMappings の greedy longest-match を行う。
    /// 解決したかなは `.direct` スタイルで ComposingText に直接追加する。
    ///
    /// **背景**: AzooKey の trie はプレフィクスキーに raw terminal を登録できない
    /// （登録すると即座に解決されて "ql" → "ぞ" が壊れる）。そのため、
    /// "q" → "j" と打つと trie がバックトラックできず "qう" になってしまう。
    /// こちら側でバッファ管理することで "そう" に正しく解決される。
    public func handleSequentialInput(_ character: String) {
        directRawInput += character
        sequentialBuffer += character
        drainSequentialBuffer()
        if state == .selecting || state == .previewing {
            resetToComposing()
        }
        requestLiveConversion()
        requestPrediction()
    }

    /// 逐次入力バッファの仮解決テキスト（markedText 表示・変換候補取得用）
    ///
    /// バッファにたまっているキーシーケンスを inputMappings で仮解決した結果を返す。
    /// 月配列では全単打キーにマッピングがあるため、常にかな文字が返る。
    public var pendingBufferText: String {
        guard !sequentialBuffer.isEmpty, let mappings = activeKeymap?.inputMappings else { return "" }
        if let kana = mappings[sequentialBuffer] { return kana }
        // バッファ全体にマッチがない場合、最長マッチで再帰的に解決
        var result = ""
        var remaining = sequentialBuffer
        while !remaining.isEmpty {
            var matched = false
            for len in stride(from: remaining.count, through: 1, by: -1) {
                let prefix = String(remaining.prefix(len))
                if let kana = mappings[prefix] {
                    result += kana
                    remaining = String(remaining.dropFirst(len))
                    matched = true
                    break
                }
            }
            if !matched {
                result += String(remaining.prefix(1))
                remaining = String(remaining.dropFirst())
            }
        }
        return result
    }

    /// バッファを可能な限り解決する（greedy longest-match + バックトラック）
    ///
    /// - バッファがマッピングに完全一致し、かつより長いマッピングのプレフィクスでもない
    ///   → 即座に解決（例: "dq" → "ぁ"、"dq" は他のキーのプレフィクスではない）
    /// - バッファがプレフィクスに一致 → 次のキーを待つ（例: "d" は "dq" のプレフィクス）
    /// - どちらでもない → バックトラック（先頭から最長マッチを探して解決、残りを再処理）
    private func drainSequentialBuffer() {
        guard let keymap = activeKeymap, let mappings = keymap.inputMappings else { return }

        while !sequentialBuffer.isEmpty {
            let hasMatch = mappings[sequentialBuffer] != nil
            let isPrefix = keymap.prefixSet.contains(sequentialBuffer)

            if hasMatch && !isPrefix {
                // 一意マッチ → 即座に解決
                fallbackFlushedKeys.removeAll()
                composingText.insertAtCursorPosition(mappings[sequentialBuffer]!, inputStyle: .direct)
                sequentialBuffer = ""
            } else if isPrefix {
                // プレフィクスマッチ → 次のキーを待つ
                return
            } else {
                // マッチもプレフィクスもない → バックトラック（先頭から最長マッチ）
                var resolved = false
                for len in stride(from: sequentialBuffer.count - 1, through: 1, by: -1) {
                    let prefix = String(sequentialBuffer.prefix(len))
                    if mappings[prefix] != nil {
                        fallbackFlushedKeys.removeAll()
                        composingText.insertAtCursorPosition(mappings[prefix]!, inputStyle: .direct)
                        sequentialBuffer = String(sequentialBuffer.dropFirst(len))
                        resolved = true
                        break
                    }
                }
                if !resolved {
                    // 先頭1文字もマッチしない → 生文字として追加（フォールバック）
                    let rawChar = String(sequentialBuffer.prefix(1))
                    composingText.insertAtCursorPosition(rawChar, inputStyle: .direct)
                    fallbackFlushedKeys.append(rawChar)
                    sequentialBuffer = String(sequentialBuffer.dropFirst())
                }
            }
        }
    }

    /// バッファを強制解決する（確定・キャンセル前に呼ぶ）
    ///
    /// バッファに残っているキーシーケンスを最善の解決方法で ComposingText に追加する。
    /// 確定操作の前に呼び出して、バッファの内容を composingText に反映させる。
    private func flushSequentialBuffer() {
        guard !sequentialBuffer.isEmpty, let mappings = activeKeymap?.inputMappings else { return }
        // バッファ全体がマッピングにあればそのまま解決
        if let kana = mappings[sequentialBuffer] {
            composingText.insertAtCursorPosition(kana, inputStyle: .direct)
            sequentialBuffer = ""
            return
        }
        // なければ greedy 解決（drainSequentialBuffer が while で全て処理する）
        drainSequentialBuffer()
    }

    /// 薙刀式の先行出力を巻き戻す（直前の入力ピースを削除して新しい文字に差し替え）
    ///
    /// 同時打鍵で先行出力した文字を同時打鍵結果に差し替える際に使用する。
    /// `count` で削除するピース数を指定できる（3キー同時打鍵で2つの単打出力を
    /// まとめて差し替える場合は count=2）。
    public func replaceDirectKana(count: Int, with newKana: String) {
        fallbackFlushedKeys.removeAll()
        for _ in 0..<count {
            composingText.deleteBackwardFromCursorPosition(count: 1)
        }
        if newKana.isEmpty {
            // 空文字列の場合は削除のみ（特殊アクション前の巻き戻し）
            if composingText.isEmpty {
                resetState()
                return
            }
        } else {
            composingText.insertAtCursorPosition(newKana, inputStyle: .direct)
        }
        if state == .selecting || state == .previewing {
            resetToComposing()
        }
        requestLiveConversion()
        requestPrediction()
    }

    /// 末尾の1文字を削除する
    @discardableResult
    public func deleteBackward() -> DeleteResult {
        // 逐次入力バッファに未解決キーがある場合、バッファから削除
        if !sequentialBuffer.isEmpty {
            sequentialBuffer = String(sequentialBuffer.dropLast())
            // BS でバッファが空になった場合、フォールバックでフラッシュされた
            // 生キーを引き戻してバッファに復元する
            if sequentialBuffer.isEmpty, let lastRaw = fallbackFlushedKeys.last,
               activeKeymap?.prefixSet.contains(lastRaw) == true {
                fallbackFlushedKeys.removeLast()
                composingText.deleteBackwardFromCursorPosition(count: 1)
                sequentialBuffer = lastRaw
            }
            if sequentialBuffer.isEmpty && composingText.isEmpty {
                let prefix = confirmedPrefix
                resetState()
                return .finished(prefix.isEmpty ? nil : prefix)
            }
            if state == .selecting || state == .previewing {
                resetToComposing()
            }
            requestLiveConversion()
            return .continuing
        }
        // バッファが空で composingText から直接削除 → フォールバック履歴を無効化
        fallbackFlushedKeys.removeAll()
        // 文節編集中ならカーソルを末尾に戻してから削除（azooKey-Desktop 準拠）
        if !composingText.isAtEndIndex {
            let delta = composingText.convertTarget.count - composingText.convertTargetCursorPosition
            if delta > 0 {
                _ = composingText.moveCursorFromCursorPosition(count: delta)
            }
            didExperienceSegmentEdition = false
        }
        composingText.deleteBackwardFromCursorPosition(count: 1)
        if composingText.isEmpty {
            let prefix = confirmedPrefix
            resetState()
            return .finished(prefix.isEmpty ? nil : prefix)
        }
        if state == .selecting || state == .previewing {
            resetToComposing()
        }
        requestLiveConversion()
        return .continuing
    }

    // MARK: - 文節区切り編集

    /// 文節区切りを編集する（Shift+矢印キーで呼ばれる）
    ///
    /// `ComposingText` のカーソル位置を移動し、カーソル位置までのテキストで
    /// 変換候補を再取得する。azooKey-Desktop の `SegmentsManager.editSegment` と同等。
    ///
    /// - Parameter count: 正で右に拡張、負で左に縮小
    public func editSegment(count: Int) {
        flushSequentialBuffer()
        guard !composingText.isEmpty else { return }

        // 選択中の候補があれば、その候補の区切り位置にカーソルを合わせる
        if state == .selecting, !candidates.isEmpty {
            let selected = candidates[selectedCandidateIndex]
            var afterComposing = composingText
            afterComposing.prefixComplete(composingCount: selected.composingCount)
            let prefixCount = composingText.convertTarget.count - afterComposing.convertTarget.count
            _ = composingText.moveCursorFromCursorPosition(
                count: -composingText.convertTargetCursorPosition + prefixCount
            )
        }

        // カーソル移動
        if count > 0 {
            if composingText.isAtEndIndex && !didExperienceSegmentEdition {
                // 初回 Shift+Right & 末尾 → 先頭 + count にジャンプ
                _ = composingText.moveCursorFromCursorPosition(
                    count: -composingText.convertTargetCursorPosition + count
                )
            } else {
                _ = composingText.moveCursorFromCursorPosition(count: count)
            }
        } else {
            _ = composingText.moveCursorFromCursorPosition(count: count)
        }

        // 先頭（位置0）には行かせない（最低1文字は変換対象にする）
        if composingText.isAtStartIndex {
            _ = composingText.moveCursorFromCursorPosition(count: 1)
        }

        // 状態更新
        didExperienceSegmentEdition = true

        candidates = []
        selectedCandidateIndex = 0
        resetAdditionalCandidates()

        // 新しい区切りで変換リクエスト → selecting 状態へ
        // 文節編集は常に候補ウィンドウ付きの selecting に遷移する
        requestConversion(forceSelecting: true)
    }

    // MARK: - 変換操作

    /// 変換をリクエストする（Space キーで呼び出し）
    ///
    /// ライブ変換 OFF 時は `.previewing`（第1候補プレビュー、候補ウィンドウなし）に遷移。
    /// ライブ変換 ON 時は `.selecting`（候補ウィンドウ表示）に直接遷移。
    /// `.previewing` からの呼び出し（`forceSelecting: true`）は常に `.selecting` に遷移。
    public func requestConversion(forceSelecting: Bool = false) {
        flushSequentialBuffer()
        guard !composingText.isEmpty else { return }

        let prefixText = resolvedPrefixForConversion()
        let options = makeConvertRequestOptions()
        let result = converter.requestCandidates(prefixText, options: options)

        var allCandidates = result.mainResults
        // mainResults が空なら firstClauseResults をフォールバック
        if allCandidates.isEmpty {
            allCandidates = result.firstClauseResults
        }

        guard !allCandidates.isEmpty else { return }

        liveConversionText = nil
        predictionCandidates = []

        if forceSelecting || liveConversionEnabled {
            // forceSelecting / ライブ変換 ON: selecting に直接遷移
            previewText = nil
            candidates = allCandidates
            selectedCandidateIndex = 0
            resetVisibleRange()
            state = .selecting
        } else {
            // ライブ変換 OFF: previewing に遷移（第1候補のプレビューのみ）
            previewText = allCandidates.first?.text
            candidates = allCandidates
            selectedCandidateIndex = 0
            resetVisibleRange()
            state = .previewing
        }
    }

    /// 次の候補を選択する（Space 連打 / 下矢印）
    public func selectNextCandidate() {
        guard state == .selecting, !candidates.isEmpty else {
            requestConversion()
            return
        }
        // 追加候補内を下に移動
        if isAdditionalCandidateSelected {
            let visible = visibleAdditionalCandidates
            if selectedAdditionalCandidateIndex + 1 < visible.count {
                // 追加候補内の次へ
                selectedAdditionalCandidateIndex += 1
            } else {
                // 追加候補の末尾 → 通常候補の先頭へ
                isAdditionalCandidateSelected = false
                selectedAdditionalCandidateIndex = 0
                selectedCandidateIndex = 0
                updateVisibleRange()
            }
            return
        }
        selectedCandidateIndex = (selectedCandidateIndex + 1) % candidates.count
        updateVisibleRange()
    }

    /// 前の候補を選択する（上矢印）
    ///
    /// 通常候補の先頭（index 0）でさらに上を押すと、追加候補（ひらがな・カタカナ・英数）
    /// が段階的に展開される。展開済みの追加候補内では上キーで移動し、
    /// 最上部からさらに上を押すと新しい追加候補が展開される。
    public func selectPrevCandidate() {
        guard state == .selecting, !candidates.isEmpty else { return }

        // 追加候補が選択されている場合
        if isAdditionalCandidateSelected {
            if selectedAdditionalCandidateIndex > 0 {
                // 追加候補内を上に移動
                selectedAdditionalCandidateIndex -= 1
            } else {
                // 最上部でさらに上 → まだ展開可能なら1つ追加（新しい候補が先頭に入る）
                if showingAdditionalCandidateCount < allAdditionalCandidates.count {
                    showingAdditionalCandidateCount += 1
                    // selectedAdditionalCandidateIndex は 0 のまま（新しい先頭を選択）
                }
            }
            return
        }

        // 通常候補の先頭 → 追加候補を表示
        if selectedCandidateIndex == 0 {
            generateAdditionalCandidatesIfNeeded()
            if !allAdditionalCandidates.isEmpty {
                if showingAdditionalCandidateCount == 0 {
                    // 初回展開: 1つだけ表示
                    showingAdditionalCandidateCount = 1
                }
                // 既に展開済みなら追加展開せず、末尾（通常候補に最も近い位置）を選択
                isAdditionalCandidateSelected = true
                selectedAdditionalCandidateIndex = visibleAdditionalCandidates.count - 1
                return
            }
        }

        selectedCandidateIndex = max(0, selectedCandidateIndex - 1)
        updateVisibleRange()
    }

    /// ウィンドウ内の番号で候補を直接選択・確定する（数字キー 1-9）
    ///
    /// - Parameter offsetInWindow: ウィンドウ内の0-basedオフセット
    public func selectCandidateInWindow(at offsetInWindow: Int) -> ConfirmResult? {
        let absoluteIndex = clampedVisibleRange.lowerBound + offsetInWindow
        guard state == .selecting,
              absoluteIndex >= 0, absoluteIndex < candidates.count else { return nil }
        // 追加候補が選択されていても、数字キーは通常候補を直接選択
        isAdditionalCandidateSelected = false
        selectedCandidateIndex = absoluteIndex
        return confirmConversion()
    }

    // MARK: - 確定・キャンセル

    /// 変換確定の結果
    public enum ConfirmResult {
        /// 全文確定（composing 終了）。テキストを commit する。
        case full(String)
        /// 部分確定（残りのテキストで再変換中）。marked text のみ更新。
        case partial
    }

    /// deleteBackward の結果
    public enum DeleteResult {
        /// composingText に残りがある → marked text 更新
        case continuing
        /// composition 終了（commit するテキスト or nil）
        case finished(String?)
    }

    /// 選択中の候補を取得する
    public var selectedCandidate: Candidate? {
        guard state == .selecting, !candidates.isEmpty,
              candidates.indices.contains(selectedCandidateIndex) else { return nil }
        return candidates[selectedCandidateIndex]
    }

    /// 変換を確定し、結果を返す
    ///
    /// azooKey の submitSelectedCandidate + prefixCandidateCommited に相当。
    /// 候補が入力の一部のみをカバーする場合（部分変換）、
    /// confirmedPrefix に蓄積し marked text のみ更新する。
    /// 全文確定時にのみ commitText が必要な `.full` を返す。
    ///
    /// - Parameter toPreviewing: 部分確定後に `.previewing` に遷移するか。
    ///   true: Enter/数字キーからの確定（残りがあれば `.previewing`）。
    ///   false: → キーからの確定（残りがあれば `.selecting` 維持）。
    @discardableResult
    public func confirmConversion(toPreviewing: Bool = true) -> ConfirmResult {
        flushSequentialBuffer()
        switch state {
        case .composing:
            // confirmedPrefix 分は部分確定時に既に leftSideContext に追加済み
            let remaining = liveConversionText ?? composingText.convertTarget
            let text = confirmedPrefix + remaining
            updateLeftSideContext(remaining)
            finalizeComposition()
            return .full(text)

        case .previewing:
            // previewing 中の確定: 第1候補テキストを確定
            let text = confirmedPrefix + (previewText ?? composingText.convertTarget)
            updateLeftSideContext(previewText ?? composingText.convertTarget)
            finalizeComposition()
            return .full(text)

        case .selecting:
            // 追加候補が選択されている場合
            if isAdditionalCandidateSelected {
                let visible = visibleAdditionalCandidates
                let idx = min(selectedAdditionalCandidateIndex, visible.count - 1)
                if idx >= 0, idx < visible.count {
                    let additional = visible[idx]
                    let text = confirmedPrefix + additional.text
                    updateLeftSideContext(additional.text)
                    finalizeComposition()
                    return .full(text)
                }
            }

            guard let selected = selectedCandidate else {
                let remaining = composingText.convertTarget
                let text = confirmedPrefix + remaining
                updateLeftSideContext(remaining)
                finalizeComposition()
                return .full(text)
            }

            let confirmedText = selected.text

            // 学習データを更新
            converter.setCompletedData(selected)
            converter.updateLearningData(selected)

            // prefixComplete で確定部分を除去（azooKey の prefixCandidateCommited と同等）
            composingText.prefixComplete(composingCount: selected.composingCount)

            if !composingText.isEmpty {
                // 部分確定: confirmedPrefix に蓄積し、残りのテキストで次の文節へ
                confirmedPrefix += confirmedText
                updateLeftSideContext(confirmedText)
                prepareNextSegment(toPreviewing: toPreviewing)
                return .partial
            }

            // 全文確定（confirmedPrefix 分は部分確定時に既に追加済み）
            let fullText = confirmedPrefix + confirmedText
            updateLeftSideContext(confirmedText)
            finalizeComposition()
            return .full(fullText)
        }
    }

    /// 変換をキャンセルする
    ///
    /// confirmedPrefix があれば返却し、呼び出し元が commit する。
    /// confirmedPrefix がなければ nil を返す（呼び出し元は clearMarkedText）。
    public func cancelConversion() -> String? {
        flushSequentialBuffer()
        let prefix = confirmedPrefix
        resetState()
        return prefix.isEmpty ? nil : prefix
    }

    /// 全てのテキストを確定する（selecting/previewing 中の文字キー入力時、句読点、モード切替等）
    ///
    /// azooKey の `.commitMarkedTextAndAppendPieceToMarkedText` の前半に相当。
    /// 選択中の候補テキスト＋残りのひらがなを一括で確定し、composing を終了する。
    /// 部分確定テキストは既に commit 済みのため displayText に含まれない。
    public func confirmAll() -> String {
        flushSequentialBuffer()
        let text = displayText
        // 追加候補が選択されている場合は学習データを更新しない
        if state == .selecting, !isAdditionalCandidateSelected, let selected = selectedCandidate {
            converter.setCompletedData(selected)
            converter.updateLearningData(selected)
        }
        updateLeftSideContext(text)
        finalizeComposition()
        return text
    }

    // MARK: - 変換形式を指定して確定

    /// 変換形式（macOS 標準 Ctrl+J,K,L,;,: 用）
    public enum ConversionForm {
        /// ひらがな（Ctrl+J）
        case hiragana
        /// カタカナ（Ctrl+K）
        case katakana
        /// 半角カタカナ（Ctrl+L）— macOS 標準（ことえり）準拠
        case halfWidthKatakana
        /// 全角英数（Ctrl+;）
        case fullWidthRoman
        /// 半角英数（Ctrl+:）
        case halfWidthRoman
    }

    /// 指定した変換形式で全文確定する（F6〜F10 の代替キーバインド用）
    ///
    /// composingText のひらがなを指定の形式に変換して確定する。
    /// confirmedPrefix がある場合はそれも含む。
    public func confirmWithForm(_ form: ConversionForm) -> String {
        flushSequentialBuffer()
        let hiragana = resolvedPrefixForConversion().convertTarget
        guard !hiragana.isEmpty else {
            let text = confirmedPrefix
            finalizeComposition()
            return text
        }

        let converted: String
        switch form {
        case .hiragana:
            converted = hiragana
        case .katakana:
            converted = hiragana.applyingTransform(.hiraganaToKatakana, reverse: false) ?? hiragana
        case .halfWidthKatakana:
            let katakana = hiragana.applyingTransform(.hiraganaToKatakana, reverse: false) ?? hiragana
            converted = katakana.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? katakana
        case .halfWidthRoman:
            converted = recoverRawInput()
        case .fullWidthRoman:
            let raw = recoverRawInput()
            converted = raw.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? raw
        }

        let text = confirmedPrefix + converted
        updateLeftSideContext(converted)
        finalizeComposition()
        return text
    }

    /// composingText の入力ピースから元のローマ字/記号文字列を復元する
    ///
    /// AzooKey trie 経由の入力は `.key(intention:)` で元のキー文字を復元可能。
    /// direct 入力（カスタムテーブル・同時打鍵）では `.character` ピースにかな文字が入り、
    /// 元のキー入力は `directRawInput` に別途保持されている。
    /// `directRawInput` が空でなければそちらを優先する。
    private func recoverRawInput() -> String {
        // direct 入力パス（カスタムテーブル・同時打鍵）では directRawInput に
        // 元のキー文字列が蓄積されている
        if !directRawInput.isEmpty {
            return directRawInput + sequentialBuffer
        }
        // AzooKey trie 経由の入力は composingText.input から復元
        let fromPieces = composingText.input.compactMap { element -> String? in
            switch element.piece {
            case .character(let c): return String(c)
            case .key(let intention, _, _): return intention.map { String($0) }
            case .compositionSeparator: return nil
            }
        }.joined() as String
        return fromPieces
    }

    /// selecting/previewing 状態から composing 状態に戻す（Escape で候補ウィンドウを閉じる）
    ///
    /// azooKey の `.hideCandidateWindow` + `.transition(.composing)` に相当。
    /// ライブ変換テキストを再取得して composing 状態に戻す。
    public func returnToComposing() {
        resetToComposing()
        requestLiveConversion()
    }

    /// previewing 状態から selecting 状態に遷移する（Space 再押下で候補ウィンドウ表示）
    ///
    /// azooKey の `.enterCandidateSelectionMode` に相当。
    /// 既に取得済みの候補リストをそのまま使い、候補ウィンドウを表示する。
    public func enterSelecting() {
        guard state == .previewing else { return }
        previewText = nil
        state = .selecting
    }

    // MARK: - Private: 確定ヘルパー

    /// 部分確定後、次の文節の候補を準備する
    ///
    /// azooKey の `prefixCandidateCommited` の残りテキスト処理に相当。
    /// カーソルを末尾に移動し、残りのテキストで変換をリクエストする。
    /// confirmedPrefix への蓄積と leftSideContext の更新は呼び出し元で行う。
    ///
    /// - Parameter toPreviewing: true なら `.previewing` に遷移（Enter/数字キーでの部分確定時）。
    ///   false なら通常の `requestConversion()` に委譲（→ キーでの部分確定時は `.selecting` 維持）。
    private func prepareNextSegment(toPreviewing: Bool = false) {
        // カーソルを末尾に移動（azooKey と同じ: 残り全体を次の変換対象にする）
        let cursorDelta = composingText.convertTarget.count - composingText.convertTargetCursorPosition
        if cursorDelta > 0 {
            _ = composingText.moveCursorFromCursorPosition(count: cursorDelta)
        }

        // 状態リセット（文節編集フラグもリセット）
        didExperienceSegmentEdition = false
        candidates = []
        selectedCandidateIndex = 0

        previewText = nil
        resetAdditionalCandidates()

        if toPreviewing {
            // 部分確定後に previewing に遷移（azooKey-Desktop の Enter 部分確定と同等）
            let prefixText = resolvedPrefixForConversion()
            let options = makeConvertRequestOptions()
            let result = converter.requestCandidates(prefixText, options: options)

            var allCandidates = result.mainResults
            if allCandidates.isEmpty {
                allCandidates = result.firstClauseResults
            }
            if let first = allCandidates.first {
                previewText = first.text
                candidates = allCandidates
                selectedCandidateIndex = 0
                resetVisibleRange()
                state = .previewing
            } else {
                state = .composing
                requestLiveConversion()
            }
        } else {
            // 残りのテキストで変換リクエスト → selecting 状態へ
            requestConversion(forceSelecting: true)
        }
    }

    /// composing 全体をリセットする（全文確定時）
    private func finalizeComposition() {
        sequentialBuffer = ""
        fallbackFlushedKeys.removeAll()
        directRawInput = ""
        confirmedPrefix = ""
        composingText.stopComposition()
        converter.stopComposition()
        converter.commitUpdateLearningData()
        candidates = []
        selectedCandidateIndex = 0
        liveConversionText = nil
        previewText = nil
        predictionCandidates = []
        didExperienceSegmentEdition = false
        resetAdditionalCandidates()
        state = .composing
    }

    // MARK: - Private

    /// 安全にクランプした表示範囲
    private var clampedVisibleRange: ClosedRange<Int> {
        guard !candidates.isEmpty else { return 0...0 }
        let lower = max(0, min(visibleCandidateRange.lowerBound, candidates.count - 1))
        let upper = min(candidates.count - 1, visibleCandidateRange.upperBound)
        return lower...max(lower, upper)
    }

    /// 候補リスト変更時にウィンドウを先頭にリセットする
    private func resetVisibleRange() {
        let maxIndex = max(0, candidates.count - 1)
        let upper = min(Self.windowSize - 1, maxIndex)
        visibleCandidateRange = 0...upper
    }

    /// 選択位置に合わせてウィンドウをスライドする
    private func updateVisibleRange() {
        guard !candidates.isEmpty else { return }
        let current = clampedVisibleRange
        if selectedCandidateIndex < current.lowerBound {
            // 上にはみ出た → 選択位置をウィンドウの先頭に
            let upper = min(selectedCandidateIndex + Self.windowSize - 1, candidates.count - 1)
            visibleCandidateRange = selectedCandidateIndex...upper
        } else if selectedCandidateIndex > current.upperBound {
            // 下にはみ出た → 選択位置をウィンドウの末尾に
            let lower = max(selectedCandidateIndex - Self.windowSize + 1, 0)
            visibleCandidateRange = lower...selectedCandidateIndex
        }
    }

    // MARK: - 追加候補

    /// 追加候補（英数・全角英数・カタカナ・ひらがな）を生成する
    ///
    /// azooKey-Desktop の `createAdditionalCandidates` に相当。
    /// 展開は末尾から（ひらがな → カタカナ → 全角英数 → 英数）。
    /// テキストが重複する候補は除外する。
    private func generateAdditionalCandidatesIfNeeded() {
        guard allAdditionalCandidates.isEmpty else { return }
        let hiragana = resolvedPrefixForConversion().convertTarget
        guard !hiragana.isEmpty else { return }

        // composingText の入力ピースから元のローマ字/記号文字列を復元
        let rawInput = recoverRawInput()

        // 各種変換テキストを生成
        let halfWidthRoman = rawInput.applyingTransform(StringTransform.fullwidthToHalfwidth, reverse: false)
        let fullWidthRoman = rawInput.applyingTransform(StringTransform.fullwidthToHalfwidth, reverse: true)
        let katakana = hiragana.applyingTransform(.hiraganaToKatakana, reverse: false)

        // 動的ショートカット候補（読みが一致するもの）
        var dynamicCandidates: [(text: String?, annotation: String)] = []
        if dynamicShortcutsEnabled {
            for shortcut in dynamicShortcuts where shortcut.reading == hiragana {
                dynamicCandidates.append((shortcut.resolve(), shortcut.annotation))
            }
        }

        // 候補を組み立て（展開は末尾から行われるため、先に出したい候補を後ろに配置）
        let rawCandidates: [(text: String?, annotation: String)] =
            [(halfWidthRoman, "英数"),
             (fullWidthRoman, "全角英数"),
             (katakana, "カタカナ"),
             (hiragana, "ひらがな")]
            + dynamicCandidates

        // nil とテキスト重複を除外
        var seenTexts: Set<String> = []
        allAdditionalCandidates = rawCandidates.compactMap { candidate in
            guard let text = candidate.text, !text.isEmpty,
                  seenTexts.insert(text).inserted else { return nil }
            return AdditionalCandidate(text: text, annotation: candidate.annotation)
        }
    }

    /// 追加候補の状態をリセットする
    private func resetAdditionalCandidates() {
        allAdditionalCandidates = []
        showingAdditionalCandidateCount = 0
        isAdditionalCandidateSelected = false
        selectedAdditionalCandidateIndex = 0
    }

    /// 左側コンテキストを更新する（直近30文字に制限）
    private func updateLeftSideContext(_ confirmedText: String) {
        leftSideContext += confirmedText
        if leftSideContext.count > 30 {
            leftSideContext = String(leftSideContext.suffix(30))
        }
    }

    private func resetState() {
        sequentialBuffer = ""
        fallbackFlushedKeys.removeAll()
        confirmedPrefix = ""
        composingText.stopComposition()
        converter.stopComposition()
        candidates = []
        selectedCandidateIndex = 0
        liveConversionText = nil
        previewText = nil
        predictionCandidates = []
        didExperienceSegmentEdition = false
        resetAdditionalCandidates()
        state = .composing
    }

    /// selecting/previewing → composing の共通リセット
    ///
    /// 文字追加・BS・Escape 等で composing に戻る際の状態クリーンアップ。
    /// 5 箇所で同一のリセットコードが重複していたため一元化した。
    private func resetToComposing() {
        state = .composing
        candidates = []
        selectedCandidateIndex = 0
        previewText = nil
        didExperienceSegmentEdition = false
        resetAdditionalCandidates()
    }

    /// 変換リクエスト用に trailing ローマ字を解決した ComposingText を返す
    ///
    /// 末尾の未確定ローマ字（例: trailing "n"）を `compositionSeparator` で解決する。
    /// AzooKey のローマ字テーブルでは `[n, compositionSeparator] → [ん]` が定義されており、
    /// これにより "かんぜn" → "かんぜん" として変換候補を取得できる。
    private func resolvedPrefixForConversion() -> ComposingText {
        var text = composingText.prefixToCursorPosition()
        // 逐次入力バッファの仮解決テキストを追加
        let pending = pendingBufferText
        if !pending.isEmpty {
            text.insertAtCursorPosition(pending, inputStyle: .direct)
        }
        text.insertAtCursorPosition([
            ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .direct)
        ])
        return text
    }

    /// ライブ変換を実行する（キーストロークごとに呼ばれる）
    private func requestLiveConversion() {
        guard liveConversionEnabled, !(composingText.isEmpty && sequentialBuffer.isEmpty) else {
            liveConversionText = nil
            return
        }
        let prefixText = resolvedPrefixForConversion()
        let options = makeLiveConvertRequestOptions()
        let result = converter.requestCandidates(prefixText, options: options)

        if let best = result.mainResults.first ?? result.firstClauseResults.first {
            liveConversionText = best.text
        } else {
            liveConversionText = nil
        }
    }

    // MARK: - 予測変換

    /// 予測候補の最大件数
    private static let maxPredictions = 3

    /// composing 中に予測候補を取得する
    ///
    /// `predictionEnabled` が true かつ composing 中の場合に呼ばれる。
    /// 動的ショートカット（日時等）があれば先頭に追加する。
    private func requestPrediction() {
        guard predictionEnabled, state == .composing,
              !(composingText.isEmpty && sequentialBuffer.isEmpty) else {
            predictionCandidates = []
            return
        }

        var items: [PredictionItem] = []

        // 動的ショートカットの展開（読みが一致するもの）
        if dynamicShortcutsEnabled {
            let currentReading = resolvedPrefixForConversion().convertTarget
            for shortcut in dynamicShortcuts where shortcut.reading == currentReading {
                items.append(PredictionItem(
                    text: shortcut.resolve(),
                    annotation: shortcut.annotation
                ))
            }
        }

        // 変換エンジンの予測候補（軽量リクエスト）
        let prefixText = resolvedPrefixForConversion()
        let options = makePredictionRequestOptions()
        let result = converter.requestCandidates(prefixText, options: options)

        let currentText = prefixText.convertTarget
        let engineCandidates = (result.mainResults + result.firstClauseResults)
            .map(\.text)
            .filter { $0 != currentText }  // 入力と同一の候補を除外

        // 重複除去して追加
        var seen = Set(items.map(\.text))
        for text in engineCandidates {
            guard seen.insert(text).inserted else { continue }
            items.append(PredictionItem(text: text))
            if items.count >= Self.maxPredictions { break }
        }

        predictionCandidates = Array(items.prefix(Self.maxPredictions))
        selectedPredictionIndex = nil
    }

    /// 予測候補を Tab で巡回選択する
    ///
    /// 未選択 → 0 → 1 → 2 → nil（選択解除）→ 0 と巡回する。
    public func selectNextPrediction() {
        guard !predictionCandidates.isEmpty else { return }
        if let current = selectedPredictionIndex {
            let next = current + 1
            if next >= predictionCandidates.count {
                selectedPredictionIndex = nil  // 末尾を超えたら選択解除
            } else {
                selectedPredictionIndex = next
            }
        } else {
            selectedPredictionIndex = 0
        }
    }

    /// 予測候補を確定する
    ///
    /// - Parameter index: 確定する予測候補のインデックス（デフォルト 0 = 先頭）
    /// - Returns: 確定テキスト（commitText に渡す）。候補がなければ nil
    public func acceptPrediction(at index: Int = 0) -> String? {
        guard index < predictionCandidates.count else { return nil }
        let text = confirmedPrefix + predictionCandidates[index].text
        updateLeftSideContext(predictionCandidates[index].text)
        finalizeComposition()
        return text
    }

    /// 予測候補用の軽量リクエストオプション
    private func makePredictionRequestOptions() -> ConvertRequestOptions {
        ConvertRequestOptions(
            N_best: 5,
            requireJapanesePrediction: .autoMix,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            learningType: .inputAndOutput,
            memoryDirectoryURL: memoryDirectoryURL,
            sharedContainerURL: memoryDirectoryURL,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            zenzaiMode: makeZenzaiMode(inferenceLimit: 3, richCandidates: false),
            metadata: .init(versionString: "1.0")
        )
    }

    /// ライブ変換用の軽量オプション（パフォーマンス優先）
    private func makeLiveConvertRequestOptions() -> ConvertRequestOptions {
        ConvertRequestOptions(
            N_best: 1,
            requireJapanesePrediction: .disabled,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            learningType: .inputAndOutput,
            memoryDirectoryURL: memoryDirectoryURL,
            sharedContainerURL: memoryDirectoryURL,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            zenzaiMode: makeZenzaiMode(inferenceLimit: 1, richCandidates: false),
            metadata: .init(versionString: "1.0")
        )
    }

    /// 変換リクエストオプションを生成する
    private func makeConvertRequestOptions() -> ConvertRequestOptions {
        ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: predictionEnabled ? .autoMix : .disabled,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            learningType: .inputAndOutput,
            memoryDirectoryURL: memoryDirectoryURL,
            sharedContainerURL: memoryDirectoryURL,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            zenzaiMode: makeZenzaiMode(inferenceLimit: 10, richCandidates: true),
            metadata: .init(versionString: "1.0")
        )
    }

    /// Zenzai モード設定を生成する（zenzaiWeightURL が nil なら .off）
    private func makeZenzaiMode(
        inferenceLimit: Int,
        richCandidates: Bool
    ) -> ConvertRequestOptions.ZenzaiMode {
        guard let weightURL = zenzaiWeightURL else { return .off }
        return .on(
            weight: weightURL,
            inferenceLimit: inferenceLimit,
            requestRichCandidates: richCandidates,
            personalizationMode: nil,
            versionDependentMode: .v3(.init(leftSideContext: leftSideContext))
        )
    }


    /// 学習データ保存先ディレクトリを作成する
    private static func makeMemoryDirectoryURL() -> URL {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("AzooKeyMemory", isDirectory: true)
        }
        let dir = documentsURL.appendingPathComponent("AzooKeyMemory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
