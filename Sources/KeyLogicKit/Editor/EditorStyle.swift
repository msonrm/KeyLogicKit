import UIKit

/// エディタの表示スタイル設定
public struct EditorStyle: Equatable {
    public var font: UIFont
    public var lineSpacing: CGFloat
    public var textAlignment: NSTextAlignment
    public var showInvisibles: Bool
    /// Vim の scrolloff 相当。カーソルが上端・下端からこの行数以内に入らないようスクロールを自動調整する
    public var scrollOffLines: Int

    public init(
        font: UIFont = .monospacedSystemFont(ofSize: 18, weight: .regular),
        lineSpacing: CGFloat = 0,
        textAlignment: NSTextAlignment = .natural,
        showInvisibles: Bool = false,
        scrollOffLines: Int = 5
    ) {
        self.font = font
        self.lineSpacing = lineSpacing
        self.textAlignment = textAlignment
        self.showInvisibles = showInvisibles
        self.scrollOffLines = scrollOffLines
    }

    /// typingAttributes 用の辞書を生成
    public var typingAttributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.alignment = textAlignment
        return [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ]
    }
}
