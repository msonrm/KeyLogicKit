import XCTest
import Foundation
import KeyLogicKit

/// KeymapCodable のデコード仕様のユニットテスト
final class KeymapCodableTests: XCTestCase {

    /// chord テーブル（lookupTable / specialActions）の `_comment` キーは注記として無視される
    ///
    /// keymap-format.md の仕様。かわせみ配列 JSON（lookupTable に `_comment_*` を含む）が
    /// デコード不能になっていた回帰の防止（PR #630 で修正）。
    func testChordTablesIgnoreCommentKeys() throws {
        let json = """
        {
          "formatVersion": "1.0",
          "name": "テスト配列",
          "keyboardLayout": "us",
          "behavior": {
            "type": "chord",
            "config": {
              "hidToKey": { "q": "Q", "a": "A" },
              "lookupTable": {
                "_comment_single": "単打",
                "Q": "に",
                "_comment_chord": "同時打鍵",
                "A+Q": "ぬ"
              },
              "specialActions": {
                "_comment_actions": "特殊アクション",
                "Q+W": "deleteBack"
              },
              "simultaneousWindow": 0.1,
              "shiftKeys": []
            }
          }
        }
        """

        let definition = try KeymapStore.decode(from: Data(json.utf8))

        guard case .chord(let config) = definition.behavior else {
            XCTFail("chord としてデコードされていない")
            return
        }
        // _comment キーは除外され、実エントリだけが残る
        XCTAssertEqual(config.lookupTable.count, 2)
        XCTAssertEqual(config.lookupTable[ChordKey.Q.bit], "に")
        XCTAssertEqual(config.lookupTable[ChordKey.A.bit | ChordKey.Q.bit], "ぬ")
        XCTAssertEqual(config.specialActions.count, 1)
    }

    // MARK: - roundtrip（encode → decode の対称性）

    /// バンドル済みキーマップの encode → decode → encode が冪等で、主要フィールドが保存される
    ///
    /// sequential（inputBase 有/無）と chord の両方をカバーする。
    /// encode は `inputBase`/`suffixRules` 展開時に圧縮形式（explicitInputMappings）を書き出し、
    /// decode 時に再展開する対称設計のため、AZIK のような派生テーブルでも冪等になる。
    /// `KeyAction` は Equatable でないため specialActions はキー集合で照合する。
    func testBundleKeymapsRoundtrip() throws {
        let cases: [(String, KeymapDefinition?)] = [
            ("romaji_us(builtin)", DefaultKeymaps.romajiUS),
            ("azik_us", DefaultKeymaps.loadBundleKeymap("azik_us")),
            ("tsuki2-263_us", DefaultKeymaps.loadBundleKeymap("tsuki2-263_us")),
            ("nicola_us", DefaultKeymaps.loadBundleKeymap("nicola_us")),
        ]

        for (label, maybe) in cases {
            guard let def = maybe else {
                XCTFail("キーマップをロードできない: \(label)")
                continue
            }

            let data1 = try KeymapStore.encode(def)
            let def2 = try KeymapStore.decode(from: data1)
            let data2 = try KeymapStore.encode(def2)

            // 冪等性: 2 回目の encode が 1 回目と一致（辞書キー順は正規化して吸収）。
            // decode が情報を落とすと data1 != data2 になるため、対称性を厳密に検証できる。
            XCTAssertEqual(try Self.normalizedJSON(data1), try Self.normalizedJSON(data2),
                           "\(label): encode→decode→encode が冪等でない")

            // メタデータの保存
            XCTAssertEqual(def.name, def2.name, "\(label): name")
            XCTAssertEqual(def.keyboardLayout, def2.keyboardLayout, "\(label): keyboardLayout")
            XCTAssertEqual(def.author, def2.author, "\(label): author")
            XCTAssertEqual(def.license, def2.license, "\(label): license")
            XCTAssertEqual(def.inputBase, def2.inputBase, "\(label): inputBase")

            // behavior の主要テーブルの保存（Equatable なフィールドのみ）
            switch (def.behavior, def2.behavior) {
            case let (.sequential(mapA), .sequential(mapB)):
                XCTAssertEqual(mapA, mapB, "\(label): characterMap")
                XCTAssertEqual(def.inputMappings, def2.inputMappings, "\(label): inputMappings（展開後）")
                XCTAssertEqual(def.explicitInputMappings, def2.explicitInputMappings,
                               "\(label): explicitInputMappings（圧縮形式）")
                XCTAssertEqual(def.keyRemap, def2.keyRemap, "\(label): keyRemap")
            case let (.chord(cfgA), .chord(cfgB)):
                XCTAssertEqual(cfgA.hidToKey, cfgB.hidToKey, "\(label): hidToKey")
                XCTAssertEqual(cfgA.lookupTable, cfgB.lookupTable, "\(label): lookupTable")
                XCTAssertEqual(cfgA.simultaneousWindow, cfgB.simultaneousWindow,
                               "\(label): simultaneousWindow")
                XCTAssertEqual(Set(cfgA.specialActions.keys), Set(cfgB.specialActions.keys),
                               "\(label): specialActions のキー集合")
                XCTAssertEqual(cfgA.shiftKeys.map(\.key), cfgB.shiftKeys.map(\.key),
                               "\(label): shiftKeys")
            default:
                XCTFail("\(label): behavior の種類が roundtrip で変化した")
            }
        }
    }

