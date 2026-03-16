import UIKit

// MARK: - UIKey → KeyEvent 変換

extension KeyEvent {
    /// UIKey からプラットフォーム非依存の KeyEvent を生成する
    @MainActor
    init(_ uiKey: UIKey) {
        self.init(
            keyCode: HIDKeyCode(uiKey.keyCode),
            characters: uiKey.characters,
            modifierFlags: KeyModifierFlags(uiKey.modifierFlags)
        )
    }
}

extension HIDKeyCode {
    /// UIKeyboardHIDUsage から変換する
    init(_ usage: UIKeyboardHIDUsage) {
        self.init(rawValue: UInt32(usage.rawValue))
    }

    /// UIKeyboardHIDUsage に変換する
    var hidUsage: UIKeyboardHIDUsage {
        UIKeyboardHIDUsage(rawValue: Int(rawValue)) ?? .keyboardErrorUndefined
    }
}

extension KeyModifierFlags {
    /// UIKeyModifierFlags から変換する
    init(_ flags: UIKeyModifierFlags) {
        var result = KeyModifierFlags()
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.alternate) { result.insert(.alternate) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }
}

/// キー入力を横取りする UITextView サブクラス。
///
/// 設計原則:
///   - InputManager が変換状態の唯一の管理元。IMETextView は表示とキー入力の橋渡しのみ。
///   - composing 中は super.pressesBegan を呼ばない（UIKit が marked text を勝手に commit するため）。
///   - pressesBegan がハードウェアキーボードの唯一のハンドラ。
///   - insertText / deleteBackward はソフトウェアキーボード用のフォールバック。
public class IMETextView: UITextView {

    /// 不可視文字描画用レイアウトマネージャ（`useInvisibleCharLayout: true` で初期化時に設定）
    private(set) var invisibleLayoutManager: InvisibleCharLayoutManager?

    /// 不可視文字レイアウトマネージャを組み込んだ convenience initializer
    ///
    /// `useInvisibleCharLayout: true` の場合、NSTextStorage + InvisibleCharLayoutManager +
    /// NSTextContainer を手動構成して UITextView を初期化する。
    public convenience init(useInvisibleCharLayout: Bool) {
        if useInvisibleCharLayout {
            let storage = NSTextStorage()
            let layoutManager = InvisibleCharLayoutManager()
            storage.addLayoutManager(layoutManager)
            let container = NSTextContainer()
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            layoutManager.addTextContainer(container)
            self.init(frame: .zero, textContainer: container)
            self.invisibleLayoutManager = layoutManager
        } else {
            self.init(frame: .zero)
        }
    }

    /// 変換管理（外部から注入）
    ///
    /// 設定時に現在の `keyRouter` の入力マッピングを自動で同期する。
    public var inputManager: InputManager? {
        didSet {
            guard inputManager !== oldValue else { return }
            inputManager?.updateInputMappings(keyRouter.definition.inputMappings)
        }
    }

    /// エディタの表示スタイル（markedText 属性のベースとして使用）
    public var editorStyle = EditorStyle()

    /// キーイベントログ用コールバック
    public var onKeyEvent: ((KeyEventInfo) -> Void)?

    /// キーダウン通知（可視化パネル用、HID コード + タイムスタンプ）
    public var onKeyDown: ((HIDKeyCode, Date) -> Void)?

    /// キーアップ通知（可視化パネル用、HID コード + タイムスタンプ）
    public var onKeyUp: ((HIDKeyCode, Date) -> Void)?

    /// 英数モード切替通知（レイヤー自動追従用）
    public var onEnglishModeChange: ((Bool) -> Void)?

    /// カーソル位置変更通知（候補ポップアップの配置用）
    public var onCaretRectChange: ((CGRect) -> Void)?

