import XCTest
import KeyLogicKit

/// InputManager の逐次入力バッファ（カスタムテーブルの greedy longest-match）のユニットテスト
///
/// `handleSequentialInput` で 1 文字ずつ投入し、`drainSequentialBuffer` の解決結果を
/// `rawKanaText`（composingText の生かな）で観測する。月配列など inputMappings を持つ
/// 逐次入力方式のコア。プレフィクス待機・最長一致・バックトラックを検証する。
@MainActor
final class InputManagerSequentialTests: XCTestCase {

    /// InputManager は辞書ロードが重いのでプロセス内で共有する
    private static var shared: InputManager?
    private func manager() -> InputManager {
        if let m = Self.shared { return m }
        let m = InputManager()
        Self.shared = m
        return m
    }

    /// 最小テーブル。prefixSet = {"k", "ky"}（各キーの長さ1〜len-1 の真プレフィクス）。
    /// "k" 自体もマッピングを持つ（バックトラック検証用）。
    private static let mappings: [String: String] = [
        "a": "あ",
        "k": "く",
        "ka": "か",
        "ki": "き",
        "kk": "っ",     // 促音
        "kya": "きゃ",  // 拗音（最長一致）
        "n": "ん",
    ]

    /// キーマップを設定し、input を 1 文字ずつ handleSequentialInput して rawKanaText を返す
    private func typeSequence(_ input: String) -> String {
        let m = manager()
        _ = m.cancelConversion()  // ケース間のクリーン
        let def = KeymapDefinition(
            name: "test-seq",
            behavior: .sequential(characterMap: [:]),
            keyboardLayout: "us",
            inputMappings: Self.mappings
        )
        m.updateKeymap(ExpandedKeymap(definition: def))
        for ch in input {
            m.handleSequentialInput(String(ch))
        }
        return m.rawKanaText
    }

    func testSimpleMatch() {
        // "a" は他のキーのプレフィクスでないため即解決
        XCTAssertEqual(typeSequence("a"), "あ")
    }

    func testWaitsForPrefixThenResolves() {
        // "k" はマッピングを持つがプレフィクスでもあるため待機し、"a" で "か" に解決
        XCTAssertEqual(typeSequence("ka"), "か")
    }

    func testLongestMatchYoon() {
        // "kya" は "ki"+"ya" ではなく最長一致で "きゃ"
        XCTAssertEqual(typeSequence("kya"), "きゃ")
    }

    func testGeminateConsonant() {
        // "kk" → 促音 "っ"
        XCTAssertEqual(typeSequence("kk"), "っ")
    }

    func testBacktrackOnNonContinuation() {
        // "k" はプレフィクスで待機するが次の "n" で継続不能 →
        // "k" を "く" にバックトラック解決し、残りの "n" を "ん" に解決
        XCTAssertEqual(typeSequence("kn"), "くん")
    }

    func testMultipleResolutions() {
        // "kaki" → "ka"→か 解決後に "ki"→き
        XCTAssertEqual(typeSequence("kaki"), "かき")
    }
}
