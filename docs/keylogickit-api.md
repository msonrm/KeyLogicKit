# KeyLogicKit Public API リファレンス

KeyLogicKit を外部アプリから利用する際の公開 API 一覧。

**重要: public API を追加・変更・削除した場合は、このファイルも必ず更新すること。**

## InputManager — 変換エンジン（@Observable クラス）

### 型定義

| 型 | 説明 |
|---|---|
| `ConversionState` enum | `.composing`, `.previewing`, `.selecting` |
| `InputMode` enum | `.japanese`, `.english` |
| `InputMethod` enum | `.sequential`, `.chord(name: String)`, `.directEnglish`（`isChord: Bool` 付き） |
| `DisplaySegmentFocus` enum | `.confirmed`, `.focused`, `.unfocused` |
| `DisplaySegment` struct | `text: String`, `focus: DisplaySegmentFocus` |
| `AdditionalCandidate` struct | `text: String`, `annotation: String` |
| `ConversionForm` enum | `.hiragana`, `.katakana`, `.halfWidthKatakana`, `.fullWidthRoman`, `.halfWidthRoman` |
| `DeleteResult` enum | `.deleted`, `.empty`（composing テキストが空になった場合） |
| `ConfirmResult` struct | `text: String`, `isFullyConfirmed: Bool` |

### 初期化

```swift
init()  // 辞書変換エンジンを初期化
```

### 状態プロパティ（読み取り専用）

| プロパティ | 型 | 説明 |
|---|---|---|
| `state` | `ConversionState` | 現在の変換状態 |
| `inputMode` | `InputMode` | 入力モード（日本語/英語） |
| `displaySegments` | `[DisplaySegment]` | markedText の表示セグメント |
| `displayText` | `String` | markedText 全体の文字列 |
| `candidates` | `[Candidate]` | 変換候補配列 |
| `candidateTexts` | `[String]` | 候補テキスト配列 |
| `selectedCandidateIndex` | `Int` | 選択中の候補インデックス |
| `visibleCandidateRange` | `ClosedRange<Int>` | 表示中の候補ウィンドウ範囲 |
| `visibleCandidateTexts` | `[String]` | ウィンドウ内の候補テキスト |
| `selectedIndexInWindow` | `Int` | ウィンドウ内の選択位置（0-based） |
| `isEmpty` | `Bool` | 入力が空か |
| `previewText` | `String?` | previewing 時の第1候補テキスト |
| `isAdditionalCandidateSelected` | `Bool` | 追加候補が選択中か |
| `selectedAdditionalCandidateIndex` | `Int` | 追加候補内の選択位置 |
| `visibleAdditionalCandidates` | `[AdditionalCandidate]` | 表示中の追加候補 |
| `confirmedPrefix` | `String` | 部分確定済みテキスト |
| `liveConversionText` | `String?` | ライブ変換結果（nil=ひらがな表示） |
| `editorFontSize` | `CGFloat` | エディタフォントサイズ |
| `leftSideContext` | `String` | 直前の確定テキスト（文脈用） |
| `predictionCandidates` | `[PredictionItem]` | 予測候補 |
| `activeInputMappings` | `[String: String]?` | アクティブな入力テーブル |
| `pendingBufferText` | `String` | 逐次バッファの仮解決テキスト |

### 設定プロパティ（読み書き）

| プロパティ | 型 | デフォルト | 説明 |
|---|---|---|---|
| `inputMethod` | `InputMethod` | `.sequential` | 入力方式 |
| `liveConversionEnabled` | `Bool` | `false` | ライブ変換 |
| `predictionEnabled` | `Bool` | `false` | 予測変換 |
| `dynamicShortcuts` | `[DynamicShortcut]` | 日時ショートカット | 動的ショートカット |
| `dynamicShortcutsEnabled` | `Bool` | `true` | 動的ショートカット有効化 |
| `simultaneousWindow` | `TimeInterval` | `0.080` | 同時打鍵判定窓（秒） |
| `fullControlMode` | `Bool` | `true` | キー入力完全制御モード（システム IME 切替を無効化） |
| `zenzaiWeightURL` | `URL?` | `nil` | Zenzai モデル URL（DI） |

