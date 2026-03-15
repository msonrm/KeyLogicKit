import Foundation

/// キーマップ定義（JSON でシリアライズ可能な汎用フォーマット v1）
///
/// 全てのキー配列を「振る舞いの種類 + テーブルデータ」で表現する。
/// 入力方式の追加は新しい KeymapDefinition を作るだけで、コードの変更は不要。
public struct KeymapDefinition: Sendable {

    // MARK: - メタデータ

    /// フォーマットバージョン（現在は "1.0" 固定）
    public let formatVersion: String

    /// キーマップ名（表示用）
    public let name: String

    /// 入力方式の説明（任意）
    public let description: String?

    /// 作者名（任意）
    public let author: String?

    /// ライセンス識別子（SPDX 形式、任意）
    public let license: String?

    /// 対象キーボードの物理配列（"us", "jis" 等）
    public let keyboardLayout: String

    /// 出力文字体系（"hiragana", "katakana" 等、任意）
    public let targetScript: String?

    // MARK: - 入力定義

    /// 入力方式の振る舞い
    public let behavior: InputBehavior

    /// 制御キーバインド（composing/selecting 中）
    public var controlBindings: ControlBindings = .default

    /// ベーステーブルの種類（逐次入力方式用）
    ///
    /// `"romaji"` を指定すると、組み込み標準ローマ字テーブルを `inputMappings` のベースとして使用する。
    /// nil の場合は `inputMappings` をそのまま使用する（月配列等）。
    public let inputBase: String?

    /// キーリマップテーブル（逐次入力方式用、物理キー文字 → 論理キー文字）
    ///
    /// キー位置をリマップする配列（大西配列等）で使用する。
    /// 入力時に物理キーを論理キーに変換し、以降すべて論理キー空間で処理する。
    /// 例: 大西配列では物理 "j" → 論理 "t" なので、"j" を押すとバッファに "t" が入り、
    /// 論理キー空間の "ta" → "た" で変換される。
    /// `inputMappings` は論理キー空間のまま保持される（物理空間への展開は行わない）。
    public let keyRemap: [String: String]?

    /// サフィックス展開ルール（逐次入力方式用）
    ///
    /// ベーステーブルのエントリに対してサフィックスを自動展開する。
    /// 例: `"z": SuffixRule(vowel: "a", suffix: "ん")` は、母音 "a" で終わる全エントリに
    /// "子音+z → かな+ん" の展開を生成する（ka → kz → かん）。
    public let suffixRules: [String: SuffixRule]?

    /// 前置シフト方式の入力テーブル（キーシーケンス → かな）
    ///
    /// `sequential` 方式で使用する。キーシーケンスは key.characters を連結した文字列。
    /// 例: "dy" → "ぬ"（D前置+Y）, "kq" → "ぁ"（K前置+Q）, "sl" → "が"（S+L後置濁音）
    /// `inputBase` / `suffixRules` 指定時はデコード時に展開済みの完全テーブルが格納される。
    /// nil の場合は変換エンジン固有のデフォルトテーブルのみを使用する。
    public let inputMappings: [String: String]?

    /// JSON で明示的に指定されたマッピングのみ（roundtrip エンコード用）
    ///
    /// `inputBase` / `suffixRules` による展開前の元データ。展開なしの場合は nil。
    public var explicitInputMappings: [String: String]?

    /// 前置シフトキーの明示指定（逐次入力方式用）
    ///
    /// 指定されたキーのみをシフトキーとして扱い、⇧ ラベル + シフトレイヤーを生成する。
    /// 空配列の場合は前置シフトキーなし（ローマ字系配列向け）。
    /// 例: 月配列2-263 では `["d", "k"]`、AZIK では `[]`
    public let prefixShiftKeys: [Character]?

    /// モード切替キートリガー（HID コード + 修飾キー）
    ///
    /// 修飾キーなし（`modifiers` が空）のトリガーは、修飾キーの状態によらずマッチする（後方互換）。
    /// 修飾キーあり（`modifiers` が非空）のトリガーは、指定された修飾キーが押されている場合のみマッチする。
    public struct ModeKeyTrigger: Hashable, Sendable {
        /// 物理キーの HID コード
        public let keyCode: HIDKeyCode
        /// 必須修飾キー（空 = 修飾キー不問で常にマッチ）
        public let modifiers: KeyModifierFlags

        public init(keyCode: HIDKeyCode, modifiers: KeyModifierFlags = []) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    /// モード切替キー（トリガー → KeyAction）
    ///
    /// 逐次入力・同時打鍵問わず、英数直接入力モードの切替キーを定義する。
    /// 修飾キーなしのトリガーは修飾キーの状態によらず最優先でマッチする。
    /// 修飾キーありのトリガーは指定の修飾キーが押されている場合のみマッチする。
    /// 例: LANG2 → `.switchToEnglish`、Ctrl+Space → `.toggleInputMode`
    /// chord の specialActions で定義済みの F+G 等と共存可能。
    public let modeKeys: [ModeKeyTrigger: KeyAction]?

