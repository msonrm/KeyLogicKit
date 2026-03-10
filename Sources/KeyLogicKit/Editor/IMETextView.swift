import UIKit

/// キー入力を横取りする UITextView サブクラス。
///
/// 設計原則:
///   - InputManager が変換状態の唯一の管理元。IMETextView は表示とキー入力の橋渡しのみ。
///   - composing 中は super.pressesBegan を呼ばない（UIKit が marked text を勝手に commit するため）。
///   - pressesBegan がハードウェアキーボードの唯一のハンドラ。
///   - insertText / deleteBackward はソフトウェアキーボード用のフォールバック。
public class IMETextView: UITextView {

    /// 変換管理（外部から注入）
    public var inputManager: InputManager?

    /// キーイベントログ用コールバック
    public var onKeyEvent: ((KeyEventInfo) -> Void)?

    /// キーダウン通知（可視化パネル用、HID コード + タイムスタンプ）
    public var onKeyDown: ((UIKeyboardHIDUsage, Date) -> Void)?

    /// キーアップ通知（可視化パネル用、HID コード + タイムスタンプ）
    public var onKeyUp: ((UIKeyboardHIDUsage, Date) -> Void)?

    /// 英数モード切替通知（レイヤー自動追従用）
    public var onEnglishModeChange: ((Bool) -> Void)?

    /// カーソル位置変更通知（候補ポップアップの配置用）
    public var onCaretRectChange: ((CGRect) -> Void)?

    /// 現在のキールーター（入力方式・キーボードレイアウトの切替で差し替え）
    public var keyRouter = KeyRouter(definition: DefaultKeymaps.romajiUS) {
        didSet { syncChordBufferTables() }
    }

    /// 同時打鍵判定ウィンドウを設定する
    public func setSimultaneousWindow(_ window: TimeInterval) {
        chordBuffer.simultaneousWindow = window
    }

    /// pressesBegan で super をブロックしたキーコードを追跡
    ///
    /// pressesEnded/pressesCancelled で super に渡すかどうかの判定に使う。
    /// pressesBegan で super を呼ばずにインターセプトしたキーは、
    /// pressesEnded でも super を呼ばない（UIKit の内部状態の不整合を防ぐ）。
    private var interceptedKeyCodes: Set<UIKeyboardHIDUsage> = []

    /// 同時打鍵バッファ（chord 方式の入力で使用）
    private let chordBuffer = SimultaneousKeyBuffer()

    /// テキスト選択のアンカー位置（SHFT+T/Y の選択起点）
    ///
    /// 標準テキストエディタでは Shift+矢印は「アンカー（固定端）」と「アクティブエンド（移動端）」で
    /// 選択範囲を管理する。SHFT+T/Y はアクティブエンドを左右に移動させ、アンカーは固定。
    /// SHFT+T/Y 以外のキーが押されたらリセットする。
    private var selectionAnchor: UITextPosition?

    /// システムの入力モードが日本語かどうか
    private var isJapaneseInputMode: Bool {
        guard let lang = textInputMode?.primaryLanguage else { return true }
        return lang.hasPrefix("ja")
    }

    /// 現在のキーマップが指定 HID キーコードを処理するか（chord の hidToKey に含まれるか）
    private func keymapHandles(_ keyCode: UIKeyboardHIDUsage) -> Bool {
        guard case .chord(let config) = keyRouter.definition.behavior else { return false }
        return config.hidToKey[keyCode] != nil
    }

    /// InputManager の状態に基づく composing 判定
    private var isComposing: Bool {
        guard let im = inputManager else { return false }
        return !im.isEmpty
    }

    // MARK: - Key Event Info

    public struct KeyEventInfo {
        public let phase: String
        public let keyCode: UIKeyboardHIDUsage
        public let characters: String?
        public let modifiers: UIKeyModifierFlags
        public let handled: Bool
        public let timestamp: Date

        public var description: String {
            let modStr = modifierDescription(modifiers)
            let charStr = characters ?? "(none)"
            let handledStr = handled ? "intercepted" : "passed to super"
            let timeStr = Self.timestampFormatter.string(from: timestamp)
            return "[\(timeStr)] [\(phase)] keyCode=\(keyCode.rawValue) char=\"\(charStr)\" mod=\(modStr) → \(handledStr)"
        }

