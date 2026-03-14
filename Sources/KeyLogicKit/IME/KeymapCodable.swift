import Foundation

// MARK: - Private Helpers

/// 動的な文字列キー（辞書の JSON エンコード/デコード用）
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - HIDKeyCode ↔ 文字列名

/// HIDKeyCode と JSON 用文字列名の相互変換
///
/// フォーマット仕様の独自命名を使用。Apple の UIKeyboardHIDUsage 名には依存しない。
private enum HIDUsageNames {

    /// HIDKeyCode → 文字列名
    static func name(for keyCode: HIDKeyCode) -> String? {
        codeToName[keyCode]
    }

    /// 文字列名 → HIDKeyCode
    static func keyCode(for name: String) -> HIDKeyCode? {
        nameToCode[name]
    }

    private static let table: [(HIDKeyCode, String)] = [
        // アルファベット
        (.keyboardA, "a"), (.keyboardB, "b"), (.keyboardC, "c"),
        (.keyboardD, "d"), (.keyboardE, "e"), (.keyboardF, "f"),
        (.keyboardG, "g"), (.keyboardH, "h"), (.keyboardI, "i"),
        (.keyboardJ, "j"), (.keyboardK, "k"), (.keyboardL, "l"),
        (.keyboardM, "m"), (.keyboardN, "n"), (.keyboardO, "o"),
        (.keyboardP, "p"), (.keyboardQ, "q"), (.keyboardR, "r"),
        (.keyboardS, "s"), (.keyboardT, "t"), (.keyboardU, "u"),
        (.keyboardV, "v"), (.keyboardW, "w"), (.keyboardX, "x"),
        (.keyboardY, "y"), (.keyboardZ, "z"),
        // 数字
        (.keyboard1, "1"), (.keyboard2, "2"), (.keyboard3, "3"),
        (.keyboard4, "4"), (.keyboard5, "5"), (.keyboard6, "6"),
        (.keyboard7, "7"), (.keyboard8, "8"), (.keyboard9, "9"),
        (.keyboard0, "0"),
        // 制御キー
        (.keyboardReturnOrEnter, "enter"),
        (.keyboardEscape, "escape"),
        (.keyboardDeleteOrBackspace, "backspace"),
        (.keyboardDeleteForward, "delete"),
        (.keyboardTab, "tab"),
        (.keyboardSpacebar, "space"),
        (.keyboardCapsLock, "capsLock"),
        // 記号
        (.keyboardHyphen, "hyphen"),
        (.keyboardEqualSign, "equal"),
        (.keyboardOpenBracket, "bracketLeft"),
        (.keyboardCloseBracket, "bracketRight"),
        (.keyboardBackslash, "backslash"),
        (.keyboardSemicolon, "semicolon"),
        (.keyboardQuote, "quote"),
        (.keyboardGraveAccentAndTilde, "backquote"),
        (.keyboardComma, "comma"),
        (.keyboardPeriod, "period"),
        (.keyboardSlash, "slash"),
        // ナビゲーション
        (.keyboardRightArrow, "arrowRight"),
        (.keyboardLeftArrow, "arrowLeft"),
        (.keyboardDownArrow, "arrowDown"),
        (.keyboardUpArrow, "arrowUp"),
        (.keyboardHome, "home"),
        (.keyboardEnd, "end"),
        (.keyboardPageUp, "pageUp"),
        (.keyboardPageDown, "pageDown"),
        // ファンクションキー
        (.keyboardF1, "f1"), (.keyboardF2, "f2"), (.keyboardF3, "f3"),
        (.keyboardF4, "f4"), (.keyboardF5, "f5"), (.keyboardF6, "f6"),
        (.keyboardF7, "f7"), (.keyboardF8, "f8"), (.keyboardF9, "f9"),
        (.keyboardF10, "f10"), (.keyboardF11, "f11"), (.keyboardF12, "f12"),
        // JIS 固有キー
        (.keyboardInternational1, "international1"),   // ¥/_ キー（JIS）
        (.keyboardInternational2, "international2"),   // ひらがな/カタカナ（JIS）
        (.keyboardInternational3, "international3"),   // ¥ キー（JIS バックスラッシュ横）
        (.keyboardInternational4, "international4"),   // 変換
        (.keyboardInternational5, "international5"),   // 無変換
        (.keyboardLANG1, "lang1"),                     // かな/変換
        (.keyboardLANG2, "lang2"),                     // 英数/無変換
        // 修飾キー
        (.keyboardRightAlt, "rightAlt"),
    ]

