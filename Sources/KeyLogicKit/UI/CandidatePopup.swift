import SwiftUI

/// macOS スタイルの変換候補ポップアップ。
///
/// カーソル直下に表示し、数字キー (1-9) / 矢印キー / Space で候補を選択する。
/// スライディングウィンドウ方式で、最大9件を表示しつつ全候補をスクロール可能。
/// 追加候補（ひらがな・カタカナ・英数）は通常候補の上に注釈付きで表示する。
/// システムカラーを使用し、ダークモードに自動対応。
public struct CandidatePopup: View {

    // MARK: - 選択行のハイライト色（macOS IME 風グレー、ダークモード対応）

    /// 選択行の背景色。ライトモードではグレー系、ダークモードではやや明るいグレー。
    private static let selectionBackground = Color(.secondarySystemFill)

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
    /// 候補テキストのフォントサイズ（エディタ連動）
    var fontSize: CGFloat = 15

    public init(
        additionalCandidates: [InputManager.AdditionalCandidate],
        isAdditionalCandidateSelected: Bool,
        selectedAdditionalCandidateIndex: Int,
        candidates: [String],
        selectedIndex: Int,
        fontSize: CGFloat = 15
    ) {
        self.additionalCandidates = additionalCandidates
        self.isAdditionalCandidateSelected = isAdditionalCandidateSelected
        self.selectedAdditionalCandidateIndex = selectedAdditionalCandidateIndex
        self.candidates = candidates
        self.selectedIndex = selectedIndex
        self.fontSize = fontSize
    }

    public var body: some View {
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
                .font(.system(size: fontSize))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 160)
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
                .font(.system(size: fontSize))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 160)
        .background(isSelected ? Self.selectionBackground : Color.clear)
    }
}
