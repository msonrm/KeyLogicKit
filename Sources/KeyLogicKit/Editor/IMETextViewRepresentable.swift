import SwiftUI

/// IMETextView の SwiftUI ラッパー。
/// InputManager を注入し、常時 IME モードで動作する。
public struct IMETextViewRepresentable: UIViewRepresentable {

    /// 変換管理（SwiftUI 側で所有）
    public var inputManager: InputManager

    /// キールーター（入力方式・キーボードレイアウトの切替で差し替え）
    public var keyRouter: KeyRouter

    /// エディタの表示スタイル（フォント・行間・文末揃え）
    public var editorStyle: EditorStyle

    /// テキスト内容のバインディング（アプリ側との同期用）
    @Binding public var text: String

    /// カーソル位置のバインディング（アプリ側との同期用）
    @Binding public var cursorLocation: Int

    /// 選択範囲の長さのバインディング（アプリ側との同期用）
    @Binding public var selectionLength: Int

    /// スクロール強制リクエスト（値が変わるたびにカーソル位置が同じでもスクロール実行）
    public var scrollRevision: Int

    /// キーイベントログの追加コールバック
    public var onKeyEvent: ((IMETextView.KeyEventInfo) -> Void)?

    /// キーダウン通知（可視化パネル用、HID コード + タイムスタンプ）
    public var onKeyDown: ((HIDKeyCode, Date) -> Void)?

    /// キーアップ通知（可視化パネル用、HID コード + タイムスタンプ）
    public var onKeyUp: ((HIDKeyCode, Date) -> Void)?

    /// 英数モード切替通知（レイヤー自動追従用）
    public var onEnglishModeChange: ((Bool) -> Void)?

    /// カーソル位置変更通知（候補ポップアップの配置用）
    public var onCaretRectChange: ((CGRect) -> Void)?

    /// プログラム的なカーソル移動後のスクロール要求コールバック
    /// カーソル位置の UTF-16 オフセットを渡す。スクロール方法はアプリ側が決定する。
    public var onScrollRequest: ((IMETextView, Int) -> Void)?

