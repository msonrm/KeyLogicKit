import UIKit

/// エディタの表示スタイル設定
public struct EditorStyle: Equatable {
    public var font: UIFont
    public var lineSpacing: CGFloat
    public var textAlignment: NSTextAlignment

    public init(
        font: UIFont = .monospacedSystemFont(ofSize: 18, weight: .regular),
        lineSpacing: CGFloat = 0,
        textAlignment: NSTextAlignment = .natural
    ) {
        self.font = font
        self.lineSpacing = lineSpacing
        self.textAlignment = textAlignment
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