### 入力操作メソッド

| メソッド | 説明 |
|---|---|
| `setInputMode(_ mode: InputMode)` | 入力モード設定 |
| `setEditorFontSize(_ size: CGFloat)` | フォントサイズ設定 |
| `setLeftSideContext(_ context: String)` | 左側コンテキスト設定（最大30文字、カーソル移動・ファイル開封時用） |
| `updateInputMappings(_ mappings: [String: String]?)` | 入力テーブル設定 |
| `recordChordKey(_ key: ChordKey)` | chord キーの QWERTY 文字を蓄積（英数候補用） |
| `appendDirectKana(_ kana: String)` | かな文字を直接追加（trie 非経由） |
| `handleSequentialInput(_ character: String)` | 逐次入力（greedy longest-match） |
| `replaceDirectKana(count: Int, with newKana: String)` | 直前 N 文字を差し替え（同時打鍵巻き戻し） |
| `deleteBackward() -> DeleteResult` | 1文字削除 |
| `editSegment(count: Int)` | 文節区切り編集（正=右拡張、負=左縮小） |

### 変換操作メソッド

| メソッド | 説明 |
|---|---|
| `requestConversion(forceSelecting: Bool = false)` | 変換開始（Space） |
| `selectNextCandidate()` | 次の候補（Space/↓） |
| `selectPrevCandidate()` | 前の候補（↑、先頭で追加候補を展開） |
| `selectCandidateInWindow(at: Int) -> ConfirmResult?` | 数字キーで候補選択（1-9） |
| `confirmConversion() -> String` | 選択中の候補を確定 |
| `confirmAll() -> String` | 全文確定 |
| `confirmWithForm(_ form: ConversionForm) -> String` | 指定形式で確定（Ctrl+J/K/L/;/:） |
| `cancelConversion()` | 変換キャンセル（全リセット） |
| `returnToComposing()` | composing に戻る（Escape） |

## KeyRouter — キールーティング（struct）