    /// 現在のキールーター（入力方式・キーボードレイアウトの切替で差し替え）
    public var keyRouter = KeyRouter(definition: DefaultKeymaps.romajiUS) {
        didSet {
            syncChordBufferTables()
            // キーマップ切替時に入力マッピングを同期（同一定義の再代入はスキップ）
            if keyRouter.definition.name != oldValue.definition.name {
                inputManager?.updateInputMappings(keyRouter.definition.inputMappings)
            }
        }
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
    private var interceptedKeyCodes: Set<HIDKeyCode> = []

    /// 同時打鍵バッファ（chord 方式の入力で使用）
    private let chordBuffer = SimultaneousKeyBuffer()

    /// スマート選択の状態（Shift+Option+→/← で段階的に拡大・縮小）
    private var smartSelectionState = SmartSelectionState()

    /// ブロック境界検出の外部注入プロパティ
    ///
    /// アプリ側がブロック（シーン区切り等）の定義を注入すると、
    /// スマート選択の最上位レベルとしてブロック選択が有効になる。
    /// nil の場合、`.block` レベルはスキップされる。
    public var blockRangeProvider: BlockRangeProvider? {
        get { smartSelectionState.blockRangeProvider }
        set { smartSelectionState.blockRangeProvider = newValue }
    }

    /// ブロック間のセパレータ文字列（例: "\n\n\n\n"）
    ///
    /// 設定されている場合、`swapBlock` で最後のブロックがスワップに関わるとき
    /// セパレータの付け替え（正規化）を行う。nil の場合は正規化なし（後方互換）。
    public var blockSeparator: String?

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

    /// 現在のキーマップが指定 HID キーコードを処理するか
    ///
    /// modeKeys に定義されているか、chord の hidToKey に含まれるかを判定する。
    /// fullControlMode でシステム IME トリガーキーをインターセプトする際、
    /// キーマップが処理するキーはインターセプトせず KeyRouter に委ねるために使用。
    private func keymapHandles(_ keyCode: UIKeyboardHIDUsage) -> Bool {
        let hid = HIDKeyCode(keyCode)
        if let modeKeys = keyRouter.definition.modeKeys,
           modeKeys.keys.contains(where: { $0.keyCode == hid }) { return true }
        guard case .chord(let config) = keyRouter.definition.behavior else { return false }
        return config.hidToKey[hid] != nil
    }

    /// InputManager の状態に基づく composing 判定
    private var isComposing: Bool {
        guard let im = inputManager else { return false }
        return !im.isEmpty
    }

    // MARK: - Key Event Info

    public struct KeyEventInfo {
        public let phase: String
        public let keyCode: HIDKeyCode
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
        case .switchToEnglish:
            selectionAnchor = nil
            if isComposing {
                let confirmed = im.confirmAll()
                commitText(confirmed)
                logEvent("switch-en-confirm", detail: confirmed)
            }
            chordBuffer.reset()
            switchToDirectEnglish()
            logEvent("switch-en", detail: "→ directEnglish")
        case .switchToJapanese:
            selectionAnchor = nil
            if im.inputMethod == .directEnglish {
                chordBuffer.reset()
                switchToJapaneseMode()
                logEvent("switch-ja", detail: "→ japanese")
            }
        case .toggleInputMode:
            selectionAnchor = nil
            if im.inputMethod == .directEnglish {
                chordBuffer.reset()
                switchToJapaneseMode()
                logEvent("toggle-ja", detail: "→ japanese")
            } else {
                if isComposing {
                    let confirmed = im.confirmAll()
                    commitText(confirmed)
                    logEvent("toggle-en-confirm", detail: confirmed)
                }
                chordBuffer.reset()
                switchToDirectEnglish()
                logEvent("toggle-en", detail: "→ directEnglish")
            }
        default:
            break
        }
    }

    /// 英数直接入力モードに切り替える
    ///
    /// chord 方式の場合は chord buffer のテーブルを英数用に差し替える。
    /// sequential 方式でも inputMethod を .directEnglish に設定し、
    /// KeyRouter が印字可能文字を .directInsert で返すようになる。
    /// `inputManager.inputMethod` が唯一の真実の情報源（KeyRouter は struct のため
    /// SwiftUI の updateUIView で上書きされる可能性がある）。
    private func switchToDirectEnglish() {
        if case .chord(let config) = keyRouter.definition.behavior {
            if let englishLookup = config.englishLookupTable {
                chordBuffer.lookupFunction = { englishLookup[$0] }
            }
            if let englishActions = config.englishSpecialActions {
                chordBuffer.specialActionFunction = { englishActions[$0] }
            }
        }
        inputManager?.inputMethod = .directEnglish
        onEnglishModeChange?(true)
    }

    /// 日本語入力モードに復帰する
    ///
    /// chord 方式の場合は lookup テーブルを日本語用に復元し、
    /// sequential 方式の場合は inputMethod を .sequential に戻す。
    private func switchToJapaneseMode() {
        switch keyRouter.definition.behavior {
        case .chord(let config):
            let lookup = config.lookupTable
            chordBuffer.lookupFunction = { lookup[$0] }
            let actions = config.specialActions
            chordBuffer.specialActionFunction = { actions[$0] }
            inputManager?.inputMethod = .chord(name: keyRouter.definition.name)
        case .sequential:
            inputManager?.inputMethod = .sequential
        }
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
        // fullControlMode ではシステム IME の状態変更を無視
        if inputManager?.fullControlMode == true { return }

        let isJapanese = isJapaneseInputMode
        inputManager?.setInputMode(isJapanese ? .japanese : .english)

        // アプリ側の IM バッジにも通知
        onEnglishModeChange?(!isJapanese)

        // 日本語 → 英語に切り替わった時、composing 中なら全文確定
        if !isJapanese && isComposing {
            guard let im = inputManager else { return }
            let confirmed = im.confirmAll()
            commitText(confirmed)
            logEvent("mode-confirm", detail: confirmed)
        }
    }

