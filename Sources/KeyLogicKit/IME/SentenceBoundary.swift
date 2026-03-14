import Foundation

/// 日本語テキストの文・句・カッコ境界を検出するユーティリティ
///
/// 文の区切り（。！？!?）、句の区切り（、,）、カッコペア（「」『』（）等）を
/// 認識し、カーソル位置に基づいた境界検出を提供する。
/// UIKit 非依存で、String + String.Index のみで動作する。
public enum SentenceBoundary {

    // MARK: - 定数

    /// 文末記号
    public static let sentenceEnders: Set<Character> = ["。", "！", "？", "!", "?"]

    /// 文末記号の後に続きうる閉じカッコ
    public static let closingBrackets: Set<Character> = [
        // 日本語
        "」", "』", "）", "】", "〉", "》",
        // ASCII
        ")", "]", "}", ">", "\"", "'",
    ]

    /// 句区切り（読点）
    public static let clauseDelimiters: Set<Character> = ["、", ","]

    /// カッコペア（開き → 閉じ）
    public static let bracketPairs: [(open: Character, close: Character)] = [
        ("「", "」"), ("『", "』"), ("（", "）"),
        ("【", "】"), ("〈", "〉"), ("《", "》"),
        ("(", ")"), ("[", "]"), ("{", "}"), ("<", ">"),
        ("\u{201C}", "\u{201D}"),  // ""
        ("\u{2018}", "\u{2019}"),  // ''
    ]

    /// 開きカッコ → 閉じカッコの辞書
    private static let openToClose: [Character: Character] = {
        var dict: [Character: Character] = [:]
        for pair in bracketPairs {
            dict[pair.open] = pair.close
        }
        return dict
    }()

    /// 閉じカッコ → 開きカッコの辞書
    private static let closeToOpen: [Character: Character] = {
        var dict: [Character: Character] = [:]
        for pair in bracketPairs {
            dict[pair.close] = pair.open
        }
        return dict
    }()

    // MARK: - 文境界検出

    /// 指定位置を含む文の範囲を返す
    ///
    /// 文末は `。！？!?` + 後続の閉じカッコ + 後続の空白で定義される。
    /// 文頭は文末の直後、テキスト先頭、または改行の直後。
    /// - Parameters:
    ///   - text: 対象テキスト全体
    ///   - position: カーソル位置
    /// - Returns: 文の範囲（末尾の空白を含む）
    public static func sentenceRange(in text: String, at position: String.Index) -> Range<String.Index> {
        let start = sentenceStart(in: text, at: position)
        let end = sentenceEnd(in: text, from: position)
        return start..<end
    }

    /// 指定位置から前方の文頭を返す（現在の文の文頭）
    ///
    /// position がちょうど文頭にある場合はその位置を返す。
    public static func sentenceStart(in text: String, at position: String.Index) -> String.Index {
        guard position > text.startIndex else { return text.startIndex }

        var idx = position
        // position が文の先頭にいる可能性を考慮して1文字戻ってからスキャン
        while idx > text.startIndex {
            let prev = text.index(before: idx)
            let c = text[prev]

            // 改行を見つけたら、その直後が文頭
            if c == "\n" {
                return idx
            }
            // 文末記号を見つけたら、空白・閉じカッコをスキップした直後が次の文頭
            if sentenceEnders.contains(c) {
                // この位置は前の文の文末記号の直後
                // position がこの文末の空白部分にいる場合も考慮
                let afterEnd = consumeTrailingAfterEnder(in: text, from: idx)
                if afterEnd <= position {
                    return afterEnd
                }
                // position が文末記号の直後の空白の中にいた場合、前の文の文頭を探す
                return idx
            }
            // 閉じカッコの後の文末記号もチェック
            if closingBrackets.contains(c) {
                // 閉じカッコの前に文末記号があるかチェック
                if let enderIdx = findEnderBeforeClosingBrackets(in: text, before: idx) {
                    let afterEnd = consumeTrailingAfterEnder(in: text, from: text.index(after: enderIdx))
                    if afterEnd <= position {
                        return afterEnd
                    }
                }
            }
            idx = prev
        }
        return text.startIndex
    }

    /// 指定位置より前の文頭を返す（前の文の文頭へジャンプ用）
    ///
    /// position が文頭にある場合、さらに前の文の文頭を返す。
    public static func previousSentenceStart(in text: String, before position: String.Index) -> String.Index {
        guard position > text.startIndex else { return text.startIndex }

        // まず現在の文頭を見つける
        let currentStart = sentenceStart(in: text, at: position)

        // 現在位置が文頭でなければ、現在の文頭を返す
        if currentStart < position {
            return currentStart
        }

        // 現在位置が文頭なので、1文字前に移動して前の文の文頭を探す
        guard currentStart > text.startIndex else { return text.startIndex }
        let prevIdx = text.index(before: currentStart)
        return sentenceStart(in: text, at: prevIdx)
    }

    /// 指定位置より後の文末を返す（次の文末へジャンプ用）
    ///
    /// position が文末にある場合、さらに次の文末を返す。
    public static func nextSentenceEnd(in text: String, after position: String.Index) -> String.Index {
        guard position < text.endIndex else { return text.endIndex }

        // まず現在の文末を見つける
        let currentEnd = sentenceEnd(in: text, from: position)

        // 現在位置が文末でなければ、現在の文末を返す
        if currentEnd > position {
            return currentEnd
        }

        // 現在位置が文末なので、次の文末を探す
        guard currentEnd < text.endIndex else { return text.endIndex }
        return sentenceEnd(in: text, from: currentEnd)
    }

