import UIKit

/// 不可視文字（スペース、タブ、改行）を描画する NSLayoutManager サブクラス
///
/// `showInvisibles` が true のとき、通常のグリフ描画に加えて
/// 不可視文字の記号を半透明で重ねて描画する。
/// 全角スペースは赤系で表示し、半角スペースと視覚的に区別する。
class InvisibleCharLayoutManager: NSLayoutManager {
    /// 不可視文字の表示 ON/OFF
    var showInvisibles = false

    // MARK: - 不可視文字の描画色設定

    /// 半角スペースの描画色
    var spaceColor: UIColor = UIColor.label.withAlphaComponent(0.2)
    /// 全角スペースの描画色（赤系で区別）
    var fullWidthSpaceColor: UIColor = UIColor.systemRed.withAlphaComponent(0.3)
    /// タブの描画色
    var tabColor: UIColor = UIColor.label.withAlphaComponent(0.2)
    /// 改行の描画色
    var newlineColor: UIColor = UIColor.label.withAlphaComponent(0.2)

    // MARK: - 不可視文字の記号定義

    /// 半角スペース (U+0020) → 中黒ドット
    nonisolated(unsafe) private static let halfWidthSpaceSymbol: NSString = "·"
    /// 全角スペース (U+3000) → 四角
    nonisolated(unsafe) private static let fullWidthSpaceSymbol: NSString = "□"
    /// タブ (U+0009) → 矢印
    nonisolated(unsafe) private static let tabSymbol: NSString = "→"
    /// 改行 (U+000A) → ピルクロー
    nonisolated(unsafe) private static let newlineSymbol: NSString = "¶"

    // MARK: - 描画

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard showInvisibles, let textStorage = textStorage else { return }

        let fullText = textStorage.string as NSString

        enumerateLineFragments(forGlyphRange: glyphsToShow) { [weak self] _, _, textContainer, glyphRange, _ in
            guard let self else { return }

            for glyphIndex in glyphRange.location ..< NSMaxRange(glyphRange) {
                let charIndex = self.characterIndexForGlyph(at: glyphIndex)
                guard charIndex < fullText.length else { continue }

                let char = fullText.character(at: charIndex)
                let symbolAndColor = self.symbolAndColor(for: char)
                guard let (symbol, color) = symbolAndColor else { continue }

                let glyphPoint = self.location(forGlyphAt: glyphIndex)
                let lineRect = self.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

                // 描画位置（origin はテキストコンテナのオフセット）
                let drawPoint = CGPoint(
                    x: origin.x + lineRect.origin.x + glyphPoint.x,
                    y: origin.y + lineRect.origin.y
                )

                // フォントサイズをテキストから取得
                let fontSize: CGFloat
                if charIndex < textStorage.length {
                    let attrs = textStorage.attributes(at: charIndex, effectiveRange: nil)
                    let font = attrs[.font] as? UIFont
                    fontSize = font?.pointSize ?? 14
                } else {
                    fontSize = 14
                }

                let symbolFont = UIFont.systemFont(ofSize: fontSize)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: symbolFont,
                    .foregroundColor: color,
                ]

                symbol.draw(at: drawPoint, withAttributes: attrs)
            }
        }
    }

    /// 文字に対応する不可視文字記号と描画色を返す
    private func symbolAndColor(for char: unichar) -> (NSString, UIColor)? {
        switch char {
        case 0x0020: // 半角スペース
            return (Self.halfWidthSpaceSymbol, spaceColor)
        case 0x3000: // 全角スペース（赤系で区別）
            return (Self.fullWidthSpaceSymbol, fullWidthSpaceColor)
        case 0x0009: // タブ
            return (Self.tabSymbol, tabColor)
        case 0x000A: // 改行
            return (Self.newlineSymbol, newlineColor)
        default:
            return nil
        }
    }
}
