import Foundation

/// 汎用キールーター
///
/// KeymapDefinition のデータに基づいてキーイベントを KeyAction に変換する。
/// 入力方式ごとのサブクラスは不要 — データ（テーブル）で振る舞いが決まる。
///
/// ルーティングの優先順位:
///   0. modeKeys → モード切替キー（最優先）
///   1. Ctrl+キー（composing 中）→ controlBindings の Emacs バインド
///   2. 標準制御キー（composing 中）→ Enter/Escape/Space/BS/矢印/数字
///      ※ chord 方式ではシフトキー（Space 等）を除外（selecting 中を除く）
///   3. behavior に応じた文字キー処理:
///      - sequential: event.characters → .printable(c) / .directInsert(c)
///      - chord: hidToKey → .chordInput(key) / .chordShiftDown(key)
///   4. 該当なし → .pass
@MainActor
public struct KeyRouter {

    /// キーマップ定義
    public let definition: KeymapDefinition

    /// 公開イニシャライザ
    public init(definition: KeymapDefinition) {
        self.definition = definition
    }

    /// キーイベントを KeyAction に変換する
    ///
    /// - Parameters:
    ///   - event: プラットフォーム非依存のキーイベント
    ///   - isComposing: 現在 composing/selecting 中か
    ///   - state: 現在の変換状態
    ///   - isDirectEnglishMode: 英数直接入力モードか（F+G 後や modeKeys 切替後の状態）
    /// - Returns: 実行すべきアクション
    public func route(_ event: KeyEvent, isComposing: Bool,
               state: InputManager.ConversionState,
               isDirectEnglishMode: Bool = false) -> KeyAction {
        // modeKeys: モード切替キー（最優先）
        if let action = matchModeKey(event) {
            return action
        }

        // Ctrl+キー（composing 中）→ Emacs バインド
        if isComposing && event.modifierFlags.contains(.control) {
            return routeControlKey(event)
        }

        // composing/selecting 中の標準制御キー
        if isComposing {
            // chord 方式: シフトキー（Space 等）は selecting 以外では
            // 同時打鍵バッファに委ねる（singleTapAction で .convert が発火する）
            let isChordShiftKey: Bool
            if case .chord(let config) = definition.behavior,
               state != .selecting,
               let chordKey = config.hidToKey[event.keyCode],
               config.shiftKeys.contains(where: { $0.key == chordKey }) {
                isChordShiftKey = true
            } else {
                isChordShiftKey = false
            }

            if !isChordShiftKey, let action = routeStandardControlKey(event, state: state) {
                return action
            }
        }

        // idle 時の Option+矢印 → 文ナビゲーション / スマート選択
        if !isComposing, let action = routeOptionArrow(event) {
            return action
        }

        // idle 時のスペースキー → 確定スペース挿入（半角/全角は InputManager で制御）
        // 英数直接入力モードでは super に委譲（通常の半角スペース）
        // chord 方式でスペースがシフトキーの場合は除外（SandS: chord buffer に委ねる）
        if !isComposing && !isDirectEnglishMode && event.keyCode == .keyboardSpacebar {
            if case .chord(let config) = definition.behavior,
               let chordKey = config.hidToKey[event.keyCode],
               config.shiftKeys.contains(where: { $0.key == chordKey }) {
                // chord シフトキー → routeChord に委譲（SandS の単打/長押し判定を行う）
            } else {
                return .insertSpace(shifted: event.modifierFlags.contains(.shift))
            }
        }

        // behavior に応じた文字キー処理
        switch definition.behavior {
        case .sequential(let characterMap):
            return routeSequential(event, characterMap: characterMap, isComposing: isComposing,
                                   state: state, isDirectEnglishMode: isDirectEnglishMode)
        case .chord(let config):
            return routeChord(event, config: config, isComposing: isComposing, state: state,
                              isDirectEnglishMode: isDirectEnglishMode)
        }
    }

    // MARK: - modeKeys マッチング