    static let codeToName: [HIDKeyCode: String] = {
        var dict: [HIDKeyCode: String] = [:]
        for (code, name) in table {
            dict[code] = name
        }
        return dict
    }()

    static let nameToCode: [String: HIDKeyCode] = {
        var dict: [String: HIDKeyCode] = [:]
        for (code, name) in table {
            dict[name] = code
        }
        return dict
    }()
}

// MARK: - ChordKey ↔ 文字列名

/// ChordKey と JSON 用文字列名の相互変換
private enum ChordKeyNames {

    /// ChordKey → 文字列名（case 名をそのまま使用）
    static func name(for key: ChordKey) -> String {
        keyToName[key]!
    }

    /// 文字列名 → ChordKey
    static func key(for name: String) -> ChordKey? {
        nameToKey[name]
    }

    static let keyToName: [ChordKey: String] = [
        .Q: "Q", .W: "W", .E: "E", .R: "R", .T: "T",
        .Y: "Y", .U: "U", .I: "I", .O: "O", .P: "P",
        .A: "A", .S: "S", .D: "D", .F: "F", .G: "G",
        .H: "H", .J: "J", .K: "K", .L: "L", .semicolon: "semicolon",
        .Z: "Z", .X: "X", .C: "C", .V: "V", .B: "B",
        .N: "N", .M: "M", .comma: "comma", .dot: "dot", .slash: "slash",
        .space: "space", .leftThumb: "leftThumb", .rightThumb: "rightThumb",
    ]

    static let nameToKey: [String: ChordKey] = {
        var dict: [String: ChordKey] = [:]
        for (key, name) in keyToName {
            dict[name] = key
        }
        return dict
    }()
}

// MARK: - ビットマスク ↔ キー名文字列

/// ChordKey ビットマスクと "F+J" 形式文字列の相互変換
private enum BitmaskEncoding {

    /// UInt64 ビットマスク → "F+J" 形式の文字列
    ///
    /// 親指キー（space, leftThumb, rightThumb）は常に先頭、残りはアルファベット順でソート。
    static func string(from bits: UInt64) -> String {
        let thumbKeys: Set<ChordKey> = [.space, .leftThumb, .rightThumb]
        var thumbNames: [String] = []
        var names: [String] = []
        for chordKey in ChordKey.allCases {
            guard bits & chordKey.bit != 0 else { continue }
            let name = ChordKeyNames.name(for: chordKey)
            if thumbKeys.contains(chordKey) {
                thumbNames.append(name)
            } else {
                names.append(name)
            }
        }
        thumbNames.sort()
        names.sort()
        return (thumbNames + names).joined(separator: "+")
    }

    /// "F+J" 形式の文字列 → UInt64 ビットマスク
    static func bits(from string: String) -> UInt64? {
        let names = string.split(separator: "+").map(String.init)
        guard !names.isEmpty else { return nil }
        var result: UInt64 = 0
        for name in names {
            guard let key = ChordKeyNames.key(for: name) else { return nil }
            result |= key.bit
        }
        return result
    }
}

// MARK: - ChordKey: Codable

extension ChordKey: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ChordKeyNames.name(for: self))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let key = ChordKeyNames.key(for: name) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "不明な ChordKey 名: \(name)"
            )
        }
        self = key
    }
}

// MARK: - ShiftKeyConfig: Codable


