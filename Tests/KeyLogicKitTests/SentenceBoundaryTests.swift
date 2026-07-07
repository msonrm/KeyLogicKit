import XCTest
import KeyLogicKit

/// SentenceBoundary の文・句・カッコ境界検出のユニットテスト
///
/// 文字インデックスベースで方向非依存（縦書き対応でも無変更）の純ロジック。
/// 期待値は各メソッドのスキャン仕様に基づく:
/// - カッコ外はテキスト全体をスキャンし、カッコ内の文末記号は無視（カッコをスキップ）
/// - カッコ内はカッコの内側にスキャン範囲を限定（閉じカッコ直前が暗黙の文末）
/// - 連続する文末記号（！？ / !?）は一つの文末として扱う
final class SentenceBoundaryTests: XCTestCase {

    // MARK: - ヘルパー

    /// offset から String.Index
    private func idx(_ s: String, _ offset: Int) -> String.Index {
        s.index(s.startIndex, offsetBy: offset)
    }

    /// Range<String.Index> を部分文字列に
    private func slice(_ s: String, _ r: Range<String.Index>) -> String {
        String(s[r])
    }

    /// String.Index の offset
    private func off(_ s: String, _ i: String.Index) -> Int {
        s.distance(from: s.startIndex, to: i)
    }

    // MARK: - sentenceRange

    func testSentenceRangeBasic() {
        let text = "こんにちは。さようなら。"
        // 先頭の文
        XCTAssertEqual(slice(text, SentenceBoundary.sentenceRange(in: text, at: idx(text, 0))),
                       "こんにちは。")
        // 2文目（「さ」= offset 6）
        XCTAssertEqual(slice(text, SentenceBoundary.sentenceRange(in: text, at: idx(text, 6))),
                       "さようなら。")
    }

    func testSentenceRangeConsecutiveEnders() {
        // 連続する文末記号（！？）は一つの文末として扱う
        let text = "ええ！？そう。"
        XCTAssertEqual(slice(text, SentenceBoundary.sentenceRange(in: text, at: idx(text, 0))),
                       "ええ！？")
    }

    func testSentenceRangeSkipsInsideBrackets() {
        // カッコ外の位置: カッコ内の「。」は文末とみなさず、カッコ外の文末までが1文
        let text = "彼は「そう。」と言った。"
        // 「言」= offset 8 はカッコ外
        XCTAssertEqual(slice(text, SentenceBoundary.sentenceRange(in: text, at: idx(text, 8))),
                       "彼は「そう。」と言った。")
    }

    func testSentenceRangeInsideBrackets() {
        // カッコ内の位置: スキャン範囲がカッコの内側に限定される
        let text = "彼は「そう。」と言った。"
        // 「そ」= offset 3 はカッコ内
        XCTAssertEqual(slice(text, SentenceBoundary.sentenceRange(in: text, at: idx(text, 3))),
                       "そう。")
    }

    // MARK: - previousSentenceStart / nextSentenceEnd

    func testPreviousSentenceStart() {
        let text = "あ。い。う。"  // あ0 。1 い2 。3 う4 。5
        // 「う」= offset 4 は文頭。既に文頭なので前の文「い。」の頭=offset 2
        XCTAssertEqual(off(text, SentenceBoundary.previousSentenceStart(in: text, before: idx(text, 4))), 2)
        // 「い」= offset 2 も文頭 → さらに前の文「あ。」の頭=offset 0
        XCTAssertEqual(off(text, SentenceBoundary.previousSentenceStart(in: text, before: idx(text, 2))), 0)
    }

    func testNextSentenceEnd() {
        let text = "あ。い。う。"
        // 「い」= offset 2 の次の文末=「い。」の直後=offset 4
        XCTAssertEqual(off(text, SentenceBoundary.nextSentenceEnd(in: text, after: idx(text, 2))), 4)
        // 「う」= offset 4 の次の文末=末尾=offset 6
        XCTAssertEqual(off(text, SentenceBoundary.nextSentenceEnd(in: text, after: idx(text, 4))), 6)
    }

    // MARK: - clauseRange

    func testClauseRange() {
        let text = "あ、い、う。"  // あ0 、1 い2 、3 う4 。5
        let sentence = SentenceBoundary.sentenceRange(in: text, at: idx(text, 2))
        // 「い」= offset 2 を含む句は「い、」（末尾の読点を含む）
        XCTAssertEqual(slice(text, SentenceBoundary.clauseRange(in: text, at: idx(text, 2), within: sentence)),
                       "い、")
    }

    // MARK: - enclosingBrackets

    func testEnclosingBracketsNested() {
        let text = "（あ（い）う）"  // （0 あ1 （2 い3 ）4 う5 ）6
        // 「い」= offset 3 を囲む最も内側のカッコは内側の（）
        guard let brackets = SentenceBoundary.enclosingBrackets(in: text, at: idx(text, 3)) else {
            XCTFail("カッコ内と判定されるべき")
            return
        }
        XCTAssertEqual(slice(text, brackets.inner), "い")
        XCTAssertEqual(slice(text, brackets.outer), "（い）")
    }

    func testEnclosingBracketsOutside() {
        let text = "ふつうの文。"
        XCTAssertNil(SentenceBoundary.enclosingBrackets(in: text, at: idx(text, 2)))
    }
}