    /// 指定位置から後方へスキャンして文末位置を返す（空白含む）
    private static func sentenceEnd(in text: String, from position: String.Index) -> String.Index {
        var idx = position
        while idx < text.endIndex {
            let c = text[idx]
            // 改行は文の区切り
            if c == "\n" {
                return text.index(after: idx)
            }
            if sentenceEnders.contains(c) {
                // 文末記号の後の閉じカッコと空白をスキップ
                return consumeTrailingAfterEnder(in: text, from: text.index(after: idx))
            }
            idx = text.index(after: idx)
        }
        return text.endIndex
    }

    /// 文末記号の直後から、連続文末記号・閉じカッコ・空白をスキップした位置を返す
    ///
    /// `！？` や `!?` のように連続する文末記号は一つの文末として扱う。
    private static func consumeTrailingAfterEnder(in text: String, from start: String.Index) -> String.Index {
        var idx = start
        // 連続する文末記号をスキップ（！？、!? 等）
        while idx < text.endIndex && sentenceEnders.contains(text[idx]) {
            idx = text.index(after: idx)
        }
        // 閉じカッコをスキップ
        while idx < text.endIndex && closingBrackets.contains(text[idx]) {
            idx = text.index(after: idx)
        }
        // 空白をスキップ（改行は含めない — 改行は次の文の区切りとして扱う）
        while idx < text.endIndex && text[idx].isWhitespace && text[idx] != "\n" {
            idx = text.index(after: idx)
        }
        return idx
    }

    /// 指定位置の前方にある閉じカッコ列の前に文末記号があるか探す
    private static func findEnderBeforeClosingBrackets(in text: String, before position: String.Index) -> String.Index? {
        var idx = position
        while idx > text.startIndex {
            let prev = text.index(before: idx)
            let c = text[prev]
            if sentenceEnders.contains(c) {
                return prev
            }
            if !closingBrackets.contains(c) {
                return nil
            }
            idx = prev
        }
        return nil
    }

    // MARK: - 句境界検出

    /// 指定位置を含む句（、区切り）の範囲を返す
    ///
    /// 句は文内で読点（、,）で区切られた単位。
    /// - Parameters:
    ///   - text: 対象テキスト全体
    ///   - position: カーソル位置
    ///   - sentence: 句を検索する文の範囲
    /// - Returns: 句の範囲
    public static func clauseRange(in text: String, at position: String.Index,
                                   within sentence: Range<String.Index>) -> Range<String.Index> {
        // 句の開始を探す: position から前方にスキャン
        var clauseStart = sentence.lowerBound
        var idx = position
        while idx > sentence.lowerBound {
            let prev = text.index(before: idx)
            if clauseDelimiters.contains(text[prev]) {
                clauseStart = idx
                break
            }
            idx = prev
        }

        // 句の終了を探す: position から後方にスキャン
        var clauseEnd = sentence.upperBound
        idx = position
        while idx < sentence.upperBound {
            if clauseDelimiters.contains(text[idx]) {
                clauseEnd = text.index(after: idx)
                break
            }
            idx = text.index(after: idx)
        }

        return clauseStart..<clauseEnd
    }

    // MARK: - カッコ境界検出

    /// 指定位置を囲む最も内側のカッコペアの範囲を返す
    ///
    /// - Parameters:
    ///   - text: 対象テキスト全体
    ///   - position: カーソル位置
    /// - Returns: (inner: カッコの中身, outer: カッコを含む範囲)。カッコ内にない場合は nil
    public static func enclosingBrackets(in text: String, at position: String.Index)
        -> (inner: Range<String.Index>, outer: Range<String.Index>)? {
        // 各カッコペアについて、position を囲む最も内側のペアを探す
        var bestInner: Range<String.Index>?
        var bestOuter: Range<String.Index>?

        for pair in bracketPairs {
            if let result = findEnclosingPair(in: text, at: position,
                                              open: pair.open, close: pair.close) {
                // 最も狭い（最内側の）ペアを選ぶ
                if let currentBest = bestInner {
                    if result.inner.lowerBound >= currentBest.lowerBound
                        && result.inner.upperBound <= currentBest.upperBound {
                        bestInner = result.inner
                        bestOuter = result.outer
                    }
                } else {
                    bestInner = result.inner
                    bestOuter = result.outer
                }
            }
        }

        guard let inner = bestInner, let outer = bestOuter else { return nil }
        return (inner: inner, outer: outer)
    }

    /// 特定のカッコペアで position を囲む範囲を探す
    private static func findEnclosingPair(in text: String, at position: String.Index,
                                          open: Character, close: Character)
        -> (inner: Range<String.Index>, outer: Range<String.Index>)? {
        // 後方スキャン: position から前方に開きカッコを探す（ネストを考慮）
        var depth = 0
        var openIdx: String.Index?
        var idx = position

        while idx > text.startIndex {
            let prev = text.index(before: idx)
            let c = text[prev]
            if c == close {
                depth += 1
            } else if c == open {
                if depth == 0 {
                    openIdx = prev
                    break
                }
                depth -= 1
            }
            idx = prev
        }

        guard let foundOpen = openIdx else { return nil }

        // 前方スキャン: position から後方に閉じカッコを探す（ネストを考慮）
        depth = 0
        idx = position
        while idx < text.endIndex {
            let c = text[idx]
            if c == open {
                depth += 1
            } else if c == close {
                if depth == 0 {
                    let innerStart = text.index(after: foundOpen)
                    let innerEnd = idx
                    let outerStart = foundOpen
                    let outerEnd = text.index(after: idx)
                    return (inner: innerStart..<innerEnd, outer: outerStart..<outerEnd)
                }
                depth -= 1
            }
            idx = text.index(after: idx)
        }

        return nil
    }
}