extension KeymapDefinition.ShiftKeyConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case key
        case singleTapAction
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(singleTapAction, forKey: .singleTapAction)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(ChordKey.self, forKey: .key)
        self.singleTapAction = try container.decodeIfPresent(KeyAction.self, forKey: .singleTapAction)
    }
}

// MARK: - KeyAction: Codable

extension KeyAction: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .convert:                   try container.encode("convert")
        case .convertPrev:               try container.encode("convertPrev")
        case .confirm:                   try container.encode("confirm")
        case .cancel:                    try container.encode("cancel")
        case .deleteBack:                try container.encode("deleteBack")
        case .moveLeft:                  try container.encode("moveLeft")
        case .moveRight:                 try container.encode("moveRight")
        case .moveUp:                    try container.encode("moveUp")
        case .moveDown:                  try container.encode("moveDown")
        case .editSegmentLeft:           try container.encode("editSegmentLeft")
        case .editSegmentRight:          try container.encode("editSegmentRight")
        case .confirmHiragana:           try container.encode("confirmHiragana")
        case .confirmKatakana:           try container.encode("confirmKatakana")
        case .confirmHalfWidthKatakana:  try container.encode("confirmHalfWidthKatakana")
        case .confirmFullWidthRoman:     try container.encode("confirmFullWidthRoman")
        case .confirmHalfWidthRoman:     try container.encode("confirmHalfWidthRoman")
        case .chordShiftDown(let key):
            try container.encode("chordShiftDown:\(ChordKeyNames.name(for: key))")
        case .insertAndConfirm(let s):
            try container.encode("insertAndConfirm:\(s)")
        case .switchToEnglish:           try container.encode("switchToEnglish")
        case .switchToJapanese:          try container.encode("switchToJapanese")
        case .toggleInputMode:           try container.encode("toggleInputMode")
        case .pass:                      try container.encode("pass")
        case .moveSentenceStart:         try container.encode("moveSentenceStart")
        case .moveSentenceEnd:           try container.encode("moveSentenceEnd")
        case .swapSentenceUp:            try container.encode("swapSentenceUp")
        case .swapSentenceDown:          try container.encode("swapSentenceDown")
        case .smartSelectExpand:         try container.encode("smartSelectExpand")
        case .smartSelectShrink:         try container.encode("smartSelectShrink")
        case .selectSentenceUp:          try container.encode("selectSentenceUp")
        case .selectSentenceDown:        try container.encode("selectSentenceDown")
        case .printable(let c):
            try container.encode("printable:\(c)")
        case .selectCandidate(let i):
            try container.encode("selectCandidate:\(i)")
        case .chordInput(let key):
            try container.encode("chordInput:\(ChordKeyNames.name(for: key))")
        case .directInsert(let s):
            try container.encode("directInsert:\(s)")
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "convert":                  self = .convert
        case "convertPrev":              self = .convertPrev
        case "confirm":                  self = .confirm
        case "cancel":                   self = .cancel
        case "deleteBack":               self = .deleteBack
        case "moveLeft":                 self = .moveLeft
        case "moveRight":                self = .moveRight
        case "moveUp":                   self = .moveUp
        case "moveDown":                 self = .moveDown
        case "editSegmentLeft":          self = .editSegmentLeft
        case "editSegmentRight":         self = .editSegmentRight
        case "confirmHiragana":          self = .confirmHiragana
        case "confirmKatakana":          self = .confirmKatakana
        case "confirmHalfWidthKatakana": self = .confirmHalfWidthKatakana
        case "confirmFullWidthRoman":    self = .confirmFullWidthRoman
        case "confirmHalfWidthRoman":    self = .confirmHalfWidthRoman
        case "switchToEnglish":           self = .switchToEnglish
        case "switchToJapanese":          self = .switchToJapanese
        case "toggleInputMode":           self = .toggleInputMode
        case "pass":                     self = .pass
        case "moveSentenceStart":        self = .moveSentenceStart
        case "moveSentenceEnd":          self = .moveSentenceEnd
        case "swapSentenceUp":           self = .swapSentenceUp
        case "swapSentenceDown":         self = .swapSentenceDown
        case "smartSelectExpand":        self = .smartSelectExpand
        case "smartSelectShrink":        self = .smartSelectShrink
        case "selectSentenceUp":         self = .selectSentenceUp
        case "selectSentenceDown":       self = .selectSentenceDown
        case "printable":
            guard parts.count == 2, parts[1].count == 1, let c = parts[1].first else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "printable には1文字が必要: \(string)"
                )
            }
            self = .printable(c)
        case "selectCandidate":
            guard parts.count == 2, let i = Int(parts[1]) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "selectCandidate には整数が必要: \(string)"
                )
            }
            self = .selectCandidate(i)
        case "chordInput":
            guard parts.count == 2, let key = ChordKeyNames.key(for: parts[1]) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "chordInput には有効な ChordKey 名が必要: \(string)"
                )
            }
            self = .chordInput(key)
        case "insertAndConfirm":
            guard parts.count == 2 else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "insertAndConfirm には文字列が必要: \(string)"
                )
            }
            self = .insertAndConfirm(parts[1])
        case "chordShiftDown":
            guard parts.count == 2, let key = ChordKeyNames.key(for: parts[1]) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "chordShiftDown には有効な ChordKey 名が必要: \(string)"
                )
            }
            self = .chordShiftDown(key)
        case "directInsert":
            guard parts.count == 2 else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "directInsert には文字列が必要: \(string)"
                )
            }
            self = .directInsert(parts[1])
        default:
            // x- プレフィックスのアプリ固有アクションは無視（pass にフォールバック）
            if parts[0].hasPrefix("x-") {
                self = .pass
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "不明な KeyAction: \(string)"
                )
            }
        }
    }
}

