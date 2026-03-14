import Foundation

/// スマート選択の拡大レベル
///
/// Shift+Option+→ で段階的に選択範囲を拡大し、
/// Shift+Option+← で逆方向に縮小する。
/// レベルが上がるほど選択範囲が広くなる。
public enum SmartSelectionLevel: Int, Comparable, Sendable {
    /// 選択なし（カーソルのみ）
    case none = 0
    /// 句（読点 、区切り）
    case clause = 1
    /// カッコの内側
    case insideBrackets = 2
    /// カッコを含む
    case includingBrackets = 3
    /// 文全体（句点 。区切り）
    case sentence = 4

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// スマート選択の状態を管理する
///
/// IMETextView が保持し、Shift+Option+→/← で段階的に
/// 選択範囲を拡大・縮小する。通常のキー操作でリセットされる。
///
/// 拡大時、片側がカッコに当たった場合はそちら側を固定して
/// もう片方だけを拡大する。
public struct SmartSelectionState: Sendable {

    /// 現在の拡大レベル
    public private(set) var level: SmartSelectionLevel = .none

    /// スマート選択の起点（最初に拡大操作を行ったカーソル位置）
    public private(set) var origin: String.Index?

    /// 現在の選択範囲
    public private(set) var currentRange: Range<String.Index>?

    /// 各レベルの選択範囲履歴（縮小時に使用）
    private var rangeHistory: [SmartSelectionLevel: Range<String.Index>] = [:]

    public init() {}

    /// 選択範囲を次のレベルに拡大する
    ///
    /// 該当するレベルの範囲が現在の範囲と同じ場合はスキップして
    /// 次のレベルを試す。
    /// - Parameters:
    ///   - text: 対象テキスト全体
    ///   - cursor: 現在のカーソル位置（初回拡大時の起点）
    /// - Returns: 新しい選択範囲。これ以上拡大できない場合は nil
    public mutating func expand(in text: String, cursor: String.Index) -> Range<String.Index>? {
        // 初回: 起点を記録
        if level == .none {
            origin = cursor
        }

        guard let originIdx = origin else { return nil }

        // 次のレベルを順に試す
        var nextLevel = SmartSelectionLevel(rawValue: level.rawValue + 1)
        while let tryLevel = nextLevel, tryLevel <= .sentence {
            if let range = rangeForLevel(tryLevel, in: text, origin: originIdx) {
                // 現在の選択範囲と同じならスキップ
                if let current = currentRange, range == current {
                    nextLevel = SmartSelectionLevel(rawValue: tryLevel.rawValue + 1)
                    continue
                }
                level = tryLevel
                currentRange = range
                rangeHistory[tryLevel] = range
                return range
            }
            nextLevel = SmartSelectionLevel(rawValue: tryLevel.rawValue + 1)
        }

        return nil
    }

    /// 選択範囲を前のレベルに縮小する
    ///
    /// - Parameter text: 対象テキスト全体
    /// - Returns: 新しい選択範囲。none に戻った場合は nil（カーソル位置に戻る）
    public mutating func shrink(in text: String) -> Range<String.Index>? {
        guard level > .none else { return nil }

        // 前のレベルを探す
        var prevLevel = SmartSelectionLevel(rawValue: level.rawValue - 1)
        while let tryLevel = prevLevel, tryLevel >= .clause {
            if let range = rangeHistory[tryLevel] {
                level = tryLevel
                currentRange = range
                return range
            }
            prevLevel = SmartSelectionLevel(rawValue: tryLevel.rawValue - 1)
        }

        // 全レベルをスキップした — none に戻る
        level = .none
        currentRange = nil
        return nil
    }

    /// 状態をリセットする
    public mutating func reset() {
        level = .none
        origin = nil
        currentRange = nil
        rangeHistory = [:]
    }

    // MARK: - Private

    /// 指定レベルの選択範囲を計算する
    private func rangeForLevel(_ level: SmartSelectionLevel, in text: String,
                               origin: String.Index) -> Range<String.Index>? {
        switch level {
        case .none:
            return nil

        case .clause:
            let sentence = SentenceBoundary.sentenceRange(in: text, at: origin)
            let clause = SentenceBoundary.clauseRange(in: text, at: origin, within: sentence)
            return clause

        case .insideBrackets:
            guard let brackets = SentenceBoundary.enclosingBrackets(in: text, at: origin) else {
                return nil
            }
            return brackets.inner

        case .includingBrackets:
            guard let brackets = SentenceBoundary.enclosingBrackets(in: text, at: origin) else {
                return nil
            }
            return brackets.outer

        case .sentence:
            return SentenceBoundary.sentenceRange(in: text, at: origin)
        }
    }
}