    /// modeKeys からイベントにマッチするアクションを検索する
    ///
    /// 修飾キーありのトリガーを優先的にマッチさせ、次に修飾キーなし（修飾キー不問）をマッチさせる。
    private func matchModeKey(_ event: KeyEvent) -> KeyAction? {
        guard let modeKeys = definition.modeKeys else { return nil }

        let eventMods = event.modifierFlags.intersection([.shift, .control, .alternate])

        // 修飾キー付きトリガーを優先チェック
        if !eventMods.isEmpty {
            let trigger = KeymapDefinition.ModeKeyTrigger(keyCode: event.keyCode, modifiers: eventMods)
            if let action = modeKeys[trigger] {
                return action
            }
        }

        // 修飾キーなしトリガー（修飾キー不問で常にマッチ）
        let bareTrigger = KeymapDefinition.ModeKeyTrigger(keyCode: event.keyCode)
        return modeKeys[bareTrigger]
    }

    // MARK: - Ctrl+キー（Emacs バインド）

    /// Ctrl+キーを controlBindings から検索して KeyAction に変換する
    private func routeControlKey(_ event: KeyEvent) -> KeyAction {
        let bindings = definition.controlBindings

        // Ctrl+: の特殊処理（Shift+; で入力、Ctrl+Shift+; として届く）
        // Ctrl+; と同じ keyCode (0x33) だが Shift が付いている場合
        if event.keyCode == .keyboardSemicolon && event.modifierFlags.contains(.shift) {
            if let action = bindings.ctrlColonAction {
                return action
            }
        }

        // Ctrl+; の特殊処理
        if event.characters == ";" || event.keyCode == .keyboardSemicolon {
            if let action = bindings.ctrlSemicolonAction {
                return action
            }
        }

        // 通常の Ctrl+キー
        if let action = bindings.emacsBindings[event.keyCode] {
            return action
        }

        // 未定義の Ctrl+キーは消費（composing 中は super に渡さない）
        return .pass
    }

    // MARK: - 標準制御キー（全入力方式共通）

    /// composing/previewing/selecting 中の標準制御キーを KeyAction に変換する
    ///
    /// Enter, Escape, Space, BS, 矢印, 数字キーの振る舞いは
    /// 全入力方式で共通のためハードコードする。
    private func routeStandardControlKey(_ event: KeyEvent, state: InputManager.ConversionState) -> KeyAction? {
        switch event.keyCode {
        case .keyboardReturnOrEnter, .keyboardTab:
            return .confirm

        case .keyboardEscape:
            return .cancel

        case .keyboardSpacebar:
            if event.modifierFlags.contains(.shift) && state == .selecting {
                return .convertPrev
            }
            return .convert

        case .keyboardDeleteOrBackspace:
            return .deleteBack

        case .keyboardLeftArrow:
            if event.modifierFlags.contains(.shift) {
                return .editSegmentLeft
            }
            return .moveLeft

        case .keyboardRightArrow:
            if event.modifierFlags.contains(.shift) {
                return .editSegmentRight
            }
            return .moveRight

        case .keyboardUpArrow:
            return .moveUp

        case .keyboardDownArrow:
            return .moveDown

        case .keyboard1, .keyboard2, .keyboard3, .keyboard4, .keyboard5,
             .keyboard6, .keyboard7, .keyboard8, .keyboard9:
            if state == .selecting && !event.modifierFlags.contains(.shift) {
                let offset = Int(event.keyCode.rawValue) - Int(HIDKeyCode.keyboard1.rawValue)
                return .selectCandidate(offset)
            }
            // composing/previewing 中の数字キーは nil を返して後続の文字入力処理に委譲
            return nil

        default:
            return nil
        }
    }

    // MARK: - Option+矢印（文ナビゲーション / スマート選択）