    // MARK: - 版ゲート

    /// `formatVersion` のメジャーが違う JSON は**黙って部分デコードせず**拒否する
    ///
    /// 旧実装が新セマンティクスを無視したまま動く silent 縮退を防ぐため
    /// （薙刀式の `judgment` を旧エンジンが黙って時間窓で動かした事故と同じ形）。
    func testFormatVersionGate() throws {
        func json(_ version: String) -> Data {
            Data("""
            {
              "formatVersion": "\(version)",
              "name": "テスト配列",
              "keyboardLayout": "us",
              "behavior": { "type": "sequential", "characterMap": {} }
            }
            """.utf8)
        }

        // 対応メジャー（1.x）は通る。マイナーの差は許容する
        for version in ["1.0", "1.1", "1.10"] {
            XCTAssertNoThrow(try KeymapStore.decode(from: json(version)),
                             "formatVersion \(version) は読めるべき")
        }

        // メジャーが違う / 数値でない → 拒否
        for version in ["2.0", "0.9", "abc", ""] {
            XCTAssertThrowsError(try KeymapStore.decode(from: json(version)),
                                 "formatVersion \(version) は拒否されるべき") { error in
                guard case DecodingError.dataCorrupted = error else {
                    XCTFail("formatVersion \(version): dataCorrupted を期待したが \(error)")
                    return
                }
            }
        }
    }

    // MARK: - requires（必須セマンティクスの宣言）

    /// 理解できないセマンティクスを要求する JSON は**動かす代わりに拒否する**
    ///
    /// 版ゲート（formatVersion）では拾えない「同じ構造だが意味論が変わった」変更に効く。
    /// 実例 = `judgment: "mutual"` を知らない旧実装が黙って時間窓で動かした事故。
    func testRequiresSemantics() throws {
        func json(_ requiresLine: String) -> Data {
            Data("""
            {
              "formatVersion": "1.0",
              \(requiresLine)
              "name": "テスト配列",
              "keyboardLayout": "us",
              "behavior": { "type": "sequential", "characterMap": {} }
            }
            """.utf8)
        }

        // 理解できる名前だけ / 省略 → 通る
        XCTAssertNoThrow(try KeymapStore.decode(from: json("")))
        XCTAssertNoThrow(try KeymapStore.decode(
            from: json("\"requires\": [\"behavior:sequential\", \"controlBindings\"],")))

        // 未実装のセマンティクス（段 3 / 段 4 で実装予定）→ 拒否
        for name in ["roles", "layouts", "postModify", "judgment:stroke"] {
            XCTAssertThrowsError(
                try KeymapStore.decode(from: json("\"requires\": [\"\(name)\"],")),
                "requires \(name) は拒否されるべき"
            )
        }

        // 保持もされる（ホストが何を要求されたか見られる）
        let def = try KeymapStore.decode(from: json("\"requires\": [\"judgment:mutual\"],"))
        XCTAssertEqual(def.requires, ["judgment:mutual"])
    }

    // MARK: - 未知のトップレベルフィールド

    /// 未知のフィールドは**黙って飛ばさず拒否する**
    ///
    /// v2 で足すフィールド（roles / layouts / base）を、古い実装が「知らないものを
    /// 飛ばして読む」ことを防ぐため。許可リストは `CodingKeys` ではなく
    /// `knownFields`（schema の properties と一致）である点が要。
    func testUnknownTopLevelFields() throws {
        func json(_ extra: String) -> Data {
            Data("""
            {
              "formatVersion": "1.0",
              \(extra)
              "name": "テスト配列",
              "keyboardLayout": "us",
              "behavior": { "type": "sequential", "characterMap": {} }
            }
            """.utf8)
        }

        // v2 で足す予定のフィールドは今は拒否
        for field in ["roles", "layouts", "base"] {
            XCTAssertThrowsError(try KeymapStore.decode(from: json("\"\(field)\": {},")),
                                 "\(field) は拒否されるべき")
        }

        // $schema / _comment は許す
        XCTAssertNoThrow(try KeymapStore.decode(
            from: json("\"$schema\": \"./keymap-v1.schema.json\", \"_comment\": \"メモ\",")))

        // **この実装が読まない既知フィールドは拒否しない**（配列としては正しい）。
        // CodingKeys を許可リストに使うとここで落ちる — knownFields を使う理由。
        XCTAssertNoThrow(try KeymapStore.decode(
            from: json("\"addedAt\": \"2026-08-01\", \"bufferDisplayMap\": {\"h\": \"k\"},")))
    }

    /// JSON を JSONSerialization + sortedKeys で正規化した文字列（辞書キー順の差を吸収）
    private static func normalizedJSON(_ data: Data) throws -> String {
        let obj = try JSONSerialization.jsonObject(with: data)
        let normalized = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(decoding: normalized, as: UTF8.self)
    }
}