// MARK: - ControlBindings: Codable

extension ControlBindings: Codable {
    private enum CodingKeys: String, CodingKey {
        case emacsBindings
        case ctrlSemicolonAction
        case ctrlColonAction
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // emacsBindings: [HIDKeyCode: KeyAction] → {"h": "deleteBack", ...}
        var bindingsContainer = container.nestedContainer(
            keyedBy: DynamicCodingKey.self, forKey: .emacsBindings
        )
        for (keyCode, action) in emacsBindings {
            guard let name = HIDUsageNames.name(for: keyCode) else { continue }
            try bindingsContainer.encode(action, forKey: DynamicCodingKey(stringValue: name))
        }

        try container.encodeIfPresent(ctrlSemicolonAction, forKey: .ctrlSemicolonAction)
        try container.encodeIfPresent(ctrlColonAction, forKey: .ctrlColonAction)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let bindingsContainer = try container.nestedContainer(
            keyedBy: DynamicCodingKey.self, forKey: .emacsBindings
        )
        var bindings: [HIDKeyCode: KeyAction] = [:]
        for key in bindingsContainer.allKeys {
            guard let code = HIDUsageNames.keyCode(for: key.stringValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: bindingsContainer,
                    debugDescription: "不明な HID usage 名: \(key.stringValue)"
                )
            }
            let action = try bindingsContainer.decode(KeyAction.self, forKey: key)
            bindings[code] = action
        }
        self.emacsBindings = bindings

        self.ctrlSemicolonAction = try container.decodeIfPresent(KeyAction.self, forKey: .ctrlSemicolonAction)
        self.ctrlColonAction = try container.decodeIfPresent(KeyAction.self, forKey: .ctrlColonAction)
    }
}

// MARK: - KeymapDefinition.ChordConfig: Codable