    /// アプリ固有の拡張フィールド（フォーマット仕様の範囲外）
    ///
    /// 将来の拡張用。キー名は `"x-"` プレフィックスを推奨。
    public let extensions: [String: String]?

    /// 現在のフォーマットバージョン
    public static let currentFormatVersion = "1.0"

    public init(name: String, behavior: InputBehavior, keyboardLayout: String,
         inputBase: String? = nil,
         keyRemap: [String: String]? = nil,
         suffixRules: [String: SuffixRule]? = nil,
         inputMappings: [String: String]? = nil,
         prefixShiftKeys: [Character]? = nil,
         controlBindings: ControlBindings = .default,
         modeKeys: [ModeKeyTrigger: KeyAction]? = nil,
         formatVersion: String = KeymapDefinition.currentFormatVersion,
         description: String? = nil, author: String? = nil,
         license: String? = nil, targetScript: String? = nil,
         extensions: [String: String]? = nil) {
        self.formatVersion = formatVersion
        self.name = name
        self.description = description
        self.author = author
        self.license = license
        self.keyboardLayout = keyboardLayout
        self.targetScript = targetScript
        self.behavior = behavior
        self.inputBase = inputBase
        self.keyRemap = keyRemap
        self.suffixRules = suffixRules
        self.prefixShiftKeys = prefixShiftKeys
        self.controlBindings = controlBindings
        self.modeKeys = modeKeys
        self.extensions = extensions

        // inputBase / suffixRules がある場合は展開（論理キー空間のまま）
        if inputBase != nil || suffixRules != nil {
            self.explicitInputMappings = inputMappings
            self.inputMappings = Self.expandInputMappings(
                inputBase: inputBase,
                suffixRules: suffixRules,
                explicitMappings: inputMappings
            )
        } else {
            self.explicitInputMappings = nil
            self.inputMappings = inputMappings
        }
    }

    /// サフィックス展開ルール
    public struct SuffixRule: Codable, Sendable {
        /// 対象となるベースエントリの母音（"a", "i", "u", "e", "o"）
        public let vowel: String
        /// 出力に付加するサフィックス文字列
        public let suffix: String
    }

    // MARK: - サフィックス展開

    /// `inputBase` + `suffixRules` + 明示的マッピングを展開して完全な inputMappings を生成する
    ///
    /// 展開順序:
    ///   1. `inputBase` でベーステーブルをロード（論理キー空間）
    ///   2. 明示的 `inputMappings` をマージ（論理キー空間）
    ///   3. `suffixRules` でサフィックス展開（論理キー空間）
    ///
    /// 結果は論理キー空間のまま返される。物理→論理変換は `keyRemap` でランタイムに行う。
    /// マージ優先順: `explicitMappings` > `suffixExpansions` > `base`
    public static func expandInputMappings(
        inputBase: String?,
        suffixRules: [String: SuffixRule]?,
        explicitMappings: [String: String]?
    ) -> [String: String]? {
        // ベーステーブル
        var base: [String: String] = [:]
        if inputBase == "romaji" {
            base = DefaultKeymaps.standardRomajiTable
        }

        // 明示的マッピングをベースにマージ（suffix 展開の対象にもなる）
        var allEntries = base
        if let explicit = explicitMappings {
            for (k, v) in explicit where !k.hasPrefix("_comment") {
                allEntries[k] = v
            }
        }

        // suffix 展開
        var suffixExpansions: [String: String] = [:]
        if let rules = suffixRules, !rules.isEmpty {
            let vowels: Set<Character> = ["a", "i", "u", "e", "o"]

            for (romajiSeq, kanaOutput) in allEntries {
                guard let lastChar = romajiSeq.last, vowels.contains(lastChar) else { continue }
                let consonantPrefix = String(romajiSeq.dropLast())
                // 母音単独（a, i, u, e, o）はスキップ
                guard !consonantPrefix.isEmpty else { continue }

                for (suffixKey, rule) in rules {
                    guard String(lastChar) == rule.vowel else { continue }
                    let expandedKey = consonantPrefix + suffixKey
                    let expandedValue = kanaOutput + rule.suffix
                    suffixExpansions[expandedKey] = expandedValue
                }
            }
        }

        // マージ: base < suffix < explicit（論理キー空間）
        var result = base
        for (k, v) in suffixExpansions {
            result[k] = v
        }
        if let explicit = explicitMappings {
            for (k, v) in explicit where !k.hasPrefix("_comment") {
                result[k] = v
            }
        }

        return result.isEmpty ? nil : result
    }