    // MARK: - fullControlMode: システム IME キーのハンドリング

    /// fullControlMode 有効時にシステム IME トリガーキーを処理する
    ///
    /// キーマップの modeKeys / hidToKey に定義されていないシステム IME キーを
    /// インターセプトし、super に渡さない（システム IME 切替を防止）。
    /// LANG1/LANG2 はアプリ独自のモード切替に、CAPS LOCK はトグルに使用する。
    private func handleFullControlIMEKey(_ key: UIKey, presses: Set<UIPress>, event: UIPressesEvent?) {
        interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))

        switch key.keyCode {
        case .keyboardLANG2:
            // 英数直接入力に切替
            if isComposing, let im = inputManager {
                let confirmed = im.confirmAll()
                commitText(confirmed)
                logEvent("fc-eisu-confirm", detail: confirmed)
            }
            resetChordBufferIfNeeded()
            switchToDirectEnglish()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .keyboardLANG1:
            // 日本語入力に復帰
            if inputManager?.inputMethod == .directEnglish {
                resetChordBufferIfNeeded()
                switchToJapaneseMode()
            }
            logKeyEvent(phase: "began", key: key, handled: true)

        case .keyboardCapsLock:
            // 日本語↔英数トグル
            if let im = inputManager {
                if im.inputMethod == .directEnglish {
                    resetChordBufferIfNeeded()
                    switchToJapaneseMode()
                    logEvent("fc-caps-ja", detail: "→ japanese")
                } else {
                    if isComposing {
                        let confirmed = im.confirmAll()
                        commitText(confirmed)
                        logEvent("fc-caps-confirm", detail: confirmed)
                    }
                    resetChordBufferIfNeeded()
                    switchToDirectEnglish()
                    logEvent("fc-caps-en", detail: "→ directEnglish")
                }
            }
            logKeyEvent(phase: "began", key: key, handled: true)

        default:
            // 変換、無変換、Ctrl+Space、ひらがな/カタカナ: キーを消費するだけ
            logKeyEvent(phase: "began", key: key, handled: true)
        }
    }

    // MARK: - insertText / deleteBackward: ソフトウェアキーボード用フォールバック

    public override func insertText(_ text: String) {
        guard let im = inputManager else {
            super.insertText(text)
            return
        }
        // 英語モードならそのまま挿入
        // fullControlMode ではアプリの inputMethod で判定、それ以外はシステム IME 状態で判定
        let isEnglish = im.fullControlMode
            ? im.inputMethod == .directEnglish
            : !isJapaneseInputMode
        if isEnglish {
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

        // fullControlMode: システム IME 切替キーをインターセプト
        // modeKeys に定義されたキーは keymapHandles() で true → ここをスキップし KeyRouter に流れる
        if inputManager?.fullControlMode == true {
            let hidCode = HIDKeyCode(key.keyCode)
            let isCtrlSpace = key.keyCode == .keyboardSpacebar
                && key.modifierFlags.contains(.control)
            if !keymapHandles(key.keyCode)
               && (HIDKeyCode.systemIMETriggerKeys.contains(hidCode) || isCtrlSpace) {
                handleFullControlIMEKey(key, presses: presses, event: event)
                return
            }
        }

        // Cmd+ 系は常に super（コピペ等）
        // ただし composing 中の Cmd+Z（Shift なし）は composing キャンセルに使う。
        // super を呼ぶと marked text が勝手に commit されるため。
        // 1回目の Cmd+Z で composing キャンセル、2回目で UITextView の undo が実行される。
        if key.modifierFlags.contains(.command) {
            if isComposing,
               key.keyCode == .keyboardZ,
               !key.modifierFlags.contains(.shift),
               let im = inputManager {
                interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
                cancelComposition(im)
                logKeyEvent(phase: "began", key: key, handled: true)
                return
            }
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
        // fullControlMode ではシステム IME 状態を無視し、inputManager.inputMethod で判定
        if !isJapaneseInputMode && inputManager?.fullControlMode != true {
            logKeyEvent(phase: "began", key: key, handled: false)
            super.pressesBegan(presses, with: event)
            return
        }

        guard let im = inputManager else {
            logKeyEvent(phase: "began", key: key, handled: false)
            super.pressesBegan(presses, with: event)
            return
        }

        // KeyRouter にルーティングを委譲（UIKey → KeyEvent 変換）
        let isDirectEnglish = im.inputMethod == .directEnglish
        let keyEvent = KeyEvent(key)
        let action = keyRouter.route(keyEvent, isComposing: isComposing, state: im.state,
                                     isDirectEnglishMode: isDirectEnglish)
        executeAction(action, key: key, inputManager: im, presses: presses, event: event)
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key else {
            super.pressesEnded(presses, with: event)
            return
        }
        // 可視化パネル向けキーアップ通知
        onKeyUp?(HIDKeyCode(key.keyCode), Date())
        // chord 方式: キーアップ通知
        if case .chord(let config) = keyRouter.definition.behavior {
            if let chordKey = config.hidToKey[HIDKeyCode(key.keyCode)] {
                chordBuffer.keyUp(chordKey)
            }
        }
        // pressesBegan でインターセプトしたキーは super に渡さない
        if interceptedKeyCodes.remove(HIDKeyCode(key.keyCode)) != nil {
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
            if let chordKey = config.hidToKey[HIDKeyCode(key.keyCode)] {
                chordBuffer.keyUp(chordKey)
            }
        }
        if interceptedKeyCodes.remove(HIDKeyCode(key.keyCode)) != nil {
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
        // スマート選択系以外のアクションでは状態をリセット
        switch action {
        case .smartSelectExpand, .smartSelectShrink, .selectSentenceUp, .selectSentenceDown,
             .swapSentenceUp, .swapSentenceDown:
            break
        default:
            if smartSelectionState.level != .none {
                smartSelectionState.reset()
            }
        }

        switch action {
        case .pass:
            if isComposing {
                // composing 中は super を呼ばない（UIKit が marked text を勝手に commit するため）
                // chord 方式の場合はバッファもリセット
                if case .chord = keyRouter.definition.behavior {
                    chordBuffer.reset()
                }
                interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
                logKeyEvent(phase: "began", key: key, handled: true)
            } else {
                logKeyEvent(phase: "began", key: key, handled: false)
                super.pressesBegan(presses, with: event)
            }

        case .printable(let c):
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
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
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            // Tab キー + 予測候補あり → 予測候補を確定
            if key.keyCode == .keyboardTab,
               im.state == .composing,
               !im.predictionCandidates.isEmpty {
                // Tab + 予測候補あり → 巡回選択（macOS 標準 IME 準拠）
                im.selectNextPrediction()
            } else if im.state == .composing,
                      let selectedIdx = im.selectedPredictionIndex,
                      let text = im.acceptPrediction(at: selectedIdx) {
                // Enter + 予測候補選択中 → 選択中の予測候補を確定
                commitText(text)
                logEvent("prediction-accept", detail: text)
            } else {
                confirmComposition(im)
            }
            logKeyEvent(phase: "began", key: key, handled: true)

        case .cancel:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
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
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            handleSpace(im)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .convertPrev:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            im.selectPrevCandidate()
            updateMarkedTextDisplay()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .deleteBack:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
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
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            // composing/previewing/selecting 全状態で消費のみ（azooKey-Desktop / macOS 標準準拠）
            logKeyEvent(phase: "began", key: key, handled: true)

        case .moveRight:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            if im.state == .selecting || im.state == .previewing {
                // → キーからの確定: 残りがあれば selecting 維持
                confirmComposition(im, toPreviewing: false)
            }
            // composing 中は消費のみ
            logKeyEvent(phase: "began", key: key, handled: true)

        case .moveUp:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            if im.state == .selecting {
                im.selectPrevCandidate()
                updateMarkedTextDisplay()
            }
            // composing/previewing 中は消費のみ
            logKeyEvent(phase: "began", key: key, handled: true)

        case .moveDown:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
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
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            im.editSegment(count: -1)
            updateMarkedTextDisplay()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .editSegmentRight:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            im.editSegment(count: 1)
            updateMarkedTextDisplay()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .selectCandidate(let offset):
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
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
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.hiragana)
            commitText(confirmed)
            logEvent("ctrl-j-hiragana", detail: confirmed)

        case .confirmKatakana:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.katakana)
            commitText(confirmed)
            logEvent("ctrl-k-katakana", detail: confirmed)

        case .confirmHalfWidthKatakana:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.halfWidthKatakana)
            commitText(confirmed)
            logEvent("ctrl-l-halfkana", detail: confirmed)

        case .confirmHalfWidthRoman:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.halfWidthRoman)
            commitText(confirmed)
            logEvent("ctrl-colon-halfwidth", detail: confirmed)

        case .confirmFullWidthRoman:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            resetChordBufferIfNeeded()
            let confirmed = im.confirmWithForm(.fullWidthRoman)
            commitText(confirmed)
            logEvent("ctrl-semicolon-fullwidth", detail: confirmed)

        case .chordInput(let chordKey):
            selectionAnchor = nil
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))

            // selecting/previewing 中に文字キーを押した場合 → 確定して新規 composing
            if im.state == .selecting || im.state == .previewing {
                chordBuffer.reset()
                let confirmed = im.confirmAll()
                commitText(confirmed)
                logEvent("chord-select-and-continue", detail: confirmed)
            }

            // 英数候補用: 日本語モードのみ QWERTY キー文字を蓄積
            if im.inputMethod != .directEnglish {
                im.recordChordKey(chordKey)
            }

            // 英数モード + 物理 Shift → lookup 時に shift ビットを合成して大文字を出力
            chordBuffer.physicalShift = im.inputMethod == .directEnglish
                && key.modifierFlags.contains(.shift)
            chordBuffer.keyDown(chordKey)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .chordShiftDown(let shiftKey):
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            chordBuffer.keyDown(shiftKey)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .directInsert(let text):
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            rawInsertText(text)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .switchToEnglish:
            // modeKeys 経由（KeyRouter → executeAction）で発火
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            if isComposing {
                let confirmed = im.confirmAll()
                commitText(confirmed)
                logEvent("switch-en-confirm", detail: confirmed)
            }
            resetChordBufferIfNeeded()
            switchToDirectEnglish()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .switchToJapanese:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            if im.inputMethod == .directEnglish {
                resetChordBufferIfNeeded()
                switchToJapaneseMode()
                logEvent("switch-ja", detail: "→ japanese")
            }
            logKeyEvent(phase: "began", key: key, handled: true)

        case .toggleInputMode:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            if im.inputMethod == .directEnglish {
                resetChordBufferIfNeeded()
                switchToJapaneseMode()
                logEvent("toggle-ja", detail: "→ japanese")
            } else {
                if isComposing {
                    let confirmed = im.confirmAll()
                    commitText(confirmed)
                    logEvent("toggle-en-confirm", detail: confirmed)
                }
                resetChordBufferIfNeeded()
                switchToDirectEnglish()
                logEvent("toggle-en", detail: "→ directEnglish")
            }
            logKeyEvent(phase: "began", key: key, handled: true)

        // MARK: 文ナビゲーション（Option+矢印）

        case .moveSentenceStart:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            moveCursorToSentenceStart()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .moveSentenceEnd:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            moveCursorToSentenceEnd()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .swapSentenceUp:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            swapSentence(direction: -1)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .swapSentenceDown:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            swapSentence(direction: 1)
            logKeyEvent(phase: "began", key: key, handled: true)

        // MARK: スマート選択（Shift+Option+矢印）

        case .smartSelectExpand:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            handleSmartSelectExpand()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .smartSelectShrink:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            handleSmartSelectShrink()
            logKeyEvent(phase: "began", key: key, handled: true)

        case .selectSentenceUp:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            handleSelectSentence(direction: -1)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .selectSentenceDown:
            interceptedKeyCodes.insert(HIDKeyCode(key.keyCode))
            selectionAnchor = nil
            handleSelectSentence(direction: 1)
            logKeyEvent(phase: "began", key: key, handled: true)

        case .insertAndConfirm:
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
        let fullRange = NSRange(location: baseOffset, length: (fullText as NSString).length)
        // beginEditing/endEditing で属性変更を一括通知し、レイアウトマネージャの再描画を確実にする
        textStorage.beginEditing()
        // editorStyle のベース属性を markedText 全体に適用
        textStorage.addAttributes(editorStyle.typingAttributes, range: fullRange)
        var currentOffset = 0
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

    // MARK: - 文ナビゲーション・スマート選択

    /// テキスト全文を取得する
    private func fullText() -> String {
        textStorage.string
    }

    /// カーソル位置を String.Index に変換する
    ///
    /// UITextView の offset は UTF-16 ベースなので、NSString 経由で変換する。
    private func cursorStringIndex(in text: String, from textPosition: UITextPosition) -> String.Index {
        let utf16Offset = offset(from: beginningOfDocument, to: textPosition)
        let nsString = text as NSString
        // UTF-16 オフセットの範囲チェック
        guard utf16Offset >= 0, utf16Offset <= nsString.length else {
            return text.endIndex
        }
        // NSRange → Range<String.Index> 変換
        let nsRange = NSRange(location: utf16Offset, length: 0)
        guard let range = Range(nsRange, in: text) else {
            return text.endIndex
        }
        return range.lowerBound
    }

    /// String.Index の範囲を UITextView の selectedTextRange に設定する
    private func setSelection(range: Range<String.Index>, in text: String) {
        let nsString = text as NSString
        let nsRange = NSRange(range, in: text)
        guard nsRange.location != NSNotFound,
              nsRange.location + nsRange.length <= nsString.length else { return }
        guard let start = position(from: beginningOfDocument, offset: nsRange.location),
              let end = position(from: beginningOfDocument, offset: nsRange.location + nsRange.length) else { return }
        selectedTextRange = textRange(from: start, to: end)
        scrollRangeToVisible(nsRange)
    }

    /// String.Index を UITextPosition に変換してカーソルを設定する
    private func setCursor(at index: String.Index, in text: String) {
        let nsRange = NSRange(index..<index, in: text)
        guard let pos = position(from: beginningOfDocument, offset: nsRange.location) else { return }
        selectedTextRange = textRange(from: pos, to: pos)
    }

    /// 文頭へカーソルを移動する（Option+←）
    private func moveCursorToSentenceStart() {
        let text = fullText()
        guard !text.isEmpty, let range = selectedTextRange else { return }

        let cursor = cursorStringIndex(in: text, from: range.start)
        let target = SentenceBoundary.previousSentenceStart(in: text, before: cursor)
        setCursor(at: target, in: text)
    }

    /// 文末へカーソルを移動する（Option+→）
    private func moveCursorToSentenceEnd() {
        let text = fullText()
        guard !text.isEmpty, let range = selectedTextRange else { return }

        let cursor = cursorStringIndex(in: text, from: range.end)
        let target = SentenceBoundary.nextSentenceEnd(in: text, after: cursor)
        setCursor(at: target, in: text)
    }

    /// 文を前後の文と入れ替える（Option+↑/↓）
    ///
    /// 選択範囲全体を1つの単位として隣接する文とスワップする。
    /// 未選択時はカーソル位置の1文を自動選択してスワップ。
    /// - Parameter direction: -1 で前の文と、+1 で後の文と入れ替え
    private func swapSentence(direction: Int) {
        let text = fullText()
        guard !text.isEmpty, let range = selectedTextRange else { return }

        let selStart = cursorStringIndex(in: text, from: range.start)
        let selEnd = cursorStringIndex(in: text, from: range.end)

        // スマート選択がブロックレベルならブロック単位でスワップ
        if smartSelectionState.level == .block,
           let provider = blockRangeProvider {
            swapBlock(direction: direction, text: text, cursor: selStart, provider: provider)
            return
        }

        // 選択範囲を決定
        let currentRange: Range<String.Index>
        if selStart == selEnd {
            // 未選択: カーソル位置の1文を自動選択（従来動作）
            currentRange = SentenceBoundary.sentenceRange(in: text, at: selStart)
        } else {
            // 選択中: 選択範囲をそのまま使う
            currentRange = selStart..<selEnd
        }

        // 隣接する文を探す
        let adjacentSentence: Range<String.Index>
        if direction < 0 {
            guard currentRange.lowerBound > text.startIndex else { return }
            let prevIdx = text.index(before: currentRange.lowerBound)
            adjacentSentence = SentenceBoundary.sentenceRange(in: text, at: prevIdx)
        } else {
            guard currentRange.upperBound < text.endIndex else { return }
            adjacentSentence = SentenceBoundary.sentenceRange(in: text, at: currentRange.upperBound)
        }

        guard currentRange != adjacentSentence else { return }

        // テキストを取得してスワップ
        let currentText = String(text[currentRange])
        let adjacentText = String(text[adjacentSentence])

        let (first, second): (Range<String.Index>, Range<String.Index>)
        let (firstText, secondText): (String, String)

        if currentRange.lowerBound < adjacentSentence.lowerBound {
            first = currentRange
            second = adjacentSentence
            firstText = adjacentText
            secondText = currentText
        } else {
            first = adjacentSentence
            second = currentRange
            firstText = currentText
            secondText = adjacentText
        }

        // Undo 対応: replace を使用
        let fullRange = first.lowerBound..<second.upperBound
        let nsFullRange = NSRange(fullRange, in: text)
        guard let textRangeForReplace = convertNSRangeToTextRange(nsFullRange) else { return }

        let newText = firstText + secondText
        replace(textRangeForReplace, withText: newText)

        // 入れ替え後、元の選択範囲を移動先に設定
        let updatedText = fullText()
        if direction < 0 {
            let newStart = updatedText.index(updatedText.startIndex,
                                              offsetBy: text.distance(from: text.startIndex, to: first.lowerBound))
            let newEnd = updatedText.index(newStart, offsetBy: currentText.count)
            setSelection(range: newStart..<newEnd, in: updatedText)
        } else {
            let adjacentLength = adjacentText.count
            let startOffset = text.distance(from: text.startIndex, to: first.lowerBound) + adjacentLength
            let newStart = updatedText.index(updatedText.startIndex, offsetBy: startOffset)
            let newEnd = updatedText.index(newStart, offsetBy: currentText.count)
            setSelection(range: newStart..<newEnd, in: updatedText)
        }
    }

    /// ブロック単位で前後のブロックと入れ替える（Option+↑/↓、ブロック選択時）
    ///
    /// `BlockRangeProvider` を使ってブロック範囲を取得し、隣接ブロックと交換する。
    /// プロバイダが返す範囲には末尾のセパレータ（空行等）を含む前提。
    /// `blockSeparator` が設定されている場合、最後のブロックがスワップに関わるとき
    /// セパレータの付け替え（正規化）を行う。
    private func swapBlock(direction: Int, text: String, cursor: String.Index,
                           provider: BlockRangeProvider) {
        guard let currentBlock = provider(text, cursor) else { return }

        // 隣接ブロックを探す
        let adjacentBlock: Range<String.Index>?
        if direction < 0 {
            guard currentBlock.lowerBound > text.startIndex else { return }
            let prevIdx = text.index(before: currentBlock.lowerBound)
            adjacentBlock = provider(text, prevIdx)
        } else {
            guard currentBlock.upperBound < text.endIndex else { return }
            adjacentBlock = provider(text, currentBlock.upperBound)
        }

        guard let adjacent = adjacentBlock, currentBlock != adjacent else { return }

        // テキストを取得
        var currentText = String(text[currentBlock])
        var adjacentText = String(text[adjacent])

        // セパレータ正規化: 最後のブロックがスワップに関わる場合
        if let sep = blockSeparator {
            let isCurrentLast = currentBlock.upperBound == text.endIndex
            let isAdjacentLast = adjacent.upperBound == text.endIndex

            if isCurrentLast {
                // 現在のブロック（最後）が移動する → セパレータを付与
                currentText += sep
                // 隣接ブロック（中間）が最後に来る → セパレータを除去
                if adjacentText.hasSuffix(sep) {
                    adjacentText = String(adjacentText.dropLast(sep.count))
                }
            } else if isAdjacentLast {
                // 隣接ブロック（最後）が移動する → セパレータを付与
                adjacentText += sep
                // 現在のブロック（中間）が最後に来る → セパレータを除去
                if currentText.hasSuffix(sep) {
                    currentText = String(currentText.dropLast(sep.count))
                }
            }
        }

        // 後方の範囲から先に置換（前方のオフセットを壊さないため）
        let (first, second): (Range<String.Index>, Range<String.Index>)
        let (firstText, secondText): (String, String)

        if currentBlock.lowerBound < adjacent.lowerBound {
            first = currentBlock
            second = adjacent
            firstText = adjacentText
            secondText = currentText
        } else {
            first = adjacent
            second = currentBlock
            firstText = currentText
            secondText = adjacentText
        }

        // Undo 対応: replace を使用
        let fullRange = first.lowerBound..<second.upperBound
        let nsFullRange = NSRange(fullRange, in: text)
        guard let textRangeForReplace = convertNSRangeToTextRange(nsFullRange) else { return }

        let newText = firstText + secondText
        replace(textRangeForReplace, withText: newText)

        // 入れ替え後、移動先のブロックを選択状態にする
        let updatedText = fullText()
        if direction < 0 {
            let newCursor = updatedText.index(updatedText.startIndex,
                                               offsetBy: text.distance(from: text.startIndex, to: first.lowerBound))
            if let newBlock = provider(updatedText, newCursor) {
                setSelection(range: newBlock, in: updatedText)
            }
        } else {
            let adjacentLength = adjacentText.count
            let startOffset = text.distance(from: text.startIndex, to: first.lowerBound) + adjacentLength
            guard startOffset < updatedText.count else { return }
            let newCursor = updatedText.index(updatedText.startIndex, offsetBy: startOffset)
            if let newBlock = provider(updatedText, newCursor) {
                setSelection(range: newBlock, in: updatedText)
            }
        }
    }

    /// NSRange を UITextRange に変換する
    private func convertNSRangeToTextRange(_ nsRange: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: nsRange.location),
              let end = position(from: beginningOfDocument, offset: nsRange.location + nsRange.length) else {
            return nil
        }
        return textRange(from: start, to: end)
    }

    /// スマート選択を拡大する（Shift+Option+→）
    private func handleSmartSelectExpand() {
        let text = fullText()
        guard !text.isEmpty, let range = selectedTextRange else { return }

        let cursor = cursorStringIndex(in: text, from: range.start)
        if let newRange = smartSelectionState.expand(in: text, cursor: cursor) {
            setSelection(range: newRange, in: text)
        }
    }

    /// スマート選択を縮小する（Shift+Option+←）
    private func handleSmartSelectShrink() {
        let text = fullText()
        guard !text.isEmpty else { return }

        if let newRange = smartSelectionState.shrink(in: text) {
            setSelection(range: newRange, in: text)
        } else if let origin = smartSelectionState.origin {
            // none に戻った — カーソルを起点に戻す
            setCursor(at: origin, in: text)
            smartSelectionState.reset()
        }
    }

    /// 文選択を拡張・縮小する（Shift+Option+↑/↓）
    ///
    /// 未選択なら現在の文を選択。
    /// 下方向（+1）: 次の文を追加して選択を拡張。
    /// 上方向（-1）: 選択範囲の末尾側から1文分削って縮小。1文のみの選択時は何もしない。
    /// - Parameter direction: -1 で上（縮小）、+1 で下（拡大）
    private func handleSelectSentence(direction: Int) {
        let text = fullText()
        guard !text.isEmpty, let range = selectedTextRange else { return }

        let selStart = cursorStringIndex(in: text, from: range.start)
        let selEnd = cursorStringIndex(in: text, from: range.end)
        let hasSelection = selStart != selEnd

        if !hasSelection {
            // 未選択: カーソル位置の文を選択（direction によらず同じ）
            let sentence = SentenceBoundary.sentenceRange(in: text, at: selStart)
            setSelection(range: sentence, in: text)
        } else if direction > 0 {
            // 下方向: 選択の末尾を次の文の末尾まで拡張（従来動作）
            guard selEnd < text.endIndex else { return }
            let nextSentence = SentenceBoundary.sentenceRange(in: text, at: selEnd)
            setSelection(range: selStart..<nextSentence.upperBound, in: text)
        } else {
            // 上方向: 選択範囲を末尾側から1文分縮小
            guard selEnd > text.startIndex else { return }
            let prevIdx = text.index(before: selEnd)
            let lastSentence = SentenceBoundary.sentenceRange(in: text, at: prevIdx)

            // 最後の文の先頭が選択先頭以前なら、1文のみ → 何もしない
            if lastSentence.lowerBound <= selStart {
                return
            }

            // 最後の文を選択から除外
            setSelection(range: selStart..<lastSentence.lowerBound, in: text)
        }
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
            phase: phase, keyCode: HIDKeyCode(key.keyCode),
            characters: key.characters, modifiers: key.modifierFlags,
            handled: handled, timestamp: now
        ))
        // 可視化パネル向けコールバック
        if phase == "began" {
            onKeyDown?(HIDKeyCode(key.keyCode), now)
        }
    }

    private func logEvent(_ phase: String, detail: String) {
        onKeyEvent?(KeyEventInfo(
            phase: phase, keyCode: .keyboardErrorUndefined,
            characters: detail, modifiers: [], handled: true,
            timestamp: Date()
        ))
    }

    // MARK: - Scrolloff（スクロールマージン）

    override public func scrollRangeToVisible(_ range: NSRange) {
        super.scrollRangeToVisible(range)
        enforceScrolloff()
    }

    /// カーソルが上端・下端から scrollOffLines 行以内に入らないようスクロール位置を調整する
    func enforceScrolloff() {
        let lineHeight = editorStyle.font.lineHeight + editorStyle.lineSpacing
        let margin = lineHeight * CGFloat(editorStyle.scrollOffLines)

        // カーソル位置を取得
        let cursorRange = selectedRange
        guard cursorRange.location != NSNotFound else { return }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: cursorRange.location, length: 0),
            actualCharacterRange: nil
        )
        let cursorRect = layoutManager.boundingRect(
            forGlyphRange: glyphRange, in: textContainer
        )
        let cursorY = cursorRect.origin.y + textContainerInset.top

        // カーソルの画面上の Y 座標
        let visibleY = cursorY - contentOffset.y

        // 上端マージン違反: カーソルが上から margin 以内
        if visibleY < margin {
            let targetOffsetY = cursorY - margin
            let clampedY = max(0, targetOffsetY)
            setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
        }

        // 下端マージン違反: カーソルが下から margin 以内
        let bottomThreshold = bounds.height - margin
        if visibleY > bottomThreshold {
            let targetOffsetY = cursorY - bottomThreshold
            let maxY = contentSize.height - bounds.height
            let clampedY = min(targetOffsetY, max(0, maxY))
            setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
        }
    }
}