```swift
init(definition: KeymapDefinition)
func route(_ event: KeyEvent, isComposing: Bool, state: InputManager.ConversionState,
           isDirectEnglishMode: Bool = false) -> KeyAction
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `definition` | `KeymapDefinition` | キーマップ定義 |

## KeyAction — IME アクション enum

| ケース | 説明 |
|---|---|
| `.printable(Character)` | 逐次入力文字 |
| `.convert` | 変換/次候補（Space） |
| `.convertPrev` | 前候補（Shift+Space） |
| `.confirm` | 確定（Enter/Tab） |
| `.cancel` | キャンセル（Escape） |
| `.deleteBack` | 後退削除（BS） |
| `.moveLeft/Right/Up/Down` | カーソル移動 |
| `.editSegmentLeft/Right` | 文節編集（Shift+矢印） |
| `.selectCandidate(Int)` | 数字キー候補選択 |
| `.confirmHiragana/Katakana/HalfWidthKatakana` | 形式指定確定 |
| `.confirmFullWidthRoman/HalfWidthRoman` | 英数形式確定 |
| `.chordInput(ChordKey)` | 同時打鍵文字キー |
| `.chordShiftDown(ChordKey)` | 同時打鍵シフトキー |
| `.insertAndConfirm(String)` | 挿入+確定（句読点等） |
| `.switchToEnglish` | 英数直接入力に切替 |
| `.switchToJapanese` | 日本語入力に復帰 |
| `.toggleInputMode` | 日本語↔英数トグル |
| `.directInsert(String)` | 英数直接挿入 |
| `.moveSentenceStart` | 文頭へ移動（Option+←） |
| `.moveSentenceEnd` | 文末へ移動（Option+→） |
| `.swapSentenceUp` | 文を前の文と入れ替え（Option+↑） |
| `.swapSentenceDown` | 文を次の文と入れ替え（Option+↓） |
| `.smartSelectExpand` | スマート選択拡大（Shift+Option+→） |
| `.smartSelectShrink` | スマート選択縮小（Shift+Option+←） |
| `.selectSentenceUp` | 文選択を上に拡張（Shift+Option+↑） |
| `.selectSentenceDown` | 文選択を下に拡張（Shift+Option+↓） |
| `.pass` | UIKit に委任 |

## SentenceBoundary — 文境界検出ユーティリティ（enum）

日本語テキストの文・句・カッコ境界を検出する。UIKit 非依存。

### 定数

| 定数 | 型 | 説明 |
|---|---|---|
| `sentenceEnders` | `Set<Character>` | 文末記号（。！？!?） |
| `closingBrackets` | `Set<Character>` | 閉じカッコ（」』）】〉》)]\}>"'） |
| `clauseDelimiters` | `Set<Character>` | 句区切り（、,） |
| `bracketPairs` | `[(open:close:)]` | カッコペア（日本語+ASCII） |

### メソッド

```swift
static func sentenceRange(in text: String, at position: String.Index) -> Range<String.Index>
static func sentenceStart(in text: String, at position: String.Index) -> String.Index
static func previousSentenceStart(in text: String, before position: String.Index) -> String.Index
static func nextSentenceEnd(in text: String, after position: String.Index) -> String.Index
static func clauseRange(in text: String, at position: String.Index,
                         within sentence: Range<String.Index>) -> Range<String.Index>
static func enclosingBrackets(in text: String, at position: String.Index)
    -> (inner: Range<String.Index>, outer: Range<String.Index>)?