extension KeymapDefinition.ChordConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case hidToKey
        case lookupTable
        case specialActions
        case simultaneousWindow
        case englishLookupTable
        case englishSpecialActions
        case shiftKeys
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // hidToKey: [HIDKeyCode: ChordKey] → {"q": "Q", ...}
        var hidContainer = container.nestedContainer(
            keyedBy: DynamicCodingKey.self, forKey: .hidToKey
        )
        for (keyCode, nKey) in hidToKey {
            guard let name = HIDUsageNames.name(for: keyCode) else { continue }
            try hidContainer.encode(nKey, forKey: DynamicCodingKey(stringValue: name))
        }

        // lookupTable: [UInt64: String] → {"J": "あ", "F+J": "が", ...}
        try encodeBitmaskStringDict(lookupTable, to: &container, forKey: .lookupTable)

        // specialActions: [UInt64: KeyAction] → {"U": "deleteBack", ...}
        try encodeBitmaskActionDict(specialActions, to: &container, forKey: .specialActions)

        try container.encode(simultaneousWindow, forKey: .simultaneousWindow)

        if let englishLookup = englishLookupTable {
            try encodeBitmaskStringDict(englishLookup, to: &container, forKey: .englishLookupTable)
        }

        if let englishActions = englishSpecialActions {
            try encodeBitmaskActionDict(englishActions, to: &container, forKey: .englishSpecialActions)
        }

        try container.encode(shiftKeys, forKey: .shiftKeys)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // hidToKey
        let hidContainer = try container.nestedContainer(
            keyedBy: DynamicCodingKey.self, forKey: .hidToKey
        )
        var hidDict: [HIDKeyCode: ChordKey] = [:]
        for key in hidContainer.allKeys {
            guard let code = HIDUsageNames.keyCode(for: key.stringValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: hidContainer,
                    debugDescription: "不明な HID usage 名: \(key.stringValue)"
                )
            }
            hidDict[code] = try hidContainer.decode(ChordKey.self, forKey: key)
        }
        self.hidToKey = hidDict

        // lookupTable
        self.lookupTable = try Self.decodeBitmaskStringDict(from: container, forKey: .lookupTable)

        // specialActions
        self.specialActions = try Self.decodeBitmaskActionDict(from: container, forKey: .specialActions)

        self.simultaneousWindow = try container.decode(TimeInterval.self, forKey: .simultaneousWindow)

        // englishLookupTable (optional)
        if container.contains(.englishLookupTable) {
            self.englishLookupTable = try Self.decodeBitmaskStringDict(from: container, forKey: .englishLookupTable)
        } else {
            self.englishLookupTable = nil
        }

        // englishSpecialActions (optional)
        if container.contains(.englishSpecialActions) {
            self.englishSpecialActions = try Self.decodeBitmaskActionDict(from: container, forKey: .englishSpecialActions)
        } else {
            self.englishSpecialActions = nil
        }

        // shiftKeys（省略時は Space センターシフトにフォールバック）
        self.shiftKeys = try container.decodeIfPresent(
            [KeymapDefinition.ShiftKeyConfig].self, forKey: .shiftKeys
        ) ?? [KeymapDefinition.ShiftKeyConfig(key: .space, singleTapAction: .convert)]
    }

    // MARK: - Private encode/decode helpers

    /// [UInt64: String] 辞書をビットマスク文字列キーでエンコード
    private func encodeBitmaskStringDict(
        _ dict: [UInt64: String],
        to container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        var nested = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: key)
        for (bits, value) in dict {
            let keyName = BitmaskEncoding.string(from: bits)
            try nested.encode(value, forKey: DynamicCodingKey(stringValue: keyName))
        }
    }

    /// [UInt64: KeyAction] 辞書をビットマスク文字列キーでエンコード
    private func encodeBitmaskActionDict(
        _ dict: [UInt64: KeyAction],
        to container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        var nested = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: key)
        for (bits, action) in dict {
            let keyName = BitmaskEncoding.string(from: bits)
            try nested.encode(action, forKey: DynamicCodingKey(stringValue: keyName))
        }
    }

    /// ビットマスク文字列キーの辞書から [UInt64: String] をデコード
    private static func decodeBitmaskStringDict(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [UInt64: String] {
        let nested = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: key)
        var dict: [UInt64: String] = [:]
        for codingKey in nested.allKeys {
            guard let bits = BitmaskEncoding.bits(from: codingKey.stringValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: codingKey, in: nested,
                    debugDescription: "不正なビットマスクキー: \(codingKey.stringValue)"
                )
            }
            dict[bits] = try nested.decode(String.self, forKey: codingKey)
        }
        return dict
    }

    /// ビットマスク文字列キーの辞書から [UInt64: KeyAction] をデコード
    private static func decodeBitmaskActionDict(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [UInt64: KeyAction] {
        let nested = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: key)
        var dict: [UInt64: KeyAction] = [:]
        for codingKey in nested.allKeys {
            guard let bits = BitmaskEncoding.bits(from: codingKey.stringValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: codingKey, in: nested,
                    debugDescription: "不正なビットマスクキー: \(codingKey.stringValue)"
                )
            }
            dict[bits] = try nested.decode(KeyAction.self, forKey: codingKey)
        }
        return dict
    }
}

