import XCTest
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
}
