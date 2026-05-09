import Foundation

/// 編集メニュー（選択時のフローティングメニュー）に追加するカスタムアクション項目。
///
/// `IMETextView.editMenuActionsProvider` から返した配列が、システム項目（カット・コピー・
/// ペースト・調べる・翻訳・共有 等）の末尾にサブメニューとしてまとめて並ぶ。
public struct EditMenuItem: Sendable {
    /// 表示タイトル
    public let title: String

    /// SF Symbols 名（指定すると `UIImage(systemName:)` でアイコンを付ける）
    public let systemImage: String?

    /// 選択範囲を引数に呼ばれるハンドラ。MainActor 上で実行される。
    public let handler: @MainActor (NSRange) -> Void

    public init(
        title: String,
        systemImage: String? = nil,
        handler: @escaping @MainActor (NSRange) -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.handler = handler
    }
}
