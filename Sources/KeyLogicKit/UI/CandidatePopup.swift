import SwiftUI

/// macOS スタイルの変換候補ポップアップ。
///
/// カーソル直下に表示し、数字キー (1-9) / 矢印キー / Space で候補を選択する。
/// スライディングウィンドウ方式で、最大9件を表示しつつ全候補をスクロール可能。
/// 追加候補（ひらがな・カタカナ・英数）は通常候補の上に注釈付きで表示する。
/// システムカラーを使用し、ダークモードに自動対応。
///
/// `anchor` と `bounds` を指定すると、表示領域に応じて自動的にフリップ・クランプする。
/// - デフォルト: カーソル直下に表示
/// - 垂直フリップ: 下端を超える場合、カーソル直上に反転
/// - 水平クランプ: 右端を超える場合、右端に収まるよう左にずらす
public struct CandidatePopup: View {

    // MARK: - 選択行のハイライト色（macOS IME 風グレー、ダークモード対応）

    /// 選択行の背景色。ライトモードではグレー系、ダークモードではやや明るいグレー。
    private static let selectionBackground = Color(.secondarySystemFill)

    /// アンカーとポップアップの間隔
    private static let gap: CGFloat = 4

    /// 追加候補（ひらがな・カタカナ・英数、上矢印で展開）
    let additionalCandidates: [InputManager.AdditionalCandidate]
    /// 追加候補が選択されているかどうか
    let isAdditionalCandidateSelected: Bool
    /// 追加候補内の選択インデックス（0-based）
    let selectedAdditionalCandidateIndex: Int
    /// 現在ウィンドウ内に表示する候補テキスト（最大9件）
    let candidates: [String]
    /// ウィンドウ内での選択位置（0-based）
    let selectedIndex: Int
    /// 候補テキストのフォント（エディタ連動）
    var font: Font
    /// フォントサイズ（動的幅計算用）
    var fontSize: CGFloat

    /// カーソル矩形（配置のアンカー）
    private let anchor: CGRect?
    /// 表示領域のサイズ（overlay の親ビューサイズ）
    private let bounds: CGSize?

    /// ポップアップ自身のサイズ（onGeometryChange で測定）
    @State private var popupSize: CGSize = .zero

    public init(
        additionalCandidates: [InputManager.AdditionalCandidate],
        isAdditionalCandidateSelected: Bool,
        selectedAdditionalCandidateIndex: Int,
        candidates: [String],
        selectedIndex: Int,
        font: Font = .system(size: 15),
        fontSize: CGFloat = 15,
        anchor: CGRect? = nil,
        bounds: CGSize? = nil
    ) {
        self.additionalCandidates = additionalCandidates
        self.isAdditionalCandidateSelected = isAdditionalCandidateSelected
        self.selectedAdditionalCandidateIndex = selectedAdditionalCandidateIndex
        self.candidates = candidates
        self.selectedIndex = selectedIndex
        self.font = font
        self.fontSize = fontSize
        self.anchor = anchor
        self.bounds = bounds
    }

    /// 候補テキストの最長幅に基づいて最小幅を動的に計算する
    private var dynamicMinWidth: CGFloat {
        let indexColumnWidth: CGFloat = 28   // 数字ラベル + 間隔
        let horizontalPadding: CGFloat = 16  // 左右パディング
        let baseMinWidth: CGFloat = 120      // 絶対最小幅
        let maxWidth: CGFloat = 400          // 最大幅制限

        let allTexts = candidates + additionalCandidates.map(\.text)
        let longestCount = allTexts.map(\.count).max() ?? 0
        let estimatedCharWidth = fontSize * 1.1  // 全角文字の概算幅
        let contentWidth = CGFloat(longestCount) * estimatedCharWidth
        let totalWidth = indexColumnWidth + contentWidth + horizontalPadding

        return min(max(totalWidth, baseMinWidth), maxWidth)
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
            // 追加候補（通常候補の上に表示）
            ForEach(
                Array(additionalCandidates.enumerated()),
                id: \.offset
            ) { index, additional in
                let isSelected = isAdditionalCandidateSelected && index == selectedAdditionalCandidateIndex
                additionalCandidateRow(
                    text: additional.text,
                    annotation: additional.annotation,
                    isSelected: isSelected
                )
            }

            // 追加候補と通常候補の区切り線
            if !additionalCandidates.isEmpty {
                Divider()
                    .padding(.horizontal, 4)
            }

            // 通常候補
            ForEach(
                Array(candidates.enumerated()),
                id: \.offset
            ) { index, candidate in
                let isSelected = !isAdditionalCandidateSelected && index == selectedIndex
                candidateRow(index: index, text: candidate, isSelected: isSelected)
            }
        }
        .padding(.vertical, 2)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .fixedSize()
    }

    // MARK: - Private

    @ViewBuilder
    private func candidateRow(index: Int, text: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isSelected ? Color.primary.opacity(0.6) : Color.secondary)
                .frame(width: 18, alignment: .trailing)
            Text(text)
                .font(font)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: dynamicMinWidth)
        .background(isSelected ? Self.selectionBackground : Color.clear)
    }

    @ViewBuilder
    private func additionalCandidateRow(text: String, annotation: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(annotation)
                .font(.system(.caption2))
                .foregroundStyle(isSelected ? Color.primary.opacity(0.6) : Color.secondary)
                .frame(minWidth: 18, alignment: .trailing)
            Text(text)
                .font(font)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: dynamicMinWidth)
        .background(isSelected ? Self.selectionBackground : Color.clear)
    }
}
