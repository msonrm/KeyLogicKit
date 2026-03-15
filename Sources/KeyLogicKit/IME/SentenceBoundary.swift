import Foundation

/// 日本語テキストの文・句・カッコ境界を検出するユーティリティ
///
/// 文の区切り（。！？!?）、句の区切り（、,）、カッコペア（「」『』（）等）を
/// 認識し、カーソル位置に基づいた境界検出を提供する。
/// UIKit 非依存で、String + String.Index のみで動作する。
///
/// カッコ内外でスキャン範囲を切り替える設計:
/// - カッコ外: テキスト全体をスキャン。カッコ内の文末記号は無視（カッコをスキップ）
/// - カッコ内: カッコの内側をスキャン範囲とし、閉じカッコ直前が暗黙の文末
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

    // MARK: - カッコマッチングヘルパー

    /// 開きカッコ位置から対応する閉じカッコの位置を返す（ネスト対応）
    private static func findMatchingClose(in text: String, from openIdx: String.Index) -> String.Index? {
        let openChar = text[openIdx]
        guard let closeChar = openToClose[openChar] else { return nil }
        var depth = 0
        var idx = text.index(after: openIdx)
        while idx < text.endIndex {
            let c = text[idx]
            if c == openChar { depth += 1 }
            else if c == closeChar {
                if depth == 0 { return idx }
                depth -= 1
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    /// 閉じカッコ位置から対応する開きカッコの位置を返す（ネスト対応）
    private static func findMatchingOpen(in text: String, from closeIdx: String.Index) -> String.Index? {
        let closeChar = text[closeIdx]
        guard let openChar = closeToOpen[closeChar] else { return nil }
        var depth = 0
        var idx = closeIdx
        while idx > text.startIndex {
            let prev = text.index(before: idx)
            let c = text[prev]
            if c == closeChar { depth += 1 }
            else if c == openChar {
                if depth == 0 { return prev }
                depth -= 1
            }
            idx = prev
        }
        return nil
    }

    // MARK: - 文境界検出

    /// 指定位置を含む文の範囲を返す
    ///
    /// カッコ内外でスキャン範囲を自動判定する:
    /// - カッコ外: テキスト全体をスキャン。カッコ内の文末記号は無視
    /// - カッコ内: カッコの内側に限定。閉じカッコ直前が暗黙の文末
    /// - Parameters:
    ///   - text: 対象テキスト全体
    ///   - position: カーソル位置
    /// - Returns: 文の範囲（末尾の空白を含む）
    public static func sentenceRange(in text: String, at position: String.Index) -> Range<String.Index> {
        let scanRange: Range<String.Index>
        if let brackets = enclosingBrackets(in: text, at: position) {
            scanRange = brackets.inner
        } else {
            scanRange = text.startIndex..<text.endIndex
        }

        let start = sentenceStart(in: text, at: position, within: scanRange)
        let end = sentenceEnd(in: text, from: start, within: scanRange)
        return start..<end
    }

    /// 指定位置より前の文頭を返す（前の文の文頭へジャンプ用）
    ///
    /// position が文頭にある場合、さらに前の文の文頭を返す。
    public static func previousSentenceStart(in text: String, before position: String.Index) -> String.Index {
        guard position > text.startIndex else { return text.startIndex }

        // スキャン範囲を決定
        let scanRange: Range<String.Index>
        if let brackets = enclosingBrackets(in: text, at: position) {
            scanRange = brackets.inner
        } else {
            scanRange = text.startIndex..<text.endIndex
        }

        let currentStart = sentenceStart(in: text, at: position, within: scanRange)
        if currentStart < position {
            return currentStart
        }
        guard currentStart > scanRange.lowerBound else { return scanRange.lowerBound }
        let prevIdx = text.index(before: currentStart)
        return sentenceStart(in: text, at: prevIdx, within: scanRange)
    }

    /// 指定位置より後の文末を返す（次の文末へジャンプ用）
    ///
    /// position が文末にある場合、さらに次の文末を返す。
    public static func nextSentenceEnd(in text: String, after position: String.Index) -> String.Index {
        guard position < text.endIndex else { return text.endIndex }

        let scanRange: Range<String.Index>
        if let brackets = enclosingBrackets(in: text, at: position) {
            scanRange = brackets.inner
        } else {
            scanRange = text.startIndex..<text.endIndex
        }

        let currentEnd = sentenceEnd(in: text, from: position, within: scanRange)
        if currentEnd > position {
            return currentEnd
        }
        guard currentEnd < scanRange.upperBound else { return scanRange.upperBound }
        return sentenceEnd(in: text, from: currentEnd, within: scanRange)
    }

    /// 指定位置から前方の文頭を返す（スキャン範囲 + カッコスキップ）
    private static func sentenceStart(in text: String, at position: String.Index,
                                      within scanRange: Range<String.Index>) -> String.Index {
        guard position > scanRange.lowerBound else { return scanRange.lowerBound }

        var idx = position
        while idx > scanRange.lowerBound {
            let prev = text.index(before: idx)
            let c = text[prev]

            // 改行 → その直後が文頭
            if c == "\n" {
                return idx
            }

            // 閉じカッコ（bracketPairs に含まれるもの）→ 対応する開きカッコまでスキップ
            if closeToOpen[c] != nil {
                if let openIdx = findMatchingOpen(in: text, from: prev) {
                    // スキップ先がスキャン範囲外なら範囲の先頭を返す
                    if openIdx < scanRange.lowerBound { return scanRange.lowerBound }
                    idx = openIdx
                    continue
                }
            }

            // 文末記号 → 空白・閉じカッコをスキップした位置が文頭
            if sentenceEnders.contains(c) {
                let afterEnd = consumeTrailingAfterEnder(in: text, from: idx)
                if afterEnd <= position {
                    return afterEnd
                }
            }

            idx = prev
        }
        return scanRange.lowerBound
    }

    /// 指定位置から後方へスキャンして文末位置を返す（スキャン範囲 + カッコスキップ）
    private static func sentenceEnd(in text: String, from position: String.Index,
                                    within scanRange: Range<String.Index>) -> String.Index {
        var idx = position
        while idx < scanRange.upperBound {
            let c = text[idx]

            // 改行は文の区切り
            if c == "\n" {
                return text.index(after: idx)
            }

            // 開きカッコ → 対応する閉じカッコまでスキップ
            if openToClose[c] != nil {
                if let closeIdx = findMatchingClose(in: text, from: idx) {
                    // スキップ先がスキャン範囲外なら範囲の上限を返す
                    if closeIdx >= scanRange.upperBound { return scanRange.upperBound }
                    idx = text.index(after: closeIdx)
                    continue
                }
            }

            // 文末記号 → 後続の閉じカッコ・空白をスキップ
            if sentenceEnders.contains(c) {
                let consumed = consumeTrailingAfterEnder(in: text, from: text.index(after: idx))
                return min(consumed, scanRange.upperBound)
            }

            idx = text.index(after: idx)
        }
        // スキャン範囲の上限に到達 → 暗黙の文末（カッコ内では閉じカッコが文末）
        return scanRange.upperBound
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