    /// 明示的な公開イニシャライザ（public struct のメンバワイズ init は internal のため）
    public init(
        inputManager: InputManager,
        keyRouter: KeyRouter,
        editorStyle: EditorStyle = .init(),
        text: Binding<String> = .constant(""),
        cursorLocation: Binding<Int> = .constant(0),
        selectionLength: Binding<Int> = .constant(0),
        scrollRevision: Int = 0,
        onKeyEvent: ((IMETextView.KeyEventInfo) -> Void)? = nil,
        onKeyDown: ((HIDKeyCode, Date) -> Void)? = nil,
        onKeyUp: ((HIDKeyCode, Date) -> Void)? = nil,
        onEnglishModeChange: ((Bool) -> Void)? = nil,
        onCaretRectChange: ((CGRect) -> Void)? = nil,
        onScrollRequest: ((IMETextView, Int) -> Void)? = nil
    ) {
        self.inputManager = inputManager
        self.keyRouter = keyRouter
        self.editorStyle = editorStyle
        self._text = text
        self._cursorLocation = cursorLocation
        self._selectionLength = selectionLength
        self.scrollRevision = scrollRevision
        self.onKeyEvent = onKeyEvent
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onEnglishModeChange = onEnglishModeChange
        self.onCaretRectChange = onCaretRectChange
        self.onScrollRequest = onScrollRequest
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            cursorLocation: $cursorLocation,
            selectionLength: $selectionLength
        )
    }

    public func makeUIView(context: Context) -> IMETextView {
        let textView = IMETextView(useInvisibleCharLayout: editorStyle.showInvisibles)

        // システム IME の干渉を無効化
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        // 外観設定
        textView.typingAttributes = editorStyle.typingAttributes
        textView.textStorage.setAttributes(
            editorStyle.typingAttributes,
            range: NSRange(location: 0, length: textView.textStorage.length)
        )
        textView.backgroundColor = .systemBackground
        textView.isEditable = true
        textView.isScrollEnabled = true

        // EditorStyle を IMETextView に保持（markedText 属性のベースとして使う）
        textView.editorStyle = editorStyle

        // UITextViewDelegate を接続
        textView.delegate = context.coordinator

        // InputManager、KeyRouter、コールバックを設定
        textView.inputManager = inputManager
        textView.keyRouter = keyRouter
        textView.onKeyEvent = onKeyEvent
        textView.onKeyDown = onKeyDown
        textView.onKeyUp = onKeyUp
        textView.onEnglishModeChange = onEnglishModeChange
        textView.onCaretRectChange = onCaretRectChange

        // エディタのフォントサイズを InputManager に反映
        inputManager.setEditorFontSize(editorStyle.font.pointSize)

        // 入力モード監視を開始
        textView.setupInputModeObserver()

        // キー入力受付開始
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }

        return textView
    }

    public func updateUIView(_ uiView: IMETextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isProgrammaticChange = true
        defer { coordinator.isProgrammaticChange = false }

        uiView.inputManager = inputManager
        uiView.keyRouter = keyRouter
        uiView.onKeyEvent = onKeyEvent
        uiView.onKeyDown = onKeyDown
        uiView.onKeyUp = onKeyUp
        uiView.onEnglishModeChange = onEnglishModeChange
        uiView.onCaretRectChange = onCaretRectChange
        uiView.setSimultaneousWindow(inputManager.simultaneousWindow)

        // EditorStyle の変更を検知して再設定
        if uiView.editorStyle != editorStyle {
            uiView.editorStyle = editorStyle
            uiView.typingAttributes = editorStyle.typingAttributes
            uiView.textStorage.setAttributes(
                editorStyle.typingAttributes,
                range: NSRange(location: 0, length: uiView.textStorage.length)
            )
            inputManager.setEditorFontSize(editorStyle.font.pointSize)

            // 不可視文字表示の ON/OFF を反映
            if let lm = uiView.invisibleLayoutManager, lm.showInvisibles != editorStyle.showInvisibles {
                lm.showInvisibles = editorStyle.showInvisibles
                lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: uiView.textStorage.length))
            }
        }

        // composing 中は InputManager がテキスト管理しているため外部同期をスキップ
        guard inputManager.isEmpty else { return }

        // テキスト同期（SwiftUI → UIKit）
        // UIKit 起源の変更（undo/redo 含む）がフィードバックで戻ってきた場合は
        // 代入をスキップし、undoManager の履歴を保護する。
        if uiView.text != text {
            if coordinator.lastTextFromUIKit == text {
                // UIKit → Binding → updateUIView のフィードバック: スキップ
            } else {
                uiView.text = text
            }
            coordinator.lastTextFromUIKit = nil
        }

        // カーソル / 選択の差分検出 → 差分あれば適用
        let textLength = (uiView.text as NSString).length
        let safeLoc = min(cursorLocation, textLength)
        let safeLen = min(selectionLength, textLength - safeLoc)

        if safeLoc != coordinator.appliedCursorLocation
            || safeLen != coordinator.appliedSelectionLength
            || scrollRevision != coordinator.appliedScrollRevision
        {
            if !uiView.isFirstResponder, uiView.window != nil {
                uiView.becomeFirstResponder()
            }
            uiView.selectedRange = NSRange(location: safeLoc, length: safeLen)

            // スクロール要求をアプリ側に委譲
            if let onScrollRequest = onScrollRequest {
                DispatchQueue.main.async {
                    onScrollRequest(uiView, safeLoc)
                }
            }

            coordinator.appliedCursorLocation = safeLoc
            coordinator.appliedSelectionLength = safeLen
            coordinator.appliedScrollRevision = scrollRevision
        }
    }

    // MARK: - Coordinator

    /// UITextViewDelegate を実装し、テキスト内容・カーソル位置を SwiftUI 側にバインディングで同期する
    public final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        private var cursorLocation: Binding<Int>
        private var selectionLength: Binding<Int>

        /// updateUIView 実行中のデリゲートフィードバック抑制フラグ
        var isProgrammaticChange = false

        /// 前回 updateUIView で UIKit に適用したカーソル位置（差分検出用）
        var appliedCursorLocation = 0
        /// 前回 updateUIView で UIKit に適用した選択長（差分検出用）
        var appliedSelectionLength = 0
        /// 前回 updateUIView で処理したスクロールリビジョン（差分検出用）
        var appliedScrollRevision = 0

        /// UIKit 側から最後に通知されたテキスト（undo 履歴保護用）
        ///
        /// `textViewDidChange` → Binding 更新 → `updateUIView` のフィードバックループで
        /// `uiView.text` を再代入すると `undoManager` が全クリアされる。
        /// UIKit 起源の変更なら代入をスキップするためにこの値を保持する。
        var lastTextFromUIKit: String?

        init(text: Binding<String>, cursorLocation: Binding<Int>,
             selectionLength: Binding<Int>) {
            self.text = text
            self.cursorLocation = cursorLocation
            self.selectionLength = selectionLength
        }

        // MARK: - UITextViewDelegate

        public func textViewDidChange(_ textView: UITextView) {
            lastTextFromUIKit = textView.text
            text.wrappedValue = textView.text
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isProgrammaticChange else { return }
            guard textView.markedTextRange == nil else { return }
            let loc = textView.selectedRange.location
            let len = textView.selectedRange.length

            // applied* も同時更新 → 次の updateUIView で差分なし → 不要な再適用を防止
            appliedCursorLocation = loc
            appliedSelectionLength = len

            if cursorLocation.wrappedValue != loc {
                cursorLocation.wrappedValue = loc
            }
            if selectionLength.wrappedValue != len {
                selectionLength.wrappedValue = len
            }
        }
    }
}
