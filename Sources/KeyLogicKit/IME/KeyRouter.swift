import Foundation

/// 汎用キールーター
///
/// KeymapDefinition のデータに基づいてキーイベントを KeyAction に変換する。
/// 入力方式ごとのサブクラスは不要 — データ（テーブル）で振る舞いが決まる。
///
/// ルーティングの優先順位:
///   1. Ctrl+キー（composing 中）→ controlBindings の Emacs バインド
///   2. 標準制御キー（composing 中）→ Enter/Escape/Space/BS/矢印/数字
///      ※ chord 方式ではシフトキー（Space 等）を除外（selecting 中を除く）
///   3. behavior に応じた文字キー処理:
///      - sequential: event.characters → .printable(c)
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
    ///   - isDirectEnglishMode: 英数直接入力モードか（薙刀式の F+G 後の状態）
    /// - Returns: 実行すべきアクション
    public func route(_ event: KeyEvent, isComposing: Bool,
               state: InputManager.ConversionState,
               isDirectEnglishMode: Bool = false) -> KeyAction {
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

        // behavior に応じた文字キー処理
        switch definition.behavior {
        case .sequential(let characterMap):
            return routeSequential(event, characterMap: characterMap, isComposing: isComposing, state: state)
        case .chord(let config):
            return routeChord(event, config: config, isComposing: isComposing, state: state,
                              isDirectEnglishMode: isDirectEnglishMode)
        }
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

    // MARK: - Sequential（逐次入力）

    /// 逐次入力方式のルーティング
    ///
    /// event.characters を keyRemap で論理キーに変換し、
    /// characterMap に含まれるか英字/数字であれば .printable を返す。
    /// inputMappings がある場合は、全ての非制御文字を .printable として IME に渡す
    /// （記号キー `;`, `,`, `.`, `/` 等もカスタムテーブルで解決するため）。
    /// 数字は composing 中のテキストに直接追加される（azooKey-Desktop と同等）。
    /// .printable には物理キー文字を渡す（論理変換は addPrintableToComposing で行う）。
    /// それ以外は .pass。
    private func routeSequential(_ event: KeyEvent, characterMap: [Character: Character],
                                 isComposing: Bool, state: InputManager.ConversionState) -> KeyAction {
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
        if definition.inputMappings != nil,
           let scalar = c.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar) {
            return .printable(c)
        }
        return .pass
    }

    // MARK: - Chord（同時打鍵）

    /// 同時打鍵方式のルーティング
    ///
    /// 文字キーは SimultaneousKeyBuffer に投入するため .chordInput を返す。
    /// シフトキーは .chordShiftDown を返す（どのキーがシフトかは shiftKeys で定義）。
    /// 英数直接入力モードでは、キーマップにないキーの印字可能文字を .directInsert で返す。
    private func routeChord(_ event: KeyEvent, config: KeymapDefinition.ChordConfig,
                            isComposing: Bool, state: InputManager.ConversionState,
                            isDirectEnglishMode: Bool) -> KeyAction {
        // 同時打鍵テーブルに含まれるキー → シフトキーか文字キーかを判定
        if let chordKey = config.hidToKey[event.keyCode] {
            if config.shiftKeys.contains(where: { $0.key == chordKey }) {
                return .chordShiftDown(chordKey)
            }
            return .chordInput(chordKey)
        }

        // 英数モード: 印字可能文字は直接挿入
        if isDirectEnglishMode {
            let chars = event.characters
            if !chars.isEmpty,
               let scalar = chars.unicodeScalars.first,
               !CharacterSet.controlCharacters.contains(scalar) {
                return .directInsert(chars)
            }
        }

        return .pass
    }
}
