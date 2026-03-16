import SwiftUI

/// 予測候補ポップアップ（composing 中にカーソル直下に表示）
///
/// 変換候補ウィンドウ（CandidatePopup）とは別に、composing 中のキーストロークごとに
/// 自動表示される。Tab キーで先頭候補を確定できる。
///
/// `anchor` と `bounds` を指定すると、表示領域に応じて自動的にフリップ・クランプする。
/// - デフォルト: カーソル直下に表示
/// - 垂直フリップ: 下端を超える場合、カーソル直上に反転
/// - 水平クランプ: 右端を超える場合、右端に収まるよう左にずらす
public struct PredictionPopup: View {

    /// アンカーとポップアップの間隔
    private static let gap: CGFloat = 4

    /// 予測候補テキストのリスト
    public let predictions: [PredictionItem]

    /// Tab で巡回選択中のインデックス（nil = 未選択）
    public let selectedIndex: Int?

    /// 表示フォント
    public var font: Font

    /// カーソル矩形（配置のアンカー）
    private let anchor: CGRect?
    /// 表示領域のサイズ（overlay の親ビューサイズ）
    private let bounds: CGSize?

    /// ポップアップ自身のサイズ（onGeometryChange で測定）
    @State private var popupSize: CGSize = .zero

    public init(predictions: [PredictionItem], selectedIndex: Int? = nil,
                font: Font, anchor: CGRect? = nil, bounds: CGSize? = nil) {
        self.predictions = predictions
        self.selectedIndex = selectedIndex
        self.font = font
        self.anchor = anchor
        self.bounds = bounds
    }

    public var body: some View {
        popupContent
            .onGeometryChange(for: CGSize.self, of: \.size) { newSize in
                popupSize = newSize
            }
            .offset(x: calculatedOffset.x, y: calculatedOffset.y)
    }

    // MARK: - Auto-Positioning

    /// anchor / bounds に基づいてオフセットを計算する。
    /// 未指定の場合は (0, 0) を返す（外部 .offset() で制御する従来の使い方）。
    private var calculatedOffset: CGPoint {
        guard let anchor, let bounds else { return .zero }

        var x = anchor.minX
        var y = anchor.maxY + Self.gap

        // 垂直フリップ: 下にはみ出す場合はカーソル上方に表示
        if y + popupSize.height > bounds.height {
            y = anchor.minY - popupSize.height - Self.gap
        }

        // 水平クランプ: 右にはみ出す場合は左にずらす
        if x + popupSize.width > bounds.width {
            x = bounds.width - popupSize.width
        }

        // 左端・上端の最低マージン
        x = max(0, x)
        y = max(0, y)

        return CGPoint(x: x, y: y)
    }

    // MARK: - Content

    private var popupContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(predictions.enumerated()), id: \.offset) { index, item in
                let isSelected = selectedIndex == index
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(item.text)
                        .font(font)
                    if let annotation = item.annotation {
                        Text(annotation)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            }
        }
        .padding(.vertical, 2)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color(.separator), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 1)
        .fixedSize()
    }
}

/// 予測候補アイテム
public struct PredictionItem {
    public let text: String
    public let annotation: String?

    public init(text: String, annotation: String? = nil) {
        self.text = text
        self.annotation = annotation
    }
}
