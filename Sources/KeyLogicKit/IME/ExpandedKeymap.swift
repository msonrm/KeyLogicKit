import Foundation

/// キーマップの事前展開済みデータ。
///
/// `KeymapDefinition` から一度だけ構築し、`InputManager` で共有する。
/// ランタイムのプレフィックスセット構築やフィルタリングを排除し、
/// キーマップ切替時のコストを初回構築に集約する。
public struct ExpandedKeymap: Sendable {

    /// 元のキーマップ定義
    public let definition: KeymapDefinition

    /// マージ済み入力マッピング（inputBase + suffixRules + explicitMappings、_comment フィルタ済み）
    ///
    /// `definition.inputMappings` から `_comment` プレフィックスを除去した完全テーブル。
    /// nil の場合はマッピングなし（変換エンジン固有のデフォルトテーブルのみ使用）。
    public let inputMappings: [String: String]?

    /// greedy longest-match 用プレフィックス集合
    ///
    /// `inputMappings` の全キーについて、長さ 1 〜 (key.count - 1) の部分文字列を登録。
    /// 逐次入力バッファで「次のキーを待つべきか」を O(1) で判定する。
    public let prefixSet: Set<String>

    /// 半角→全角変換テーブル（sequential のみ）
    ///
    /// `InputBehavior.sequential(characterMap:)` から抽出。chord の場合は空。
    public let characterMap: [Character: Character]

    /// キーリマップ（物理→論理、sequential のみ）
    ///
    /// `definition.keyRemap` を `[Character: Character]` に変換したもの。
    public let keyRemap: [Character: Character]

    /// Chord 事前展開データ（chord のみ、sequential の場合は nil）
    public let chordData: ExpandedChordData?

    /// `KeymapDefinition` から構築する
    public init(definition: KeymapDefinition) {
        self.definition = definition

        // inputMappings: _comment フィルタ済み
        if let mappings = definition.inputMappings {
            let filtered = mappings.filter { !$0.key.hasPrefix("_comment") }
            self.inputMappings = filtered.isEmpty ? nil : filtered
        } else {
            self.inputMappings = nil
        }

        // prefixSet 構築
        if let mappings = self.inputMappings {
            var prefixes: Set<String> = []
            for key in mappings.keys {
                for len in 1..<key.count {
                    prefixes.insert(String(key.prefix(len)))
                }
            }
            self.prefixSet = prefixes
        } else {
            self.prefixSet = []
        }

        // behavior に応じたデータ抽出
        switch definition.behavior {
        case .sequential(let charMap):
            self.characterMap = charMap
            self.chordData = nil
        case .chord(let config):
            self.characterMap = [:]
            self.chordData = ExpandedChordData(config: config)
        }

        // keyRemap: [String: String] → [Character: Character]
        if let remap = definition.keyRemap {
            var charRemap: [Character: Character] = [:]
            for (from, to) in remap {
                if let fromChar = from.first, let toChar = to.first {
                    charRemap[fromChar] = toChar
                }
            }
            self.keyRemap = charRemap
        } else {
            self.keyRemap = [:]
        }
    }
}

/// Chord 配列の事前展開済みルックアップデータ
public struct ExpandedChordData: Sendable {

    /// HID キーコード → ChordKey の変換テーブル
    public let hidToChordKey: [HIDKeyCode: ChordKey]

    /// キーの組合せビットマスク → 出力文字列
    public let lookupTable: [UInt64: String]

    /// キーの組合せビットマスク → 特殊アクション
    public let specialActions: [UInt64: KeyAction]

    /// シフトキー設定（ChordKey → 単打時アクション）
    public let shiftKeyConfigs: [ChordKey: KeyAction?]

    /// 同時打鍵判定ウィンドウ（秒）
    public let simultaneousWindow: TimeInterval

    /// 英語モード用ルックアップテーブル（nil = 英語モードなし）
    public let englishLookupTable: [UInt64: String]?

    /// 英語モード用特殊アクション（nil = 英語モードなし）
    public let englishSpecialActions: [UInt64: KeyAction]?

    /// `ChordConfig` から構築
    public init(config: KeymapDefinition.ChordConfig) {
        self.hidToChordKey = config.hidToKey
        self.lookupTable = config.lookupTable
        self.specialActions = config.specialActions
        self.simultaneousWindow = config.simultaneousWindow
        self.englishLookupTable = config.englishLookupTable
        self.englishSpecialActions = config.englishSpecialActions

        var shiftConfigs: [ChordKey: KeyAction?] = [:]
        for shiftKey in config.shiftKeys {
            shiftConfigs[shiftKey.key] = shiftKey.singleTapAction
        }
        self.shiftKeyConfigs = shiftConfigs
    }
}
