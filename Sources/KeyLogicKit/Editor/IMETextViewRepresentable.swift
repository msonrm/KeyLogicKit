import SwiftUI

/// IMETextView の SwiftUI ラッパー。
/// InputManager を注入し、常時 IME モードで動作する。
public struct IMETextViewRepresentable: UIViewRepresentable {

    /// 変換管理（SwiftUI 側で所有）
    public var inputManager: InputManager

    /// キールーター（入力方式・キーボードレイアウトの切替で差し替え）
    public var keyRouter: KeyRouter

    /// キーイベントログの追加コールバック
    public var onKeyEvent: ((IMETextView.KeyEventInfo) -> Void)?

    /// キーダウン通知（可視化パネル用、HID コード + タイムスタンプ）
    public var onKeyDown: ((UIKeyboardHIDUsage, Date) -> Void)?

    /// キーアップ通知（可視化パネル用、HID コード + タイムスタンプ）
    public var onKeyUp: ((UIKeyboardHIDUsage, Date) -> Void)?

    /// 英数モード切替通知（レイヤー自動追従用）
    public var onEnglishModeChange: ((Bool) -> Void)?

    /// カーソル位置変更通知（候補ポップアップの配置用）
    public var onCaretRectChange: ((CGRect) -> Void)?

    /// 明示的な公開イニシャライザ（public struct のメンバワイズ init は internal のため）
    public init(
        inputManager: InputManager,
        keyRouter: KeyRouter,
        onKeyEvent: ((IMETextView.KeyEventInfo) -> Void)? = nil,
        onKeyDown: ((UIKeyboardHIDUsage, Date) -> Void)? = nil,
        onKeyUp: ((UIKeyboardHIDUsage, Date) -> Void)? = nil,
        onEnglishModeChange: ((Bool) -> Void)? = nil,
        onCaretRectChange: ((CGRect) -> Void)? = nil
    ) {
        self.inputManager = inputManager
        self.keyRouter = keyRouter
        self.onKeyEvent = onKeyEvent
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onEnglishModeChange = onEnglishModeChange
        self.onCaretRectChange = onCaretRectChange
    }

    public func makeUIView(context: Context) -> IMETextView {
        let textView = IMETextView()

        // システム IME の干渉を無効化
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        // 外観設定
        textView.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        textView.backgroundColor = .systemBackground
        textView.isEditable = true
        textView.isScrollEnabled = true

        // InputManager、KeyRouter、コールバックを設定
        textView.inputManager = inputManager
        textView.keyRouter = keyRouter
        textView.onKeyEvent = onKeyEvent
        textView.onKeyDown = onKeyDown
        textView.onKeyUp = onKeyUp
        textView.onEnglishModeChange = onEnglishModeChange
        textView.onCaretRectChange = onCaretRectChange

        // エディタのフォントサイズを InputManager に反映
        if let fontSize = textView.font?.pointSize {
            inputManager.setEditorFontSize(fontSize)
        }

        // 入力モード監視を開始
        textView.setupInputModeObserver()

        // キー入力受付開始
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }

        return textView
    }

    public func updateUIView(_ uiView: IMETextView, context: Context) {
        uiView.inputManager = inputManager
        uiView.keyRouter = keyRouter
        uiView.onKeyEvent = onKeyEvent
        uiView.onKeyDown = onKeyDown
        uiView.onKeyUp = onKeyUp
        uiView.onEnglishModeChange = onEnglishModeChange
        uiView.onCaretRectChange = onCaretRectChange
        uiView.setSimultaneousWindow(inputManager.simultaneousWindow)
    }
}