```

## SmartSelectionLevel — スマート選択レベル（enum）

| ケース | 説明 |
|---|---|
| `.none` | 選択なし |
| `.clause` | 句（読点区切り） |
| `.insideBrackets` | カッコ内側 |
| `.includingBrackets` | カッコを含む |
| `.sentence` | 文全体 |

## SmartSelectionState — スマート選択状態（struct）

| プロパティ | 型 | 説明 |
|---|---|---|
| `level` | `SmartSelectionLevel` | 現在の拡大レベル |
| `origin` | `String.Index?` | 起点位置 |
| `currentRange` | `Range<String.Index>?` | 現在の選択範囲 |

| メソッド | 説明 |
|---|---|
| `expand(in:cursor:)` | 次レベルに拡大（範囲が同じならスキップ） |
| `shrink(in:)` | 前レベルに縮小 |
| `reset()` | 状態リセット |

## KeyEvent — プラットフォーム非依存キーイベント（struct）

```swift
init(keyCode: HIDKeyCode, characters: String, modifierFlags: KeyModifierFlags)
```

| プロパティ | 型 |
|---|---|
| `keyCode` | `HIDKeyCode` |
| `characters` | `String` |
| `modifierFlags` | `KeyModifierFlags` |

## HIDKeyCode — USB HID キーコード（struct, RawRepresentable）

`rawValue: UInt32`。主要定数:

- アルファベット: `.keyboardA` 〜 `.keyboardZ`
- 数字: `.keyboard1` 〜 `.keyboard0`
- 制御: `.keyboardReturnOrEnter`, `.keyboardEscape`, `.keyboardDeleteOrBackspace`, `.keyboardTab`, `.keyboardSpacebar`
- 記号: `.keyboardHyphen`, `.keyboardEqualSign`, `.keyboardOpenBracket`, `.keyboardCloseBracket`, `.keyboardBackslash`, `.keyboardSemicolon`, `.keyboardQuote`, `.keyboardGraveAccentAndTilde`, `.keyboardComma`, `.keyboardPeriod`, `.keyboardSlash`
- 矢印: `.keyboardLeftArrow`, `.keyboardRightArrow`, `.keyboardUpArrow`, `.keyboardDownArrow`
- ファンクション: `.keyboardF1` 〜 `.keyboardF12`
- JIS 固有: `.keyboardInternational1` 〜 `.keyboardInternational5`, `.keyboardLANG1`, `.keyboardLANG2`
- その他: `.keyboardCapsLock`

静的プロパティ:

| プロパティ | 型 | 説明 |
|---|---|---|
| `systemIMETriggerKeys` | `Set<HIDKeyCode>` | システム IME 切替トリガーキー（LANG1/2, CAPS LOCK, 変換/無変換, ひらがな/カタカナ） |

## KeyModifierFlags — 修飾キーフラグ（OptionSet）

`.shift`, `.control`, `.alternate`, `.command`

## KeymapDefinition — キーマップ定義（struct, Codable）

### メタデータ

| プロパティ | 型 | 説明 |
|---|---|---|
| `formatVersion` | `String` | フォーマットバージョン（`"1.0"`） |
| `name` | `String` | 表示名 |
| `description` | `String?` | 説明 |
| `author` | `String?` | 作者 |
| `license` | `String?` | SPDX ライセンス識別子 |
| `keyboardLayout` | `String` | 物理配列（`"us"`, `"jis"`） |
| `targetScript` | `String?` | 出力スクリプト |

### 入力動作

| プロパティ | 型 | 説明 |
|---|---|---|
| `behavior` | `InputBehavior` | `.sequential(characterMap:)` / `.chord(config:)` |
| `controlBindings` | `ControlBindings` | Ctrl+キーバインド |
| `inputBase` | `String?` | ベーステーブル（`"romaji"` / nil） |
| `keyRemap` | `[String: String]?` | 物理→論理キーリマップ |
| `suffixRules` | `[String: SuffixRule]?` | サフィックス展開ルール |
| `inputMappings` | `[String: String]?` | キーシーケンス→かなマッピング |
| `explicitInputMappings` | `[String: String]?` | 展開前のオリジナルマッピング |
| `prefixShiftKeys` | `[Character]?` | 前置シフトキー |
| `modeKeys` | `[HIDKeyCode: KeyAction]?` | モード切替キー（英数/かな切替） |
| `extensions` | `[String: String]?` | アプリ固有拡張 |

### 関連型

- `InputBehavior` enum: `.sequential(characterMap: [Character: Character])`, `.chord(config: ChordConfig)`
- `ChordConfig` struct: `hidToKey`, `lookupTable`, `specialActions`, `simultaneousWindow`, `englishLookupTable?`, `englishSpecialActions?`, `shiftKeys`
- `ShiftKeyConfig` struct: `key: ChordKey`, `singleTapAction: KeyAction?`
- `SuffixRule` struct: `vowel: String`, `suffix: String`
- `ControlBindings` struct: `emacsBindings`, `ctrlSemicolonAction?`, `ctrlColonAction?`（`static let default` あり）

### メソッド

```swift
static func expandInputMappings(inputBase:suffixRules:explicitMappings:) -> [String: String]?
static let currentFormatVersion = "1.0"
```

## KeymapStore — ファイル I/O（enum）

```swift
static var keymapsDirectory: URL
static func encode(_ definition: KeymapDefinition) throws -> Data
static func decode(from data: Data) throws -> KeymapDefinition
static func load(from url: URL) throws -> KeymapDefinition
static func save(_ definition: KeymapDefinition, to url: URL) throws
static func listCustomKeymaps() -> [URL]
```

## KeymapManager — キーマップ管理（@Observable クラス）

```swift
init()
init(configuration: KeymapManagerConfiguration)
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `entries` | `[KeymapEntry]` | 全キーマップエントリ |
| `selectedEntryID` | `String` | 選択中の ID |
| `selectedEntryName` | `String` | 選択中の表示名 |
| `lastError` | `String?` | エラーメッセージ |