// MARK: - KeymapDefinition.InputBehavior: Codable

extension KeymapDefinition.InputBehavior: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case characterMap
        case config
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sequential(let characterMap):
            try container.encode("sequential", forKey: .type)
            // [Character: Character] → {"a": "あ", ...}
            var mapContainer = container.nestedContainer(
                keyedBy: DynamicCodingKey.self, forKey: .characterMap
            )
            for (key, value) in characterMap {
                try mapContainer.encode(
                    String(value),
                    forKey: DynamicCodingKey(stringValue: String(key))
                )
            }

        case .chord(let config):
            try container.encode("chord", forKey: .type)
            try container.encode(config, forKey: .config)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "sequential":
            let mapContainer = try container.nestedContainer(
                keyedBy: DynamicCodingKey.self, forKey: .characterMap
            )
            var characterMap: [Character: Character] = [:]
            for codingKey in mapContainer.allKeys {
                let value = try mapContainer.decode(String.self, forKey: codingKey)
                guard codingKey.stringValue.count == 1, let keyChar = codingKey.stringValue.first else {
                    throw DecodingError.dataCorruptedError(
                        forKey: codingKey, in: mapContainer,
                        debugDescription: "characterMap のキーは1文字: \(codingKey.stringValue)"
                    )
                }
                guard value.count == 1, let valueChar = value.first else {
                    throw DecodingError.dataCorruptedError(
                        forKey: codingKey, in: mapContainer,
                        debugDescription: "characterMap の値は1文字: \(value)"
                    )
                }
                characterMap[keyChar] = valueChar
            }
            self = .sequential(characterMap: characterMap)

        case "chord":
            let config = try container.decode(KeymapDefinition.ChordConfig.self, forKey: .config)
            self = .chord(config: config)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: CodingKeys.type, in: container,
                debugDescription: "不明な behavior type: \(type)"
            )
        }
    }
}

// MARK: - KeymapDefinition: Codable

