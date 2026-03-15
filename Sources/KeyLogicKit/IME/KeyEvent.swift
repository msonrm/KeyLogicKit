import Foundation

/// プラットフォーム非依存のキーイベント表現
///
/// UIKey (iPadOS) や NSEvent (macOS) から変換して使用する。
/// KeyRouter はこの型のみに依存し、UIKit の型を直接参照しない。
public struct KeyEvent: Sendable {
    /// HID キーコード
    public let keyCode: HIDKeyCode
    /// 入力文字列（UIKey.characters に相当）
    public let characters: String
    /// 修飾キーフラグ
    public let modifierFlags: KeyModifierFlags

    public init(keyCode: HIDKeyCode, characters: String, modifierFlags: KeyModifierFlags) {
        self.keyCode = keyCode
        self.characters = characters
        self.modifierFlags = modifierFlags
    }
}

// MARK: - HIDKeyCode

/// HID Usage コード（UIKeyboardHIDUsage のプラットフォーム非依存な代替）
///
/// raw values は USB HID Usage Tables に準拠し、UIKeyboardHIDUsage と同一。
/// struct + RawRepresentable で未知のキーコードも受け入れ可能。
public struct HIDKeyCode: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // MARK: アルファベットキー

    public static let keyboardA = HIDKeyCode(rawValue: 0x04)
    public static let keyboardB = HIDKeyCode(rawValue: 0x05)
    public static let keyboardC = HIDKeyCode(rawValue: 0x06)
    public static let keyboardD = HIDKeyCode(rawValue: 0x07)
    public static let keyboardE = HIDKeyCode(rawValue: 0x08)
    public static let keyboardF = HIDKeyCode(rawValue: 0x09)
    public static let keyboardG = HIDKeyCode(rawValue: 0x0A)
    public static let keyboardH = HIDKeyCode(rawValue: 0x0B)
    public static let keyboardI = HIDKeyCode(rawValue: 0x0C)
    public static let keyboardJ = HIDKeyCode(rawValue: 0x0D)
    public static let keyboardK = HIDKeyCode(rawValue: 0x0E)
    public static let keyboardL = HIDKeyCode(rawValue: 0x0F)
    public static let keyboardM = HIDKeyCode(rawValue: 0x10)
    public static let keyboardN = HIDKeyCode(rawValue: 0x11)
    public static let keyboardO = HIDKeyCode(rawValue: 0x12)
    public static let keyboardP = HIDKeyCode(rawValue: 0x13)
    public static let keyboardQ = HIDKeyCode(rawValue: 0x14)
    public static let keyboardR = HIDKeyCode(rawValue: 0x15)
    public static let keyboardS = HIDKeyCode(rawValue: 0x16)
    public static let keyboardT = HIDKeyCode(rawValue: 0x17)
    public static let keyboardU = HIDKeyCode(rawValue: 0x18)
    public static let keyboardV = HIDKeyCode(rawValue: 0x19)
    public static let keyboardW = HIDKeyCode(rawValue: 0x1A)
    public static let keyboardX = HIDKeyCode(rawValue: 0x1B)
    public static let keyboardY = HIDKeyCode(rawValue: 0x1C)
    public static let keyboardZ = HIDKeyCode(rawValue: 0x1D)

    // MARK: 数字キー

    public static let keyboard1 = HIDKeyCode(rawValue: 0x1E)
    public static let keyboard2 = HIDKeyCode(rawValue: 0x1F)
    public static let keyboard3 = HIDKeyCode(rawValue: 0x20)
    public static let keyboard4 = HIDKeyCode(rawValue: 0x21)
    public static let keyboard5 = HIDKeyCode(rawValue: 0x22)
    public static let keyboard6 = HIDKeyCode(rawValue: 0x23)
    public static let keyboard7 = HIDKeyCode(rawValue: 0x24)
    public static let keyboard8 = HIDKeyCode(rawValue: 0x25)
    public static let keyboard9 = HIDKeyCode(rawValue: 0x26)
    public static let keyboard0 = HIDKeyCode(rawValue: 0x27)

    // MARK: 制御キー

    public static let keyboardReturnOrEnter = HIDKeyCode(rawValue: 0x28)
    public static let keyboardEscape = HIDKeyCode(rawValue: 0x29)
    public static let keyboardDeleteOrBackspace = HIDKeyCode(rawValue: 0x2A)
    public static let keyboardTab = HIDKeyCode(rawValue: 0x2B)
    public static let keyboardSpacebar = HIDKeyCode(rawValue: 0x2C)

    // MARK: 記号キー

    public static let keyboardHyphen = HIDKeyCode(rawValue: 0x2D)
    public static let keyboardEqualSign = HIDKeyCode(rawValue: 0x2E)
    public static let keyboardOpenBracket = HIDKeyCode(rawValue: 0x2F)
    public static let keyboardCloseBracket = HIDKeyCode(rawValue: 0x30)
    public static let keyboardBackslash = HIDKeyCode(rawValue: 0x31)
    // 0x32: Non-US # and ~
    public static let keyboardSemicolon = HIDKeyCode(rawValue: 0x33)
    public static let keyboardQuote = HIDKeyCode(rawValue: 0x34)
    public static let keyboardGraveAccentAndTilde = HIDKeyCode(rawValue: 0x35)
    public static let keyboardComma = HIDKeyCode(rawValue: 0x36)
    public static let keyboardPeriod = HIDKeyCode(rawValue: 0x37)
    public static let keyboardSlash = HIDKeyCode(rawValue: 0x38)
    public static let keyboardCapsLock = HIDKeyCode(rawValue: 0x39)

    // MARK: ファンクションキー

    public static let keyboardF1 = HIDKeyCode(rawValue: 0x3A)
    public static let keyboardF2 = HIDKeyCode(rawValue: 0x3B)
    public static let keyboardF3 = HIDKeyCode(rawValue: 0x3C)
    public static let keyboardF4 = HIDKeyCode(rawValue: 0x3D)
    public static let keyboardF5 = HIDKeyCode(rawValue: 0x3E)
    public static let keyboardF6 = HIDKeyCode(rawValue: 0x3F)
    public static let keyboardF7 = HIDKeyCode(rawValue: 0x40)
    public static let keyboardF8 = HIDKeyCode(rawValue: 0x41)
    public static let keyboardF9 = HIDKeyCode(rawValue: 0x42)
    public static let keyboardF10 = HIDKeyCode(rawValue: 0x43)
    public static let keyboardF11 = HIDKeyCode(rawValue: 0x44)
    public static let keyboardF12 = HIDKeyCode(rawValue: 0x45)

    // MARK: ナビゲーションキー

    public static let keyboardRightArrow = HIDKeyCode(rawValue: 0x4F)
    public static let keyboardLeftArrow = HIDKeyCode(rawValue: 0x50)
    public static let keyboardDownArrow = HIDKeyCode(rawValue: 0x51)
    public static let keyboardUpArrow = HIDKeyCode(rawValue: 0x52)
    public static let keyboardDeleteForward = HIDKeyCode(rawValue: 0x4C)
    public static let keyboardHome = HIDKeyCode(rawValue: 0x4A)
    public static let keyboardEnd = HIDKeyCode(rawValue: 0x4D)
    public static let keyboardPageUp = HIDKeyCode(rawValue: 0x4B)
    public static let keyboardPageDown = HIDKeyCode(rawValue: 0x4E)

    // MARK: JIS 固有キー

    public static let keyboardInternational1 = HIDKeyCode(rawValue: 0x87) // ¥/_ (JIS)
    public static let keyboardInternational2 = HIDKeyCode(rawValue: 0x88) // ひらがな/カタカナ
    public static let keyboardInternational3 = HIDKeyCode(rawValue: 0x89) // ¥
    public static let keyboardInternational4 = HIDKeyCode(rawValue: 0x8A) // 変換
    public static let keyboardInternational5 = HIDKeyCode(rawValue: 0x8B) // 無変換
    public static let keyboardLANG1 = HIDKeyCode(rawValue: 0x90) // かな/変換
    public static let keyboardLANG2 = HIDKeyCode(rawValue: 0x91) // 英数/無変換

    // MARK: 修飾キー

    public static let keyboardRightAlt = HIDKeyCode(rawValue: 0xE6)

    // MARK: エラー/未定義

    public static let keyboardErrorUndefined = HIDKeyCode(rawValue: 0x03)

    // MARK: システム IME トリガーキー

    /// システム IME の切替をトリガーするキーコード
    ///
    /// fullControlMode 有効時にこれらのキーをインターセプトし、
    /// システム IME の切替を防止する。
    public static let systemIMETriggerKeys: Set<HIDKeyCode> = [
        .keyboardLANG1,           // かな
        .keyboardLANG2,           // 英数
        .keyboardCapsLock,        // CAPS LOCK
        .keyboardInternational4,  // 変換
        .keyboardInternational5,  // 無変換
        .keyboardInternational2,  // ひらがな/カタカナ
    ]
}

// MARK: - KeyModifierFlags

/// プラットフォーム非依存の修飾キーフラグ
public struct KeyModifierFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let shift     = KeyModifierFlags(rawValue: 1 << 0)
    public static let control   = KeyModifierFlags(rawValue: 1 << 1)
    public static let alternate = KeyModifierFlags(rawValue: 1 << 2)
    public static let command   = KeyModifierFlags(rawValue: 1 << 3)
}