| メソッド | 説明 |
|---|---|
| `reload()` | 一覧再読み込み |
| `loadSelectedDefinition() -> KeymapDefinition?` | 選択中のキーマップ読み込み |
| `loadDefinition(for: String) -> KeymapDefinition?` | ID 指定読み込み |
| `importKeymap(from: URL) throws` | インポート |
| `deleteCustomKeymap(entryID: String) throws` | カスタムキーマップ削除 |

関連型: `KeymapManagerConfiguration` struct（`additionalKeymaps`, `defaultKeymapID`）、`KeymapEntry` struct（`id`, `name`, `isBuiltIn`）

## DefaultKeymaps — 組み込みキーマップ（enum）

| プロパティ/メソッド | 型 | 説明 |
|---|---|---|
| `romajiUS` | `KeymapDefinition` | 標準ローマ字（US） |
| `standardRomajiTable` | `[String: String]` | ベースローマ字テーブル |
| `allKeymaps` | `[(id: String, definition: KeymapDefinition)]` | 全組み込みキーマップ |
| `h2zMapUS` | `[Character: Character]` | 半角→全角マップ（US） |
| `loadBundleKeymap(_ name: String) -> KeymapDefinition?` | Bundle からキーマップ読み込み |

## ChordKey — 同時打鍵キー識別子（enum, Codable, Hashable）

33 キー: `.Q`〜`.P`, `.A`〜`.semicolon`, `.Z`〜`.slash`, `.space`, `.leftThumb`, `.rightThumb`

| プロパティ | 型 | 説明 |
|---|---|---|
| `bit` | `UInt64` | ビットマスク値 |
| `character` | `Character?` | QWERTY 文字（逆引き） |
| `hand` | `Hand` | `.left`, `.right`, `.thumb` |
| `finger` | `Finger` | 指名（日本語、CaseIterable） |
| `keyRow` | `Row` | `.upper`, `.home`, `.lower`, `.thumb` |

静的プロパティ: `topRow`, `middleRow`, `bottomRow`, `fromCharacter: [Character: ChordKey]`

## SimultaneousKeyBuffer — 同時打鍵バッファ（@MainActor クラス）

```swift
init()
func keyDown(_ key: ChordKey)
func keyUp(_ key: ChordKey)
func reset()
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `simultaneousWindow` | `TimeInterval` | 判定窓（秒、デフォルト 0.080） |
| `physicalShift` | `Bool` | 物理 Shift フラグ（英数大文字用） |
| `lookupFunction` | `(UInt64) -> String?` | 文字出力テーブル |
| `specialActionFunction` | `(UInt64) -> KeyAction?` | 特殊アクションテーブル |
| `shiftKeyConfigs` | `[ChordKey: KeyAction?]` | シフトキー設定 |
| `onOutput` | `((String, Int) -> Void)?` | テキスト出力コールバック（text, replaceCount） |
| `onShiftSingle` | `((KeyAction) -> Void)?` | シフト単打コールバック |
| `onSpecialAction` | `((KeyAction) -> Void)?` | 特殊アクションコールバック |

## DynamicShortcut — 動的ショートカット（struct）

```swift
init(reading: String, annotation: String, resolve: @escaping @Sendable () -> String)
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `reading` | `String` | 読み（例: "きょう"） |
| `annotation` | `String` | 注釈（例: "今日の日付"） |
| `resolve` | `() -> String` | テキスト生成クロージャ |

組み込み: `BuiltInShortcuts.dateTimeShortcuts`（きょう/あした/きのう/いま）

## EditorStyle — エディタ表示スタイル（struct）

```swift
init(font: UIFont = .monospacedSystemFont(ofSize: 18, weight: .regular),
     lineSpacing: CGFloat = 0,
     textAlignment: NSTextAlignment = .natural,
     showInvisibles: Bool = false)
```