    /// idle 時の Option+矢印キーを文ナビゲーション / スマート選択に変換する
    ///
    /// - Shift なし: 文頭/文末移動、文入れ替え
    /// - Shift あり: スマート選択拡大/縮小、文選択拡張
    private func routeOptionArrow(_ event: KeyEvent) -> KeyAction? {
        guard event.modifierFlags.contains(.alternate) else { return nil }

        let hasShift = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case .keyboardLeftArrow:
            return hasShift ? .smartSelectShrink : .moveSentenceStart
        case .keyboardRightArrow:
            return hasShift ? .smartSelectExpand : .moveSentenceEnd
        case .keyboardUpArrow:
            return hasShift ? .selectSentenceUp : .swapSentenceUp
        case .keyboardDownArrow:
            return hasShift ? .selectSentenceDown : .swapSentenceDown
        default:
            return nil
        }
    }

    // MARK: - Sequential（逐次入力）

    /// 逐次入力方式のルーティング
    ///
    /// event.characters を keyRemap で論理キーに変換し、
    /// characterMap に含まれるか英字/数字であれば .printable を返す。
    /// inputMappings がある場合は、全ての非制御文字を .printable として IME に渡す
    /// （記号キー `;`, `,`, `.`, `/` 等もカスタムテーブルで解決するため）。
    /// 数字は composing 中のテキストに直接追加される（azooKey-Desktop と同等）。
    /// .printable には物理キー文字を渡す（論理変換は addPrintableToComposing で行う）。
    /// 英数直接入力モードでは印字可能文字を .directInsert で返す。
    /// それ以外は .pass。
    private func routeSequential(_ event: KeyEvent, characterMap: [Character: Character],
                                 isComposing: Bool, state: InputManager.ConversionState,
                                 isDirectEnglishMode: Bool) -> KeyAction {
        // 英数直接入力モード: 印字可能文字は直接挿入
        // chars.count == 1 で "UIKeyInputDownArrow" 等の特殊文字列を除外
        if isDirectEnglishMode {
            let chars = event.characters
            if chars.count == 1,
               let scalar = chars.unicodeScalars.first,
               !CharacterSet.controlCharacters.contains(scalar) {
                return .directInsert(chars)
            }
            return .pass
        }

        let chars = event.characters
        guard chars.count == 1, let c = chars.first else {
            return .pass
        }
        // keyRemap で論理キーに変換して判定
        let logical: Character
        if let remap = definition.keyRemap, let remapped = remap[String(c)]?.first {
            logical = remapped
        } else {
            logical = c
        }
        if characterMap[logical] != nil || logical.isLetter || (isComposing && logical.isNumber) {
            return .printable(c)
        }
        // inputMappings がある場合、全ての非制御文字を IME に渡す
        // スペースは除外（idle 時は .insertSpace、composing 時は .convert で処理済み）
        if definition.inputMappings != nil,
           let scalar = c.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar),
           c != " " {
            return .printable(c)
        }
        return .pass
    }

    // MARK: - Chord（同時打鍵）

    /// 同時打鍵方式のルーティング
    ///
    /// 文字キーは SimultaneousKeyBuffer に投入するため .chordInput を返す。
    /// シフトキーは .chordShiftDown を返す（どのキーがシフトかは shiftKeys で定義）。
    /// 英数直接入力モードでは:
    ///   - englishLookupTable がある場合: chord buffer 経由で英数テーブルを使用
    ///   - englishLookupTable がない場合: chord buffer をバイパスし QWERTY 文字を直接挿入
    ///   - キーマップにないキーの印字可能文字は .directInsert で返す
    private func routeChord(_ event: KeyEvent, config: KeymapDefinition.ChordConfig,
                            isComposing: Bool, state: InputManager.ConversionState,
                            isDirectEnglishMode: Bool) -> KeyAction {
        // 同時打鍵テーブルに含まれるキー → シフトキーか文字キーかを判定
        if let chordKey = config.hidToKey[event.keyCode] {
            // 英数モードで englishLookupTable がない場合は chord buffer をバイパスし、
            // QWERTY 文字を直接挿入する（NICOLA 等でひらがなが出力されるバグの修正）
            if isDirectEnglishMode && config.englishLookupTable == nil {
                let chars = event.characters
                if chars.count == 1,
                   let scalar = chars.unicodeScalars.first,
                   !CharacterSet.controlCharacters.contains(scalar) {
                    return .directInsert(chars)
                }
                return .pass
            }
            if config.shiftKeys.contains(where: { $0.key == chordKey }) {
                return .chordShiftDown(chordKey)
            }
            return .chordInput(chordKey)
        }

        // 英数モード: キーマップにないキーの印字可能文字は直接挿入
        // chars.count == 1 で "UIKeyInputDownArrow" 等の特殊文字列を除外
        if isDirectEnglishMode {
            let chars = event.characters
            if chars.count == 1,
               let scalar = chars.unicodeScalars.first,
               !CharacterSet.controlCharacters.contains(scalar) {
                return .directInsert(chars)
            }
        }

        return .pass
    }
}
