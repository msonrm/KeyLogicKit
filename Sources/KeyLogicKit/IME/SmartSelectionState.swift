import Foundation

/// スマート選択の拡大レベル
///
/// Shift+Option+→ で段階的に選択範囲を拡大し、
/// Shift+Option+← で逆方向に縮小する。
/// レベルが上がるほど選択範囲が広くなる。
public enum SmartSelectionLevel: Int, Comparable, Sendable {
    /// 選択なし（カーソルのみ）
    case none = 0
    /// カッコの内側
    case insideBrackets = 1
    /// カッコを含む
    case includingBrackets = 2
    /// 文全体（句点 。区切り）
    case sentence = 3
    /// ブロック（境界定義はアプリ側から注入）
    case block = 4

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// ブロック境界検出のクロージャ型
///
/// アプリ側が定義するブロック（シーン区切り、段落グループ等）の範囲を返す。
/// ブロック定義がない、または指定位置がブロック境界上にない場合は nil を返す。
/// - Parameters:
///   - text: 対象テキスト全体
///   - position: カーソル位置
/// - Returns: position を含むブロックの範囲。nil の場合 `.block` レベルはスキップされる
public typealias BlockRangeProvider = @Sendable (String, String.Index) -> Range<String.Index>?

/// スマート選択の状態を管理する
///
/// IMETextView が保持し、Shift+Option+→/← で段階的に
/// 選択範囲を拡大・縮小する。通常のキー操作でリセットされる。
public struct SmartSelectionState: Sendable {

    /// ブロック境界の検出関数（アプリ側から注入）
    public var blockRangeProvider: BlockRangeProvider?

    /// 現在の拡大レベル
    public private(set) var level: SmartSelectionLevel = .none

    /// スマート選択の起点（最初に拡大操作を行ったカーソル位置）
    public private(set) var origin: String.Index?

    /// 現在の選択範囲
    public private(set) var currentRange: Range<String.Index>?

    /// 各レベルの選択範囲履歴（縮小時に使用）
    private var rangeHistory: [SmartSelectionLevel: Range<String.Index>] = [:]

    public init(blockRangeProvider: BlockRangeProvider? = nil) {
        self.blockRangeProvider = blockRangeProvider
    }

    /// 選択範囲を次のレベルに拡大する
    ///
    /// 該当するレベルの範囲が現在の範囲と同じ、または現在の範囲に包含される場合は
    /// スキップして次のレベルを試す。
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
        while let tryLevel = nextLevel, tryLevel <= .block {
            if let range = rangeForLevel(tryLevel, in: text, origin: originIdx) {
                // 現在の選択範囲と同じ、または現在の範囲に包含される場合はスキップ
                if let current = currentRange,
                   range.lowerBound >= current.lowerBound && range.upperBound <= current.upperBound {
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
        while let tryLevel = prevLevel, tryLevel >= .insideBrackets {
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
            // origin がカッコ内にある場合、カッコの開始位置で外側コンテキストの文を検索する。
            // カッコが文中に埋め込まれている場合（前後が文末でない場合）は、
            // カッコを含む文全体が返される。
            // カッコが独立した文の場合は includingBrackets と同じ範囲になり、
            // expand() のスキップ判定で自動的にスキップされる。
            if let brackets = SentenceBoundary.enclosingBrackets(in: text, at: origin) {
                return SentenceBoundary.sentenceRange(in: text, at: brackets.outer.lowerBound)
            }
            return SentenceBoundary.sentenceRange(in: text, at: origin)

        case .block:
            return blockRangeProvider?(text, origin)
        }
    }
}