| プロパティ | 型 | デフォルト |
|---|---|---|
| `font` | `UIFont` | monospacedSystemFont 18pt |
| `lineSpacing` | `CGFloat` | `0` |
| `textAlignment` | `NSTextAlignment` | `.natural` |
| `showInvisibles` | `Bool` | `false` |
| `typingAttributes` | `[NSAttributedString.Key: Any]` | 計算プロパティ |

## IMETextView — UITextView サブクラス

```swift
convenience init(useInvisibleCharLayout: Bool)
func setSimultaneousWindow(_ window: TimeInterval)
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `inputManager` | `InputManager?` | 変換エンジン（注入） |
| `editorStyle` | `EditorStyle` | 表示スタイル |
| `keyRouter` | `KeyRouter` | キールーター |
| `onKeyEvent` | `((KeyEventInfo) -> Void)?` | キーイベントログ |
| `onKeyDown` | `((HIDKeyCode, Date) -> Void)?` | キーダウン通知 |
| `onKeyUp` | `((HIDKeyCode, Date) -> Void)?` | キーアップ通知 |
| `onEnglishModeChange` | `((Bool) -> Void)?` | 英数モード変更通知 |
| `onCaretRectChange` | `((CGRect) -> Void)?` | キャレット位置変更通知 |

## IMETextViewRepresentable — SwiftUI ラッパー

```swift
init(inputManager: InputManager, keyRouter: KeyRouter, editorStyle: EditorStyle = .init(),
     text: Binding<String> = .constant(""), cursorLocation: Binding<Int> = .constant(0),
     selectionLength: Binding<Int> = .constant(0), scrollRevision: Int = 0,
     onKeyEvent: ((IMETextView.KeyEventInfo) -> Void)? = nil,
     onKeyDown: ((HIDKeyCode, Date) -> Void)? = nil,
     onKeyUp: ((HIDKeyCode, Date) -> Void)? = nil,
     onEnglishModeChange: ((Bool) -> Void)? = nil,
     onCaretRectChange: ((CGRect) -> Void)? = nil,
     onScrollRequest: ((IMETextView, Int) -> Void)? = nil)
```

## CandidatePopup — 変換候補ポップアップ（SwiftUI View）

```swift
init(additionalCandidates: [InputManager.AdditionalCandidate],
     isAdditionalCandidateSelected: Bool, selectedAdditionalCandidateIndex: Int,
     candidates: [String], selectedIndex: Int,
     font: Font = .system(size: 15), fontSize: CGFloat = 15,
     anchor: CGRect? = nil, bounds: CGSize? = nil)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `anchor` | `CGRect?` | カーソル矩形（配置のアンカー）。`bounds` と共に指定すると自動配置が有効になる |
| `bounds` | `CGSize?` | 表示領域のサイズ（overlay の親ビューサイズ） |

自動配置ルール（`anchor` と `bounds` の両方が非 nil の場合）:
- デフォルト: `anchor.maxY` の直下に表示
- 垂直フリップ: ポップアップが `bounds.height` を超える場合、`anchor.minY` の直上に反転
- 水平クランプ: ポップアップが `bounds.width` を超える場合、右端に収まるよう左にずらす
- 左端・上端は 0 でクランプ

## PredictionPopup — 予測候補ポップアップ（SwiftUI View）

```swift
init(predictions: [PredictionItem], font: Font,
     anchor: CGRect? = nil, bounds: CGSize? = nil)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `anchor` | `CGRect?` | カーソル矩形（配置のアンカー）。`bounds` と共に指定すると自動配置が有効になる |
| `bounds` | `CGSize?` | 表示領域のサイズ（overlay の親ビューサイズ） |

自動配置ルールは CandidatePopup と同一。

関連型: `PredictionItem` struct（`text: String`, `annotation: String?`）
