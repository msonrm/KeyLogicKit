import Foundation

/// 動的ショートカット定義（日付・時刻のリアルタイム展開）
///
/// 特定の読み（「きょう」「いま」等）に対して、呼び出し時に動的にテキストを生成する。
/// 変換候補や予測候補に混ぜて表示される。
public struct DynamicShortcut: Sendable {
    /// 読み（例: "きょう"）
    public let reading: String

    /// 注釈テキスト（例: "今日の日付"）
    public let annotation: String

    /// テキスト生成クロージャ（呼び出し時に評価）
    public let resolve: @Sendable () -> String

    public init(reading: String, annotation: String, resolve: @escaping @Sendable () -> String) {
        self.reading = reading
        self.annotation = annotation
        self.resolve = resolve
    }
}

/// 組み込みの日時ショートカット
public enum BuiltInShortcuts {

    /// 日本語ロケールのフォーマッタを生成するヘルパー
    private static func jaFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = format
        return f
    }

    // キャッシュ済みフォーマッタ（パフォーマンス最適化）
    private static let slashDateFormatter = jaFormatter("yyyy/MM/dd")
    private static let kanjiDateFormatter = jaFormatter("yyyy年M月d日")
    private static let weekdayFormatter = jaFormatter("EEEE")
    private static let time24Formatter = jaFormatter("HH:mm")
    private static let time12Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "a h時mm分"
        return f
    }()

    /// 日時関連の動的ショートカット
    public static let dateTimeShortcuts: [DynamicShortcut] = [
        // きょう
        DynamicShortcut(reading: "きょう", annotation: "今日の日付") {
            slashDateFormatter.string(from: Date())
        },
        DynamicShortcut(reading: "きょう", annotation: "今日の日付") {
            kanjiDateFormatter.string(from: Date())
        },
        DynamicShortcut(reading: "きょう", annotation: "曜日") {
            weekdayFormatter.string(from: Date())
        },
        // あした
        DynamicShortcut(reading: "あした", annotation: "明日の日付") {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return slashDateFormatter.string(from: tomorrow)
        },
        DynamicShortcut(reading: "あした", annotation: "明日の日付") {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return kanjiDateFormatter.string(from: tomorrow)
        },
        // きのう
        DynamicShortcut(reading: "きのう", annotation: "昨日の日付") {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return slashDateFormatter.string(from: yesterday)
        },
        DynamicShortcut(reading: "きのう", annotation: "昨日の日付") {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return kanjiDateFormatter.string(from: yesterday)
        },
        // いま
        DynamicShortcut(reading: "いま", annotation: "現在時刻") {
            time24Formatter.string(from: Date())
        },
        DynamicShortcut(reading: "いま", annotation: "現在時刻") {
            time12Formatter.string(from: Date())
        },
    ]
}
