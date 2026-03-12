import SwiftUI

/// 予測候補ポップアップ（composing 中にカーソル直下に表示）
///
/// 変換候補ウィンドウ（CandidatePopup）とは別に、composing 中のキーストロークごとに
/// 自動表示される。Tab キーで先頭候補を確定できる。
public struct PredictionPopup: View {

    /// 予測候補テキストのリスト
    public let predictions: [PredictionItem]

    /// 表示フォント
    public var font: Font

    public init(predictions: [PredictionItem], font: Font) {
        self.predictions = predictions
        self.font = font
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(predictions.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