    /// 入力方式の振る舞いの種類
    public enum InputBehavior: Sendable {
        /// key.characters ベースの逐次入力（ローマ字等）
        ///
        /// `characterMap` で半角→全角変換を行う（現 h2zMap に相当）。
        /// key.characters は UIKit がキーボードレイアウトを解決済みのため、
        /// US/JIS の違いは characterMap のデータだけで吸収できる。
        case sequential(characterMap: [Character: Character])

        /// HID コードベースの同時打鍵入力（薙刀式、NICOLA 等）
        ///
        /// 物理キー位置で入力を判定する。SimultaneousKeyBuffer と組み合わせて使う。
        case chord(config: ChordConfig)
    }

    /// シフトキー設定（同時打鍵方式のセンターシフト / 親指シフト）
    ///
    /// シフトキーは先行出力なし（タイマー待機→同時打鍵判定）の特殊動作をするキー。
    /// 薙刀式では Space（1個）、NICOLA では左親指・右親指（2個）が該当する。
    public struct ShiftKeyConfig: Sendable {
        /// シフトキーの ChordKey 識別子
        public let key: ChordKey
        /// 単打時のフォールバックアクション（nil の場合はアクションなし）
        public let singleTapAction: KeyAction?
    }

    /// 同時打鍵設定
    public struct ChordConfig: Sendable {
        /// 物理キー（HID キーコード）→ 内部キー ID の変換テーブル
        public let hidToKey: [HIDKeyCode: ChordKey]

        /// キーの組合せビットマスク → 出力文字列
        public let lookupTable: [UInt64: String]

        /// キーの組合せビットマスク → 特殊アクション（KeyAction 統一）
        public let specialActions: [UInt64: KeyAction]

        /// 同時打鍵判定ウィンドウ（秒）
        public let simultaneousWindow: TimeInterval

        /// 英数モード用の lookup テーブル（nil の場合は英数モードなし）
        public let englishLookupTable: [UInt64: String]?

        /// 英数モード用の特殊アクションテーブル（nil の場合は英数モードなし）
        public let englishSpecialActions: [UInt64: KeyAction]?

        /// シフトキー定義（1個 or 2個）
        ///
        /// 薙刀式: `[.space]`（センターシフト）
        /// NICOLA: `[.leftThumb, .rightThumb]`（左右親指シフト）
        /// 空配列の場合はシフトキーなし（全キーが文字キー扱い）。
        public let shiftKeys: [ShiftKeyConfig]
    }
}

/// 制御キーバインド定義
///
/// Emacs 風ショートカット（Ctrl+キー）のマッピングを定義する。
/// 標準制御キー（Enter, Escape, Space, BS, 矢印, 数字）は
/// KeyRouter 内でハードコードされる（全入力方式で共通のため）。
public struct ControlBindings: Sendable {

    /// Ctrl+キー → KeyAction のマッピング
    public var emacsBindings: [HIDKeyCode: KeyAction]

    /// Ctrl+; の特殊処理（UIKeyboardHIDUsage にシンボル名がないため）
    public var ctrlSemicolonAction: KeyAction?

    /// Ctrl+: の特殊処理（Shift+; で入力されるため、semicolonAction と同じく別枠）
    public var ctrlColonAction: KeyAction?

    /// デフォルトの Emacs 風バインド（macOS 標準「ことえり」準拠）
    public static let `default` = ControlBindings(
        emacsBindings: [
            HIDKeyCode.keyboardH: .deleteBack,         // Ctrl+H = Backspace
            HIDKeyCode.keyboardM: .confirm,            // Ctrl+M = Enter
            HIDKeyCode.keyboardP: .moveUp,             // Ctrl+P = Up（前の候補）
            HIDKeyCode.keyboardN: .moveDown,           // Ctrl+N = Down（次の候補 / 変換開始）
            HIDKeyCode.keyboardF: .moveRight,          // Ctrl+F = Right（selecting 中: 確定）
            HIDKeyCode.keyboardG: .cancel,             // Ctrl+G = Escape
            HIDKeyCode.keyboardI: .editSegmentLeft,    // Ctrl+I = 文節区切り左
            HIDKeyCode.keyboardJ: .confirmHiragana,    // Ctrl+J = ひらがな確定
            HIDKeyCode.keyboardK: .confirmKatakana,    // Ctrl+K = カタカナ確定
            HIDKeyCode.keyboardL: .confirmHalfWidthKatakana, // Ctrl+L = 半角カタカナ確定（ことえり準拠）
            HIDKeyCode.keyboardO: .editSegmentRight,   // Ctrl+O = 文節区切り右
        ],
        ctrlSemicolonAction: .confirmFullWidthRoman, // Ctrl+; = 全角英数確定（ことえり準拠）
        ctrlColonAction: .confirmHalfWidthRoman      // Ctrl+: = 半角英数確定（ことえり準拠）
    )
}
