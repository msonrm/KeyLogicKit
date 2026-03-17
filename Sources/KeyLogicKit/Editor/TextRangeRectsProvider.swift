import UIKit

/// テキスト範囲の視覚 rect を問い合わせるプロバイダ
///
/// IMETextViewRepresentable が makeUIView で内部のクロージャを設定する。
/// アプリ側はこのオブジェクトを保持し、getRects を呼ぶことで
/// 任意の NSRange に対応する視覚 rect を取得できる。
public final class TextRangeRectsProvider: @unchecked Sendable {
    /// 指定 NSRange の視覚 rect 配列を返す。未設定時は空配列。
    public var getRects: @MainActor (_ range: NSRange) -> [CGRect] = { _ in [] }

    public init() {}
}
