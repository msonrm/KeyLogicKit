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

    /// スクロール時のカーソル配置方法（デフォルト: `.minimal`）
    public var scrollAlignment: ScrollAlignment

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

    /// テキストコンテナに1行で収まる全角文字数が変化した際に呼ばれるコールバック
    public var onFittingCharsPerLineChange: ((_ count: Int) -> Void)?

    /// プログラム的なカーソル移動後のスクロール要求コールバック
    /// カーソル位置の UTF-16 オフセットを渡す。スクロール方法はアプリ側が決定する。
    @available(*, deprecated, message: "scrolloff が IMETextView 内で自動適用されるため不要")
    public var onScrollRequest: ((IMETextView, Int) -> Void)?

    /// ブロック境界検出の外部注入（スマート選択の最上位レベル）
    public var blockRangeProvider: BlockRangeProvider?

    /// ブロック間のセパレータ文字列（例: "\n\n\n\n"）
    ///
    /// 設定されている場合、swapBlock で最後のブロックがスワップに関わるとき
    /// セパレータの付け替え（正規化）を行う。nil の場合は正規化なし。
    public var blockSeparator: String?

    /// opt+左右 による文ナビゲーション時に呼ばれるコールバック
    /// - sentenceRange: 移動先の文の NSRange（UTF-16）
    /// - rects: 文の視覚的な矩形配列（複数行にまたがる場合は行ごとに1つ）
    public var onSentenceNavigation: ((_ sentenceRange: NSRange, _ rects: [CGRect]) -> Void)?

    /// ユーザーのタッチ操作によるスクロール時に呼ばれるコールバック（フォーカスモード解除用）
    public var onUserScroll: (() -> Void)?

    /// テキスト範囲の rect を問い合わせるプロバイダ（nil で無効）
    public var textRangeRectsProvider: TextRangeRectsProvider?

    /// UIFindInteraction による検索置換 UI を有効にする（iOS 16+）
    public var isFindInteractionEnabled: Bool = false

    /// 不可視文字の描画色（半角スペース）。nil の場合はデフォルト色
    public var invisibleSpaceColor: UIColor?
    /// 不可視文字の描画色（全角スペース）。nil の場合はデフォルト色
    public var invisibleFullWidthSpaceColor: UIColor?
    /// 不可視文字の描画色（タブ）。nil の場合はデフォルト色
    public var invisibleTabColor: UIColor?
    /// 不可視文字の描画色（改行）。nil の場合はデフォルト色
    public var invisibleNewlineColor: UIColor?

    /// ソフトウェアキーボードを非表示にする（ゲームパッド専用アプリ向け）
    public var hidesSoftwareKeyboard: Bool = false

    /// アンドゥ可能な外部テキスト変更（Optional Binding）
    ///
    /// 値がセットされると `updateUIView` でアンドゥ対応でテキストを適用し、nil にクリアする。
    /// App Intent 等からのプログラム的変更専用。通常のユーザー入力には `text` Binding を使う。
    @Binding public var undoableEdit: UndoableEdit?

    /// 明示的な公開イニシャライザ（public struct のメンバワイズ init は internal のため）
    public init(
        inputManager: InputManager,
        keyRouter: KeyRouter,
        editorStyle: EditorStyle = .init(),
        text: Binding<String> = .constant(""),
        cursorLocation: Binding<Int> = .constant(0),
        selectionLength: Binding<Int> = .constant(0),
        scrollRevision: Int = 0,
        scrollAlignment: ScrollAlignment = .minimal,
        onKeyEvent: ((IMETextView.KeyEventInfo) -> Void)? = nil,
        onKeyDown: ((HIDKeyCode, Date) -> Void)? = nil,
        onKeyUp: ((HIDKeyCode, Date) -> Void)? = nil,
        onEnglishModeChange: ((Bool) -> Void)? = nil,
        onCaretRectChange: ((CGRect) -> Void)? = nil,
        onFittingCharsPerLineChange: ((_ count: Int) -> Void)? = nil,
        onScrollRequest: ((IMETextView, Int) -> Void)? = nil,
        blockRangeProvider: BlockRangeProvider? = nil,
        blockSeparator: String? = nil,
        onSentenceNavigation: ((_ sentenceRange: NSRange, _ rects: [CGRect]) -> Void)? = nil,
        onUserScroll: (() -> Void)? = nil,
        textRangeRectsProvider: TextRangeRectsProvider? = nil,
        isFindInteractionEnabled: Bool = false,
        invisibleSpaceColor: UIColor? = nil,
        invisibleFullWidthSpaceColor: UIColor? = nil,
        invisibleTabColor: UIColor? = nil,
        invisibleNewlineColor: UIColor? = nil,
        hidesSoftwareKeyboard: Bool = false,
        undoableEdit: Binding<UndoableEdit?> = .constant(nil)
    ) {
        self.inputManager = inputManager
        self.keyRouter = keyRouter
        self.editorStyle = editorStyle
        self._text = text
        self._cursorLocation = cursorLocation
        self._selectionLength = selectionLength
        self.scrollRevision = scrollRevision
        self.scrollAlignment = scrollAlignment
        self.onKeyEvent = onKeyEvent
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onEnglishModeChange = onEnglishModeChange
        self.onCaretRectChange = onCaretRectChange
        self.onFittingCharsPerLineChange = onFittingCharsPerLineChange
        self.onScrollRequest = onScrollRequest
        self.blockRangeProvider = blockRangeProvider
        self.blockSeparator = blockSeparator
        self.onSentenceNavigation = onSentenceNavigation
        self.onUserScroll = onUserScroll
        self.textRangeRectsProvider = textRangeRectsProvider
        self.isFindInteractionEnabled = isFindInteractionEnabled
        self.invisibleSpaceColor = invisibleSpaceColor
        self.invisibleFullWidthSpaceColor = invisibleFullWidthSpaceColor
        self.invisibleTabColor = invisibleTabColor
        self.invisibleNewlineColor = invisibleNewlineColor
        self.hidesSoftwareKeyboard = hidesSoftwareKeyboard
        self._undoableEdit = undoableEdit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            cursorLocation: $cursorLocation,
            selectionLength: $selectionLength
        )
    }

    public func makeUIView(context: Context) -> IMETextView {
        let textView = IMETextView(useInvisibleCharLayout: true)

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

        // 不可視文字の初期表示状態を反映
        textView.invisibleLayoutManager?.showInvisibles = editorStyle.showInvisibles

        // 不可視文字の描画色を反映
        if let lm = textView.invisibleLayoutManager {
            if let color = invisibleSpaceColor { lm.spaceColor = color }
            if let color = invisibleFullWidthSpaceColor { lm.fullWidthSpaceColor = color }
            if let color = invisibleTabColor { lm.tabColor = color }
            if let color = invisibleNewlineColor { lm.newlineColor = color }
        }

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
        textView.onFittingCharsPerLineChange = onFittingCharsPerLineChange
        textView.blockRangeProvider = blockRangeProvider
        textView.blockSeparator = blockSeparator
        textView.onSentenceNavigation = onSentenceNavigation
        textView.onUserScroll = onUserScroll

        // TextRangeRectsProvider にクロージャを設定
        if let provider = textRangeRectsProvider {
            provider.getRects = { [weak textView] range in
                guard let textView else { return [] }
                let layoutManager = textView.layoutManager
                let textContainer = textView.textContainer
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var rects: [CGRect] = []
                layoutManager.enumerateEnclosingRects(
                    forGlyphRange: glyphRange,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: textContainer
                ) { rect, _ in
                    var adjusted = rect
                    adjusted.origin.x += textView.textContainerInset.left - textView.contentOffset.x
                    adjusted.origin.y += textView.textContainerInset.top - textView.contentOffset.y
                    rects.append(adjusted)
                }
                return rects
            }
        }

        // ソフトウェアキーボード非表示（ゲームパッド専用モード）
        textView.hidesSoftwareKeyboard = hidesSoftwareKeyboard

        // 検索置換 UI（UIFindInteraction）の有効化
        textView.isFindInteractionEnabled = isFindInteractionEnabled

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
        uiView.onFittingCharsPerLineChange = onFittingCharsPerLineChange
        uiView.blockRangeProvider = blockRangeProvider
        uiView.blockSeparator = blockSeparator
        uiView.onSentenceNavigation = onSentenceNavigation
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

        // 不可視文字の描画色を反映
        if let lm = uiView.invisibleLayoutManager {
            var colorChanged = false
            if let color = invisibleSpaceColor, lm.spaceColor != color {
                lm.spaceColor = color; colorChanged = true
            }
            if let color = invisibleFullWidthSpaceColor, lm.fullWidthSpaceColor != color {
                lm.fullWidthSpaceColor = color; colorChanged = true
            }
            if let color = invisibleTabColor, lm.tabColor != color {
                lm.tabColor = color; colorChanged = true
            }
            if let color = invisibleNewlineColor, lm.newlineColor != color {
                lm.newlineColor = color; colorChanged = true
            }
            if colorChanged && lm.showInvisibles {
                lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: uiView.textStorage.length))
            }
        }

        // composing 中は InputManager がテキスト管理しているため外部同期をスキップ
        guard inputManager.isEmpty else { return }

        // アンドゥ可能な外部編集の適用
        if let edit = undoableEdit {
            let oldNS = uiView.text as NSString
            let newNS = edit.text as NSString

            if oldNS as String != newNS as String {
                // 共通接頭辞の長さ（UTF-16 単位）
                let minLen = min(oldNS.length, newNS.length)
                var prefixLen = 0
                while prefixLen < minLen && oldNS.character(at: prefixLen) == newNS.character(at: prefixLen) {
                    prefixLen += 1
                }

                // 共通接尾辞の長さ（UTF-16 単位、接頭辞と重ならないようガード）
                let maxSuffixLen = minLen - prefixLen
                var suffixLen = 0
                while suffixLen < maxSuffixLen
                    && oldNS.character(at: oldNS.length - 1 - suffixLen) == newNS.character(at: newNS.length - 1 - suffixLen)
                {
                    suffixLen += 1
                }

                // 差分範囲のみ置換
                let replaceRange = NSRange(location: prefixLen, length: oldNS.length - prefixLen - suffixLen)
                let replacement = newNS.substring(with: NSRange(location: prefixLen, length: newNS.length - prefixLen - suffixLen))

                if let start = uiView.position(from: uiView.beginningOfDocument, offset: replaceRange.location),
                   let end = uiView.position(from: start, offset: replaceRange.length),
                   let textRange = uiView.textRange(from: start, to: end)
                {
                    uiView.replace(textRange, withText: replacement)
                }
            }

            // カーソル位置を設定
            let textLength = (uiView.text as NSString).length
            let safeLoc = min(edit.cursorLocation, textLength)
            let safeLen = min(edit.selectionLength, textLength - safeLoc)
            uiView.selectedRange = NSRange(location: safeLoc, length: safeLen)

            // Binding を同期（通常のテキスト同期パスでの二重適用を防ぐ）
            coordinator.lastTextFromUIKit = uiView.text
            text = uiView.text
            cursorLocation = safeLoc
            selectionLength = safeLen

            // リクエストをクリア
            // 注意: 非同期にすると、insertText → textViewDidChange → Binding 更新 → 次の
            // updateUIView が先に走り undoableEdit がまだ非 nil で無限ループになる。
            // 同期クリアなら、次の updateUIView 時点で nil になっておりループしない。
            undoableEdit = nil

            coordinator.appliedCursorLocation = safeLoc
            coordinator.appliedSelectionLength = safeLen
            return
        }

        // テキスト同期（SwiftUI → UIKit）
        // UIKit 起源の変更（undo/redo 含む）がフィードバックで戻ってきた場合は
        // 代入をスキップし、undoManager の履歴を保護する。
        if uiView.text != text {
            if coordinator.lastTextFromUIKit == text {
                // UIKit → Binding → updateUIView のフィードバック: スキップ
            } else {
                coordinator.isProgrammaticChange = true
                uiView.text = text
                coordinator.isProgrammaticChange = false
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

            // scrolloff 付きでカーソル位置にスクロール
            DispatchQueue.main.async {
                if scrollAlignment == .top {
                    // カーソルを上端から scrollOffLines 行目に直接配置
                    let cursorRange = NSRange(location: safeLoc, length: 0)
                    uiView.layoutManager.ensureLayout(for: uiView.textContainer)
                    let glyphRange = uiView.layoutManager.glyphRange(
                        forCharacterRange: cursorRange, actualCharacterRange: nil)
                    let cursorRect = uiView.layoutManager.boundingRect(
                        forGlyphRange: glyphRange, in: uiView.textContainer)
                    let cursorY = cursorRect.origin.y + uiView.textContainerInset.top
                    let lineHeight = uiView.editorStyle.font.lineHeight
                        + uiView.editorStyle.lineSpacing
                    let margin = lineHeight * CGFloat(uiView.editorStyle.scrollOffLines)
                    let targetOffsetY = max(0, cursorY - margin)
                    uiView.setContentOffset(
                        CGPoint(x: 0, y: targetOffsetY), animated: false)
                } else {
                    uiView.scrollRangeToVisible(NSRange(location: safeLoc, length: 0))
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

            // 非 composing 時にカーソル左側のテキストを leftSideContext に自動同期
            guard let imeView = textView as? IMETextView,
                  let im = imeView.inputManager,
                  im.isEmpty else { return }
            let start = max(0, loc - 30)
            let range = NSRange(location: start, length: loc - start)
            if range.length > 0 {
                let substring = textView.textStorage.attributedSubstring(from: range).string
                if !substring.isEmpty {
                    im.setLeftSideContext(substring)
                }
            }

            // scrolloff を適用
            DispatchQueue.main.async {
                imeView.enforceScrolloff()
            }
        }
    }
}