extension KeymapDefinition: Codable {
    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case name
        case description
        case author
        case license
        case keyboardLayout
        case targetScript
        case behavior
        case controlBindings
        case inputBase
        case keyRemap
        case suffixRules
        case inputMappings
        case prefixShiftKeys
        case modeKeys
        case extensions
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // メタデータ
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(license, forKey: .license)
        try container.encode(keyboardLayout, forKey: .keyboardLayout)
        try container.encodeIfPresent(targetScript, forKey: .targetScript)
        // 入力定義
        try container.encode(behavior, forKey: .behavior)
        try container.encode(controlBindings, forKey: .controlBindings)
        try container.encodeIfPresent(inputBase, forKey: .inputBase)
        try container.encodeIfPresent(keyRemap, forKey: .keyRemap)
        try container.encodeIfPresent(suffixRules, forKey: .suffixRules)
        // inputBase/suffixRules 展開時は元の明示的マッピングのみ書き出す（圧縮形式を保持）
        if explicitInputMappings != nil {
            try container.encodeIfPresent(explicitInputMappings, forKey: .inputMappings)
        } else {
            try container.encodeIfPresent(inputMappings, forKey: .inputMappings)
        }
        if let prefixShiftKeys {
            try container.encode(prefixShiftKeys.map(String.init), forKey: .prefixShiftKeys)
        }
        // modeKeys: [HIDKeyCode: KeyAction] → {"lang2": "switchToEnglish", ...}
        if let modeKeys {
            var modeContainer = container.nestedContainer(
                keyedBy: DynamicCodingKey.self, forKey: .modeKeys
            )
            for (keyCode, action) in modeKeys {
                guard let name = HIDUsageNames.name(for: keyCode) else { continue }
                try modeContainer.encode(action, forKey: DynamicCodingKey(stringValue: name))
            }
        }
        try container.encodeIfPresent(extensions, forKey: .extensions)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // メタデータ
        self.formatVersion = try container.decode(String.self, forKey: .formatVersion)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.author = try container.decodeIfPresent(String.self, forKey: .author)
        self.license = try container.decodeIfPresent(String.self, forKey: .license)
        self.keyboardLayout = try container.decode(String.self, forKey: .keyboardLayout)
        self.targetScript = try container.decodeIfPresent(String.self, forKey: .targetScript)
        // 入力定義
        self.behavior = try container.decode(InputBehavior.self, forKey: .behavior)
        self.controlBindings = try container.decodeIfPresent(
            ControlBindings.self, forKey: .controlBindings
        ) ?? .default
        let rawInputBase = try container.decodeIfPresent(String.self, forKey: .inputBase)
        let rawKeyRemap = try container.decodeIfPresent(
            [String: String].self, forKey: .keyRemap
        )
        let rawSuffixRules = try container.decodeIfPresent(
            [String: SuffixRule].self, forKey: .suffixRules
        )
        let rawInputMappings = try container.decodeIfPresent(
            [String: String].self, forKey: .inputMappings
        )
        self.inputBase = rawInputBase
        self.keyRemap = rawKeyRemap
        self.suffixRules = rawSuffixRules
        // inputBase / suffixRules がある場合は展開（論理キー空間のまま）
        if rawInputBase != nil || rawSuffixRules != nil {
            self.explicitInputMappings = rawInputMappings
            self.inputMappings = Self.expandInputMappings(
                inputBase: rawInputBase,
                suffixRules: rawSuffixRules,
                explicitMappings: rawInputMappings
            )
        } else {
            self.explicitInputMappings = nil
            self.inputMappings = rawInputMappings
        }
        if let rawKeys = try container.decodeIfPresent([String].self, forKey: .prefixShiftKeys) {
            self.prefixShiftKeys = rawKeys.compactMap(\.first)
        } else {
            self.prefixShiftKeys = nil
        }
        // modeKeys: {"lang2": "switchToEnglish", ...} → [HIDKeyCode: KeyAction]
        if let modeKeysContainer = try? container.nestedContainer(
            keyedBy: DynamicCodingKey.self, forKey: .modeKeys
        ) {
            var decoded: [HIDKeyCode: KeyAction] = [:]
            for key in modeKeysContainer.allKeys {
                guard let keyCode = HIDUsageNames.keyCode(for: key.stringValue) else { continue }
                decoded[keyCode] = try modeKeysContainer.decode(KeyAction.self, forKey: key)
            }
            self.modeKeys = decoded.isEmpty ? nil : decoded
        } else {
            self.modeKeys = nil
        }
        self.extensions = try container.decodeIfPresent(
            [String: String].self, forKey: .extensions
        )
    }
}

// SuffixRule: Codable は KeymapDefinition.swift で宣言時に付与（自動合成のため同一ファイル必須）
