import Foundation

/// キーマップ JSON ファイルの読み書き
///
/// Documents/Keymaps ディレクトリにカスタムキーマップを保存・読み込みする。
/// 組み込みキーマップ（DefaultKeymaps）のエクスポートにも使用可能。
public enum KeymapStore {

    /// Documents/Keymaps ディレクトリの URL
    public static var keymapsDirectory: URL {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        return documentsURL.appendingPathComponent("Keymaps", isDirectory: true)
    }

    /// KeymapDefinition を JSON Data にエンコード
    public static func encode(_ definition: KeymapDefinition) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(definition)
    }

    /// JSON Data から KeymapDefinition をデコード
    public static func decode(from data: Data) throws -> KeymapDefinition {
        let decoder = JSONDecoder()
        return try decoder.decode(KeymapDefinition.self, from: data)
    }

    /// JSON ファイルからキーマップを読み込む
    public static func load(from url: URL) throws -> KeymapDefinition {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }

    /// キーマップを JSON ファイルに書き出す
    ///
    /// 親ディレクトリが存在しない場合は自動作成する。
    public static func save(_ definition: KeymapDefinition, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let data = try encode(definition)
        try data.write(to: url, options: .atomic)
    }

    /// Documents/Keymaps 内のカスタムキーマップ一覧を取得
    ///
    /// .json ファイルの URL リストを返す。ディレクトリが存在しない場合は空配列。
    public static func listCustomKeymaps() -> [URL] {
        let directory = keymapsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
