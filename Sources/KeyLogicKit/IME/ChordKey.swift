import Foundation

/// 同時打鍵方式の物理キー識別子
///
/// QWERTY 配列の 30 キー + 親指キー 3 つ（計 33 キー）。
/// 各キーは `1 << rawValue` のビットマスク（UInt64）で同時打鍵判定に使用する。
///
/// 薙刀式は `space`（センターシフト）、NICOLA は `leftThumb`/`rightThumb` を使用する。
public enum ChordKey: UInt32, CaseIterable, Hashable, Sendable {
    // 上段
    case Q = 0, W, E, R, T
    case Y, U, I, O, P
    // 中段
    case A, S, D, F, G
    case H, J, K, L, semicolon
    // 下段
    case Z, X, C, V, B
    case N, M, comma, dot, slash
    // 親指キー
    case space       // センターシフト（Space）— 薙刀式
    case leftThumb   // 左親指（無変換 / International5）— NICOLA
    case rightThumb  // 右親指（変換 / International4）— NICOLA

    /// ビットマスク値（同時打鍵判定に使用）
    public var bit: UInt64 { 1 << UInt64(rawValue) }

    // MARK: - 打鍵統計用属性

    /// 担当する手
    public enum Hand: Sendable { case left, right, thumb }

    /// 担当する指
    public enum Finger: String, CaseIterable, Sendable {
        case leftPinky = "左小"
        case leftRing = "左薬"
        case leftMiddle = "左中"
        case leftIndex = "左人"
        case rightIndex = "右人"
        case rightMiddle = "右中"
        case rightRing = "右薬"
        case rightPinky = "右小"
        case thumb = "親指"
    }

    /// キーボード上の段
    public enum Row: String, CaseIterable, Sendable {
        case upper = "上段"
        case home = "中段"
        case lower = "下段"
        case thumb = "親指"
    }

    /// このキーを担当する手
    public var hand: Hand {
        switch self {
        case .Q, .W, .E, .R, .T,
             .A, .S, .D, .F, .G,
             .Z, .X, .C, .V, .B:
            return .left
        case .Y, .U, .I, .O, .P,
             .H, .J, .K, .L, .semicolon,
             .N, .M, .comma, .dot, .slash:
            return .right
        case .space, .leftThumb, .rightThumb:
            return .thumb
        }
    }

    /// このキーを担当する指（US 配列標準運指）
    public var finger: Finger {
        switch self {
        case .Q, .A, .Z: return .leftPinky
        case .W, .S, .X: return .leftRing
        case .E, .D, .C: return .leftMiddle
        case .R, .T, .F, .G, .V, .B: return .leftIndex
        case .Y, .U, .H, .J, .N, .M: return .rightIndex
        case .I, .K, .comma: return .rightMiddle
        case .O, .L, .dot: return .rightRing
        case .P, .semicolon, .slash: return .rightPinky
        case .space, .leftThumb, .rightThumb: return .thumb
        }
    }

    /// このキーの段（打鍵統計用）
    public var keyRow: Row {
        switch self {
        case .Q, .W, .E, .R, .T,
             .Y, .U, .I, .O, .P:
            return .upper
        case .A, .S, .D, .F, .G,
             .H, .J, .K, .L, .semicolon:
            return .home
        case .Z, .X, .C, .V, .B,
             .N, .M, .comma, .dot, .slash:
            return .lower
        case .space, .leftThumb, .rightThumb:
            return .thumb
        }
    }

    // MARK: - QWERTY 行定義

    /// 上段キー（Q-P）
    public static let topRow: [ChordKey] = [.Q, .W, .E, .R, .T, .Y, .U, .I, .O, .P]
    /// 中段キー（A-;）
    public static let middleRow: [ChordKey] = [.A, .S, .D, .F, .G, .H, .J, .K, .L, .semicolon]
    /// 下段キー（Z-/）
    public static let bottomRow: [ChordKey] = [.Z, .X, .C, .V, .B, .N, .M, .comma, .dot, .slash]

    // MARK: - 文字 → ChordKey マッピング

    /// 文字 → ChordKey の逆引きテーブル
    public static let fromCharacter: [Character: ChordKey] = [
        "q": .Q, "w": .W, "e": .E, "r": .R, "t": .T,
        "y": .Y, "u": .U, "i": .I, "o": .O, "p": .P,
        "a": .A, "s": .S, "d": .D, "f": .F, "g": .G,
        "h": .H, "j": .J, "k": .K, "l": .L, ";": .semicolon,
        "z": .Z, "x": .X, "c": .C, "v": .V, "b": .B,
        "n": .N, "m": .M, ",": .comma, ".": .dot, "/": .slash,
        " ": .space,
    ]
}