        private static let timestampFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f
        }()

        private func modifierDescription(_ flags: UIKeyModifierFlags) -> String {
            var parts: [String] = []
            if flags.contains(.command) { parts.append("Cmd") }
            if flags.contains(.shift) { parts.append("Shift") }
            if flags.contains(.alternate) { parts.append("Opt") }
            if flags.contains(.control) { parts.append("Ctrl") }
            return parts.isEmpty ? "none" : parts.joined(separator: "+")
        }
    }

    // MARK: - 入力モード監視

    /// 入力モード変更の監視を開始する
    public func setupInputModeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(inputModeDidChange),
            name: UITextInputMode.currentInputModeDidChangeNotification,
            object: nil
        )
        // 初期状態を反映
        inputModeDidChange()
        // 同時打鍵バッファのコールバック設定
        setupChordBuffer()
    }

    /// 同時打鍵バッファのコールバックを設定する
    ///
    /// chord 方式の入力で SimultaneousKeyBuffer が出力を確定した際に呼ばれる。
    /// テキスト出力、シフトキー単打、特殊アクション（BS, 矢印, Enter 等）を処理する。
    private func setupChordBuffer() {
        chordBuffer.onOutput = { [weak self] text, replaceCount in
            guard let self, let im = self.inputManager else { return }
            if im.inputMethod == .directEnglish {
                // 英数モード: 直接挿入（composing なし）
                for _ in 0..<replaceCount {
                    self.deleteBackward()
                }
                if !text.isEmpty {
                    self.rawInsertText(text)
                }
            } else {
                // 同時打鍵: InputManager 経由で composing テキストに追加
                if replaceCount > 0 {
                    im.replaceDirectKana(count: replaceCount, with: text)
                } else {
                    im.appendDirectKana(text)
                }
                self.updateMarkedTextDisplay()
            }
        }
        chordBuffer.onShiftSingle = { [weak self] action in
            guard let self else { return }
            self.executeChordAction(action)
        }
        chordBuffer.onSpecialAction = { [weak self] action in
            guard let self else { return }
            self.executeChordAction(action)
        }
    }

    /// chord buffer からの特殊アクションを実行する
    ///
    /// `executeAction` は UIKey が必要なため、chord buffer のコールバックから直接呼べない。
    /// chord 固有の文脈（isComposing 判定、idle 時のカーソル移動等）を処理してから実行する。
    private func executeChordAction(_ action: KeyAction) {
        guard let im = inputManager else { return }
        switch action {
        case .convert:
            selectionAnchor = nil
            if isComposing {
                handleSpace(im)
            } else {
                insertText(" ")
            }
        case .deleteBack:
            selectionAnchor = nil
            if isComposing {
                if im.state == .selecting || im.state == .previewing {
                    im.returnToComposing()
                    updateMarkedTextDisplay()
                } else {
                    handleDeleteBackward(im)
                }
            } else {
                deleteBackward()
            }
        case .moveLeft:
            selectionAnchor = nil
            if isComposing {
                // composing 中は消費（何もしない）
            } else {
                if let pos = selectedTextRange?.start,
                   let newPos = position(from: pos, offset: -1) {
                    selectedTextRange = textRange(from: newPos, to: newPos)
                }
            }
        case .moveRight:
            selectionAnchor = nil
            if isComposing && (im.state == .selecting || im.state == .previewing) {
                confirmComposition(im, toPreviewing: false)
            } else if !isComposing {
                if let pos = selectedTextRange?.start,
                   let newPos = position(from: pos, offset: 1) {
                    selectedTextRange = textRange(from: newPos, to: newPos)
                }
            }
        case .editSegmentLeft:
            if isComposing {
                im.editSegment(count: -1)
                updateMarkedTextDisplay()
            } else {
                moveSelectionEdge(offset: -1)
            }
        case .editSegmentRight:
            if isComposing {
                im.editSegment(count: 1)
                updateMarkedTextDisplay()
            } else {
                moveSelectionEdge(offset: 1)
            }
        case .confirm:
            selectionAnchor = nil
            if isComposing {
                confirmComposition(im)
            } else {
                insertText("\n")
            }
        case .insertAndConfirm(let text):
            selectionAnchor = nil
            if isComposing {
                let confirmed = im.confirmAll()
                commitText(confirmed)
                logEvent("chord-punct-confirm", detail: confirmed)
            }
            insertText(text)
        case .chordModeOff:
            selectionAnchor = nil
            if isComposing {
                let confirmed = im.confirmAll()
                commitText(confirmed)
                logEvent("chord-off-confirm", detail: confirmed)
            }
            chordBuffer.reset()
            switchToDirectEnglish()
            logEvent("chord-off", detail: "→ directEnglish")
        case .chordModeOn:
            selectionAnchor = nil
            if im.inputMethod == .directEnglish {
                chordBuffer.reset()
                switchToChordMode()
                logEvent("chord-on", detail: "→ chord")
            }
        default:
            break
        }
    }

    /// 英数直接入力モードに切り替える
    ///
    /// chord buffer のテーブルを英数用に差し替え、InputManager のモードを更新する。
    /// `inputManager.inputMethod` が唯一の真実の情報源（KeyRouter は struct のため
    /// SwiftUI の updateUIView で上書きされる可能性がある）。
    private func switchToDirectEnglish() {
        guard case .chord(let config) = keyRouter.definition.behavior else { return }
        if let englishLookup = config.englishLookupTable {
            chordBuffer.lookupFunction = { englishLookup[$0] }
        }
        if let englishActions = config.englishSpecialActions {
            chordBuffer.specialActionFunction = { englishActions[$0] }
        }
        inputManager?.inputMethod = .directEnglish
        onEnglishModeChange?(true)
    }

    /// 同時打鍵モードに復帰する
    private func switchToChordMode() {
        guard case .chord(let config) = keyRouter.definition.behavior else { return }
        let lookup = config.lookupTable
        chordBuffer.lookupFunction = { lookup[$0] }
        let actions = config.specialActions
        chordBuffer.specialActionFunction = { actions[$0] }
        inputManager?.inputMethod = .chord(name: keyRouter.definition.name)
        onEnglishModeChange?(false)
    }

    /// KeyRouter が外部から差し替えられた際に chord buffer のテーブルを同期する
    ///
    /// Picker で「ローマ字」↔「薙刀式」を切り替えた場合、chord buffer のテーブルが
    /// 古いまま（英数テーブル等）になる可能性があるため、KeyRouter の状態に合わせて復元する。
    private func syncChordBufferTables() {
        guard case .chord(let config) = keyRouter.definition.behavior else { return }
        // シフトキー設定を注入
        chordBuffer.shiftKeyConfigs = config.shiftKeys.reduce(into: [:]) {
            $0[$1.key] = $1.singleTapAction
        }
        if inputManager?.inputMethod == .directEnglish {
            if let englishLookup = config.englishLookupTable {
                chordBuffer.lookupFunction = { englishLookup[$0] }
            }
            if let englishActions = config.englishSpecialActions {
                chordBuffer.specialActionFunction = { englishActions[$0] }
            }
        } else {
            let lookup = config.lookupTable
            chordBuffer.lookupFunction = { lookup[$0] }
            let actions = config.specialActions
            chordBuffer.specialActionFunction = { actions[$0] }
        }
    }

    /// システムの入力モードが変わった時のハンドラ
    @objc private func inputModeDidChange() {
        let isJapanese = isJapaneseInputMode
        inputManager?.setInputMode(isJapanese ? .japanese : .english)

        // 日本語 → 英語に切り替わった時、composing 中なら全文確定
        if !isJapanese && isComposing {
            guard let im = inputManager else { return }
            let confirmed = im.confirmAll()
            commitText(confirmed)
            logEvent("mode-confirm", detail: confirmed)
        }
    }

    // MARK: - insertText / deleteBackward: ソフトウェアキーボード用フォールバック

    public override func insertText(_ text: String) {
        guard let im = inputManager else {
            super.insertText(text)
            return
        }
        // 英語モードならそのまま挿入
        if !isJapaneseInputMode {
            super.insertText(text)
            return
        }
        if isComposing { return }
        // sequential 入力の場合のみ composing 開始
        guard case .sequential(let characterMap) = keyRouter.definition.behavior else {
            super.insertText(text)
            return
        }
        // 全 printable character で composing 開始（keyRemap + characterMap 変換あり）
        // 制御文字（改行等）は除外（super.pressesBegan → insertText 経由で呼ばれる場合がある）
        let hasCustomTable = keyRouter.definition.inputMappings != nil
        let remap = keyRouter.definition.keyRemap
        if text.count == 1, let c = text.first,
           let scalar = c.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar) {
            let logical = remap?[String(c)]?.first ?? c
            guard characterMap[logical] != nil || logical.isLetter || hasCustomTable else {
                super.insertText(text)
                return
            }
            addPrintableToComposing(c, inputManager: im, characterMap: characterMap)
            updateMarkedTextDisplay()
            logEvent("sw-compose-start", detail: im.displayText)
        } else {
            super.insertText(text)
        }
    }

    public override func deleteBackward() {
        guard isComposing, let im = inputManager else {
            super.deleteBackward()
            return
        }
        handleDeleteBackward(im)
    }

    // MARK: - pressesBegan: 唯一のキー入力ハンドラ

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key else {
            super.pressesBegan(presses, with: event)
            return
        }

        // Cmd+ 系は常に super（コピペ等）
        if key.modifierFlags.contains(.command) {
            logKeyEvent(phase: "began", key: key, handled: false)
            super.pressesBegan(presses, with: event)
            return
        }

        // LANG1（かな/変換）/ LANG2（英数/無変換）:
        // キーマップの hidToKey にマッピングがあれば KeyRouter に任せる（親指シフト等）。
        // マッピングがなければ super に委譲してシステム IME 切替に使う。
        if key.keyCode == .keyboardLANG2 && !keymapHandles(key.keyCode) {
            if isComposing, let im = inputManager {
                let confirmed = im.confirmAll()
                commitText(confirmed)
                logEvent("eisu-confirm", detail: confirmed)
            }
            logKeyEvent(phase: "began", key: key, handled: false)
            super.pressesBegan(presses, with: event)
            return
        }
        if key.keyCode == .keyboardLANG1 && !keymapHandles(key.keyCode) {
            logKeyEvent(phase: "began", key: key, handled: false)
            super.pressesBegan(presses, with: event)
            return
        }

        // 英語モードなら IME をバイパスし、全てのキーを super に委譲
        if !isJapaneseInputMode {
            logKeyEvent(phase: "began", key: key, handled: false)
            super.pressesBegan(presses, with: event)
            return
        }

        guard let im = inputManager else {
            logKeyEvent(phase: "began", key: key, handled: false)
            super.pressesBegan(presses, with: event)
            return
        }

        // KeyRouter にルーティングを委譲
        let isDirectEnglish = im.inputMethod == .directEnglish
        let action = keyRouter.route(key, isComposing: isComposing, state: im.state,
                                     isDirectEnglishMode: isDirectEnglish)
        executeAction(action, key: key, inputManager: im, presses: presses, event: event)
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key else {
            super.pressesEnded(presses, with: event)
            return
        }
        // 可視化パネル向けキーアップ通知
        onKeyUp?(key.keyCode, Date())
        // chord 方式: キーアップ通知
        if case .chord(let config) = keyRouter.definition.behavior {
            if let chordKey = config.hidToKey[key.keyCode] {
                chordBuffer.keyUp(chordKey)
            }
        }
        // pressesBegan でインターセプトしたキーは super に渡さない
        if interceptedKeyCodes.remove(key.keyCode) != nil {
            return
        }
        super.pressesEnded(presses, with: event)
    }

    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key else {
            super.pressesCancelled(presses, with: event)
            return
        }
        // chord 方式: キーアップ通知
        if case .chord(let config) = keyRouter.definition.behavior {
            if let chordKey = config.hidToKey[key.keyCode] {
                chordBuffer.keyUp(chordKey)
            }
        }
        if interceptedKeyCodes.remove(key.keyCode) != nil {
            return
        }
        super.pressesCancelled(presses, with: event)
    }

    // MARK: - Action Execution

    /// KeyAction を実行する（全入力方式で共通）
    ///
    /// KeyRouter が決定したアクションを UITextView 操作に変換する。
    /// この1箇所に全てのアクション実行を集約することで、
    /// 入力方式ごとの重複コードを排除する。
    private func executeAction(_ action: KeyAction, key: UIKey, inputManager im: InputManager,
                               presses: Set<UIPress>, event: UIPressesEvent?) {
        switch action {
        case .pass:
            if isComposing {
                // composing 中は super を呼ばない（UIKit が marked text を勝手に commit するため）
                // chord 方式の場合はバッファもリセット
                if case .chord = keyRouter.definition.behavior {
                    chordBuffer.reset()
                }
                interceptedKeyCodes.insert(key.keyCode)
                logKeyEvent(phase: "began", key: key, handled: true)
            } else {
                logKeyEvent(phase: "began", key: key, handled: false)
                super.pressesBegan(presses, with: event)
            }

        case .printable(let c):
            interceptedKeyCodes.insert(key.keyCode)
            selectionAnchor = nil

            // selecting/previewing 中 → 確定して新しい composing を開始
            if im.state == .selecting || im.state == .previewing {
                let confirmed = im.confirmAll()
                commitText(confirmed)
                logEvent("select-and-continue", detail: confirmed)
            }

            guard case .sequential(let characterMap) = keyRouter.definition.behavior else { return }
            addPrintableToComposing(c, inputManager: im, characterMap: characterMap)
            updateMarkedTextDisplay()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .confirm:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            confirmComposition(im)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .cancel:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            if im.state == .selecting || im.state == .previewing {
                // selecting/previewing → composing に戻す
                im.returnToComposing()
                updateMarkedTextDisplay()
                logEvent("escape-to-composing", detail: im.displayText)
            } else {
                cancelComposition(im)
            }
            logKeyEvent(phase: "began", key: key, handled: true)

        case .convert:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            handleSpace(im)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .convertPrev:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            im.selectPrevCandidate()
            updateMarkedTextDisplay()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .deleteBack:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            if im.state == .selecting || im.state == .previewing {
                // macOS 標準 IME 準拠: selecting/previewing 中の BS は
                // まず composing に戻す（削除なし）。実際の削除は2回目の BS から。
                im.returnToComposing()
                updateMarkedTextDisplay()
                logEvent("bs-to-composing", detail: im.displayText)
            } else {
                handleDeleteBackward(im)
            }
            logKeyEvent(phase: "began", key: key, handled: true)

        case .moveLeft:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            // composing/previewing/selecting 全状態で消費のみ（azooKey-Desktop / macOS 標準準拠）
            logKeyEvent(phase: "began", key: key, handled: true)

        case .moveRight:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            if im.state == .selecting || im.state == .previewing {
                // → キーからの確定: 残りがあれば selecting 維持
                confirmComposition(im, toPreviewing: false)
            }
            // composing 中は消費のみ
            logKeyEvent(phase: "began", key: key, handled: true)

        case .moveUp:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            if im.state == .selecting {
                im.selectPrevCandidate()
                updateMarkedTextDisplay()
            }
            // composing/previewing 中は消費のみ
            logKeyEvent(phase: "began", key: key, handled: true)

        case .moveDown:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            if im.state == .selecting {
                im.selectNextCandidate()
                updateMarkedTextDisplay()
            } else if im.state == .previewing {
                // previewing 中の↓ → selecting に遷移
                im.enterSelecting()
                updateMarkedTextDisplay()
                logEvent("down-to-selecting", detail: im.displayText)
            } else {
                im.requestConversion()
                updateMarkedTextDisplay()
                logEvent("convert-down", detail: im.displayText)
            }
            logKeyEvent(phase: "began", key: key, handled: true)

        case .editSegmentLeft:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            im.editSegment(count: -1)
            updateMarkedTextDisplay()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .editSegmentRight:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            im.editSegment(count: 1)
            updateMarkedTextDisplay()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .selectCandidate(let offset):
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            if let result = im.selectCandidateInWindow(at: offset) {
                switch result {
                case .full(let confirmed):
                    commitText(confirmed)
                    logEvent("select-\(offset + 1)", detail: confirmed)
                case .partial:
                    updateMarkedTextDisplay()
                    logEvent("partial-select-\(offset + 1)", detail: im.displayText)
                }
            }
            logKeyEvent(phase: "began", key: key, handled: true)

        case .confirmHiragana:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.hiragana)
            commitText(confirmed)
            logEvent("ctrl-j-hiragana", detail: confirmed)

        case .confirmKatakana:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.katakana)
            commitText(confirmed)
            logEvent("ctrl-k-katakana", detail: confirmed)

        case .confirmHalfWidthKatakana:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.halfWidthKatakana)
            commitText(confirmed)
            logEvent("ctrl-l-halfkana", detail: confirmed)

        case .confirmHalfWidthRoman:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.halfWidthRoman)
            commitText(confirmed)
            logEvent("ctrl-colon-halfwidth", detail: confirmed)

        case .confirmFullWidthRoman:
            interceptedKeyCodes.insert(key.keyCode)
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.fullWidthRoman)
            commitText(confirmed)
            logEvent("ctrl-semicolon-fullwidth", detail: confirmed)

        case .chordInput(let chordKey):
            selectionAnchor = nil
            interceptedKeyCodes.insert(key.keyCode)

            // selecting/previewing 中に文字キーを押した場合 → 確定して新規 composing
            if im.state == .selecting || im.state == .previewing {
                chordBuffer.reset()
                let confirmed = im.confirmAll()
                commitText(confirmed)
                logEvent("chord-select-and-continue", detail: confirmed)
            }

            // 英数モード + 物理 Shift → lookup 時に shift ビットを合成して大文字を出力
            chordBuffer.physicalShift = im.inputMethod == .directEnglish
                && key.modifierFlags.contains(.shift)
            chordBuffer.keyDown(chordKey)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .chordShiftDown(let shiftKey):
            interceptedKeyCodes.insert(key.keyCode)
            chordBuffer.keyDown(shiftKey)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .directInsert(let text):
            interceptedKeyCodes.insert(key.keyCode)
            rawInsertText(text)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .insertAndConfirm, .chordModeOff, .chordModeOn:
            // chord buffer のコールバック経由でのみ発火するアクション。
            // executeChordAction() で処理済みなので、ここでは何もしない。
            break
        }
    }

    /// chord 方式の場合、バッファをリセットする
    private func resetChordBufferIfNeeded() {
        if case .chord = keyRouter.definition.behavior {
            chordBuffer.reset()
        }
    }

    // MARK: - Text Commit

    /// テキストを UITextView に直接挿入する（insertText override をバイパス）
    ///
    /// 英数直接入力モードで使用。`self.insertText()` は override で composing 開始されるため、
    /// `super.insertText()` を呼ぶヘルパーが必要（クロージャ内から super を直接呼べないため）。
    private func rawInsertText(_ text: String) {
        super.insertText(text)
    }

    /// printable character を composing テキストに追加する（keyRemap + characterMap 変換あり）
    ///
    /// 1. keyRemap: 物理キー→論理キー変換（大西配列等のキーリマップ）
    /// 2. characterMap: 論理キー→全角文字変換（数字・記号の全角化）
    /// 3. カスタムテーブル or ローマ字テーブルで処理
    private func addPrintableToComposing(_ c: Character, inputManager im: InputManager,
                                         characterMap: [Character: Character]) {
        // keyRemap: 物理キー→論理キー変換（バッファに入る前に適用）
        let logical: Character
        if let remap = keyRouter.definition.keyRemap,
           let remapped = remap[String(c)]?.first {
            logical = remapped
        } else {
            logical = c
        }

        if let mapped = characterMap[logical] {
            im.appendDirectKana(String(mapped))
        } else if im.activeInputMappings != nil {
            im.handleSequentialInput(String(logical))
        } else {
            im.appendDirectKana(String(logical))
        }
    }

    /// markedText を確定テキストで置き換える
    ///
    /// composition を正しく終了してから、確定テキストを通常テキストとして挿入する。
    /// `setMarkedText("") → unmarkText()` で UIKit の composition ライフサイクルを
    /// 完結させた後に `insertText` を呼ぶことで、UIKit の内部状態が確実にクリアされる。
    private func commitText(_ text: String) {
        removeMarkedTextAttributes()
        // composition を正しく終了（marked text を削除 → composition 解除）
        setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        unmarkText()
        // 確定テキストを通常テキストとして挿入（composition は既に終了済み）
        super.insertText(text)
    }

    // MARK: - Composition Actions

    private func handleSpace(_ im: InputManager) {
        switch im.state {
        case .composing:
            // 初回 Space → 変換リクエスト（ライブ変換 OFF なら previewing へ）
            im.requestConversion()
            updateMarkedTextDisplay()
            logEvent("convert", detail: im.displayText)
        case .previewing:
            // previewing 中の Space → selecting に遷移（候補ウィンドウ表示）
            im.enterSelecting()
            updateMarkedTextDisplay()
            logEvent("preview-to-selecting", detail: im.displayText)
        case .selecting:
            // 連続 Space → 次の候補
            im.selectNextCandidate()
            updateMarkedTextDisplay()
            logEvent("next-candidate", detail: im.displayText)
        }
    }

    private func confirmComposition(_ im: InputManager, toPreviewing: Bool = true) {
        let result = im.confirmConversion(toPreviewing: toPreviewing)
        switch result {
        case .full(let confirmed):
            commitText(confirmed)
            logEvent("confirm", detail: confirmed)
        case .partial:
            // 部分確定テキストは markedText 内に .confirmed セグメントとして保持し、
            // 全文確定時にまとめて commit する（composition の終了→再開を避ける）
            updateMarkedTextDisplay()
            logEvent("partial-confirm", detail: im.displayText)
        }
    }

    private func cancelComposition(_ im: InputManager) {
        logEvent("cancel", detail: im.displayText)
        if let prefix = im.cancelConversion() {
            // 部分確定済みテキストがあれば commit する
            commitText(prefix)
        } else {
            clearMarkedText()
        }
    }

    /// deleteBackward の結果に応じて marked text を更新する共通ヘルパー
    private func handleDeleteBackward(_ im: InputManager) {
        let result = im.deleteBackward()
        switch result {
        case .continuing:
            updateMarkedTextDisplay()
        case .finished(let textToCommit):
            if let text = textToCommit {
                commitText(text)
            } else {
                clearMarkedText()
            }
        }
    }

    // MARK: - Marked Text Display

    private func updateMarkedTextDisplay() {
        guard let im = inputManager else { return }
        let segments = im.displaySegments
        guard !segments.isEmpty else {
            clearMarkedText()
            return
        }
        setMarkedTextWithSegments(segments)
        // フォーカスセグメントの先頭位置を計算（候補ポップアップの配置用）
        let focusedOffset = segments
            .prefix(while: { $0.focus != .focused })
            .reduce(0) { $0 + $1.text.utf16.count }
        reportCaretRect(focusedSegmentOffset: focusedOffset)
    }

    private func clearMarkedText() {
        removeMarkedTextAttributes()
        setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        unmarkText()
        onCaretRectChange?(.zero)
    }

    /// markedText 範囲の手動付与した属性を除去する
    ///
    /// `setMarkedTextWithSegments` で `textStorage` に直接付与した属性は、
    /// `insertText` や `setMarkedText("")` では自動クリアされない。
    /// composition 終了前に明示的に除去する必要がある。
    private func removeMarkedTextAttributes() {
        guard let range = markedTextRange else { return }
        let start = offset(from: beginningOfDocument, to: range.start)
        let end = offset(from: beginningOfDocument, to: range.end)
        let length = end - start
        guard length > 0 else { return }
        let nsRange = NSRange(location: start, length: length)
        textStorage.removeAttribute(.underlineStyle, range: nsRange)
        textStorage.removeAttribute(.underlineColor, range: nsRange)
        textStorage.removeAttribute(.backgroundColor, range: nsRange)
        textStorage.removeAttribute(.foregroundColor, range: nsRange)
    }

    /// フォーカスセグメントの先頭位置を通知する（候補ポップアップ配置用）
    ///
    /// - Parameter focusedSegmentOffset: markedText 先頭からフォーカスセグメントまでの UTF-16 オフセット。
    ///   0 の場合は markedText の先頭位置を返す。
    private func reportCaretRect(focusedSegmentOffset: Int = 0) {
        guard let range = markedTextRange else {
            onCaretRectChange?(.zero)
            return
        }
        let basePos = if focusedSegmentOffset > 0,
                          let pos = position(from: range.start, offset: focusedSegmentOffset) {
            pos
        } else {
            range.start
        }
        var rect = caretRect(for: basePos)
        // スクロールを考慮し、表示領域座標に変換
        rect.origin.x -= contentOffset.x
        rect.origin.y -= contentOffset.y
        onCaretRectChange?(rect)
    }

    /// セグメント別のスタイルで markedText を設定する
    ///
    /// - confirmed セグメント: 細下線・テキスト色（部分確定済み）
    /// - focused セグメント: **無彩色背景ハイライト**（選択中の候補）
    /// - unfocused セグメント: 細下線・テキスト色（未変換の残り / composing 中）
    private func setMarkedTextWithSegments(_ segments: [InputManager.DisplaySegment]) {
        // 前回の属性（foregroundColor 等）が残らないよう、新しいテキスト設定前にクリア
        removeMarkedTextAttributes()
        let fullText = segments.map(\.text).joined()
        setMarkedText(fullText, selectedRange: NSRange(location: fullText.count, length: 0))
        guard !fullText.isEmpty, let range = markedTextRange else { return }
        let baseOffset = offset(from: beginningOfDocument, to: range.start)
        var currentOffset = 0
        // beginEditing/endEditing で属性変更を一括通知し、レイアウトマネージャの再描画を確実にする
        textStorage.beginEditing()
        for segment in segments {
            let segmentLength = (segment.text as NSString).length
            guard segmentLength > 0 else { continue }
            let nsRange = NSRange(location: baseOffset + currentOffset, length: segmentLength)
            switch segment.focus {
            case .confirmed:
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                textStorage.addAttribute(.underlineColor, value: UIColor.label, range: nsRange)
            case .focused:
                // 無彩色の背景ハイライト（テキスト色はそのまま）
                textStorage.addAttribute(.backgroundColor, value: UIColor.systemFill, range: nsRange)
                // setMarkedText が付与するデフォルト下線を明示的に除去
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle(rawValue: 0).rawValue, range: nsRange)
            case .unfocused:
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                textStorage.addAttribute(.underlineColor, value: UIColor.label, range: nsRange)
            }
            currentOffset += segmentLength
        }
        textStorage.endEditing()
    }

    // MARK: - テキスト選択（アンカーベース）

    /// アンカーベースでテキスト選択のアクティブエンドを移動する
    ///
    /// 初回呼び出しでカーソル位置をアンカーとして記録し、以降の SHFT+T/Y は
    /// アクティブエンド（アンカーの反対側）を移動する。
    /// - Parameter offset: -1 で左、+1 で右
    private func moveSelectionEdge(offset: Int) {
        guard let range = selectedTextRange else { return }

        // 初回: アンカーを記録（現在のカーソル位置 or 選択の開始位置）
        if selectionAnchor == nil {
            selectionAnchor = range.start
        }
        guard let anchor = selectionAnchor else { return }

        // アクティブエンド = アンカーの反対側
        let activeEnd: UITextPosition
        if compare(range.start, to: anchor) == .orderedSame {
            activeEnd = range.end    // アンカーが左端 → 右端がアクティブ
        } else if compare(range.end, to: anchor) == .orderedSame {
            activeEnd = range.start  // アンカーが右端 → 左端がアクティブ
        } else {
            // アンカーがどちらの端でもない（外部で選択が変わった）→ リセット
            selectionAnchor = range.start
            activeEnd = range.end
        }

        // アクティブエンドを移動
        guard let newActive = position(from: activeEnd, offset: offset) else { return }

        // アンカーと新しいアクティブエンドで選択範囲を構築
        if compare(anchor, to: newActive) == .orderedDescending {
            // アンカーが後ろ → [newActive, anchor]
            selectedTextRange = textRange(from: newActive, to: anchor)
        } else {
            // アンカーが前 or 同位置 → [anchor, newActive]
            selectedTextRange = textRange(from: anchor, to: newActive)
        }
    }

    // MARK: - Logging

    private func logKeyEvent(phase: String, key: UIKey, handled: Bool) {
        let now = Date()
        onKeyEvent?(KeyEventInfo(
            phase: phase, keyCode: key.keyCode,
            characters: key.characters, modifiers: key.modifierFlags,
            handled: handled, timestamp: now
        ))
        // 可視化パネル向けコールバック
        if phase == "began" {
            onKeyDown?(key.keyCode, now)
        }
    }

    private func logEvent(_ phase: String, detail: String) {
        onKeyEvent?(KeyEventInfo(
            phase: phase, keyCode: .keyboardErrorUndefined,
            characters: detail, modifiers: [], handled: true,
            timestamp: Date()
        ))
    }
}

