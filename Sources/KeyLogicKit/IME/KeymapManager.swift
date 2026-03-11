import Foundation

/// キーマップマネージャの設定
///
/// 外部アプリがアプリ固有のキーマップを組み込みとして追加したり、
/// デフォルトキーマップを変更するために使用する。
///
/// ```swift
/// let config = KeymapManagerConfiguration(
///     additionalKeymaps: [("builtin:my_layout", myDefinition)],
///     defaultKeymapID: "builtin:my_layout"
/// )
/// let manager = KeymapManager(configuration: config)
/// ```
public struct KeymapManagerConfiguration: Sendable {
    /// 追加の組み込みキーマップ（アプリ固有）
    ///
    /// `DefaultKeymaps.allKeymaps` に続けて一覧に表示される。
    /// ID は `"builtin:"` プレフィックスを推奨（`loadDefinition` で解決可能にするため）。
    public var additionalKeymaps: [(id: String, definition: KeymapDefinition)]

    /// デフォルトのキーマップ ID（未選択時のフォールバック）
    public var defaultKeymapID: String

    public init(
        additionalKeymaps: [(id: String, definition: KeymapDefinition)] = [],
        defaultKeymapID: String = "builtin:romaji_us"
    ) {
        self.additionalKeymaps = additionalKeymaps
        self.defaultKeymapID = defaultKeymapID
    }
}

/// キーマップの管理（一覧・選択・永続化・インポート・削除）
///
/// 組み込みキーマップとカスタムキーマップを統一的に管理する。
/// 選択状態は UserDefaults に永続化される。
///
/// 外部アプリからアプリ固有のキーマップを追加するには
/// `KeymapManagerConfiguration` 付きの `init(configuration:)` を使用する。
@Observable
public class KeymapManager {

    /// キーマップエントリ
    public struct KeymapEntry: Identifiable, Hashable {
        /// 一意な識別子（"builtin:romaji_us", "custom:myLayout.json" 等）
        public let id: String
        /// 表示名（JSON の name フィールド）
        public let name: String
        /// 組み込みかどうか
        public let isBuiltIn: Bool
    }

    /// 全キーマップエントリ（組み込み + カスタム）
    public private(set) var entries: [KeymapEntry] = []

    /// 選択中のエントリ ID
    public var selectedEntryID: String {
        didSet { persist() }
    }

    /// 選択中のエントリの表示名
    public var selectedEntryName: String {
        entries.first(where: { $0.id == selectedEntryID })?.name ?? "不明"
    }

    /// 直近のエラーメッセージ（UI 表示用）
    public var lastError: String?

    // MARK: - Private

    private let configuration: KeymapManagerConfiguration

    private static let selectedKeymapIDKey = "selectedKeymapID"

    // MARK: - 初期化

    /// デフォルト設定で初期化する（後方互換）
    public convenience init() {
        self.init(configuration: KeymapManagerConfiguration())
    }

    /// 設定付きで初期化する
    ///
    /// 外部アプリがアプリ固有のキーマップを組み込みとして追加する場合に使用。
    /// - Parameter configuration: キーマップマネージャの設定
    public init(configuration: KeymapManagerConfiguration) {
        self.configuration = configuration
        // UserDefaults から選択状態を復元
        let savedID = UserDefaults.standard.string(forKey: Self.selectedKeymapIDKey)
        self.selectedEntryID = savedID ?? configuration.defaultKeymapID
        reload()
        // 保存された ID が一覧にない場合はデフォルトにフォールバック
        if !entries.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = configuration.defaultKeymapID
        }
    }

    // MARK: - 一覧管理

    /// キーマップ一覧を再読み込みする
    public func reload() {
        var newEntries: [KeymapEntry] = []

        // KeyLogicKit 組み込みキーマップ
        for (id, definition) in DefaultKeymaps.allKeymaps {
            newEntries.append(KeymapEntry(id: id, name: definition.name, isBuiltIn: true))
        }

        // アプリ固有の組み込みキーマップ
        for (id, definition) in configuration.additionalKeymaps {
            newEntries.append(KeymapEntry(id: id, name: definition.name, isBuiltIn: true))
        }

        // カスタムキーマップ（Documents/Keymaps/ 内の JSON ファイル）
        for url in KeymapStore.listCustomKeymaps() {
            let fileName = url.lastPathComponent
            let entryID = "custom:\(fileName)"
            if let definition = try? KeymapStore.load(from: url) {
                newEntries.append(KeymapEntry(id: entryID, name: definition.name, isBuiltIn: false))
            }
        }

        entries = newEntries
    }

    // MARK: - キーマップ読み込み

    /// 選択中のキーマップ定義を読み込む
    public func loadSelectedDefinition() -> KeymapDefinition? {
        loadDefinition(for: selectedEntryID)
    }

    /// 指定 ID のキーマップ定義を読み込む
    public func loadDefinition(for entryID: String) -> KeymapDefinition? {
        if entryID.hasPrefix("builtin:") {
            // KeyLogicKit 組み込みキーマップ
            if let definition = DefaultKeymaps.allKeymaps.first(where: { $0.id == entryID })?.definition {
                return definition
            }
            // アプリ固有の組み込みキーマップ
            if let definition = configuration.additionalKeymaps.first(where: { $0.id == entryID })?.definition {
                return definition
            }
            return nil
        } else if entryID.hasPrefix("custom:") {
            // カスタムキーマップ
            let fileName = String(entryID.dropFirst("custom:".count))
            let url = KeymapStore.keymapsDirectory.appendingPathComponent(fileName)
            return try? KeymapStore.load(from: url)
        }
        return nil
    }

    // MARK: - インポート・削除

    /// JSON ファイルからキーマップをインポートする
    ///
    /// ファイルを Documents/Keymaps にコピーし、一覧を更新する。
    /// - Parameter sourceURL: インポート元の URL（ファイルピッカーから取得）
    public func importKeymap(from sourceURL: URL) throws {
        // Security scoped resource access
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        // JSON を読み込んで検証
        let data = try Data(contentsOf: sourceURL)
        let definition = try KeymapStore.decode(from: data)

        // Documents/Keymaps にコピー
        let fileName = sourceURL.lastPathComponent
        let destURL = KeymapStore.keymapsDirectory.appendingPathComponent(fileName)
        try KeymapStore.save(definition, to: destURL)

        // 一覧を更新
        reload()

        // インポートしたキーマップを選択
        let entryID = "custom:\(fileName)"
        if entries.contains(where: { $0.id == entryID }) {
            selectedEntryID = entryID
        }
    }

    /// カスタムキーマップを削除する
    ///
    /// 選択中のキーマップを削除した場合はデフォルトにフォールバックする。
    public func deleteCustomKeymap(entryID: String) throws {
        guard entryID.hasPrefix("custom:") else { return }
        let fileName = String(entryID.dropFirst("custom:".count))
        let url = KeymapStore.keymapsDirectory.appendingPathComponent(fileName)
        try FileManager.default.removeItem(at: url)

        // 選択中のキーマップを削除した場合はデフォルトにフォールバック
        if selectedEntryID == entryID {
            selectedEntryID = configuration.defaultKeymapID
        }

        reload()
    }

    // MARK: - Private

    private func persist() {
        UserDefaults.standard.set(selectedEntryID, forKey: Self.selectedKeymapIDKey)
    }
}
