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
| `SpaceWidth` enum | `.fullWidth`, `.halfWidth`（`CaseIterable`, `label: String` 付き） |
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
| `selectedPredictionIndex` | `Int?` | Tab で巡回選択中の予測候補インデックス |
| `activeKeymap` | `ExpandedKeymap?` | 事前展開済みキーマップ |
| `activeInputMappings` | `[String: String]?` | アクティブな入力テーブル（`activeKeymap` から導出） |
| `pendingBufferText` | `String` | 逐次バッファの仮解決テキスト |

### 設定プロパティ（読み書き）

| プロパティ | 型 | デフォルト | 説明 |
|---|---|---|---|
| `inputMethod` | `InputMethod` | `.sequential` | 入力方式 |
| `liveConversionEnabled` | `Bool` | `false` | ライブ変換 |
| `predictionEnabled` | `Bool` | `false` | 予測変換 |
| `dynamicShortcuts` | `[DynamicShortcut]` | 日時ショートカット | 動的ショートカット |
| `dynamicShortcutsEnabled` | `Bool` | `true` | 動的ショートカット有効化 |
| `japaneseSpaceWidth` | `SpaceWidth` | `.fullWidth` | 日本語モード時のスペース幅 |
| `simultaneousWindow` | `TimeInterval` | `0.080` | 同時打鍵判定窓（秒） |
| `fullControlMode` | `Bool` | `true` | キー入力完全制御モード（システム IME 切替を無効化） |
| `zenzaiWeightURL` | `URL?` | `nil` | Zenzai モデル URL（DI） |

### 入力操作メソッド

| メソッド | 説明 |
|---|---|
| `spaceCharacter(shifted: Bool) -> String` | 現在のモード+設定に応じたスペース文字（日本語=設定に従い全角/半角、Shift で逆転） |
| `setInputMode(_ mode: InputMode)` | 入力モード設定 |
| `setEditorFontSize(_ size: CGFloat)` | フォントサイズ設定 |
| `setLeftSideContext(_ context: String)` | 左側コンテキスト設定（最大30文字、カーソル移動・ファイル開封時用） |
| `updateKeymap(_ keymap: ExpandedKeymap?)` | 事前展開済みキーマップ設定（nil でクリア） |
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
| `selectNextPrediction()` | 予測候補を Tab で巡回選択 |
| `acceptPrediction(at: Int) -> String?` | 予測候補を確定（Enter） |
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
| `.insertSpace(shifted: Bool)` | 確定スペース挿入（idle 時、半角/全角は InputManager 設定に従う。Shift で逆転） |
| `.directInsert(String)` | 英数直接挿入 |
| `.moveSentenceStart` | 文頭へ移動（Option+←） |
| `.moveSentenceEnd` | 文末へ移動（Option+→） |
| `.swapSentenceUp` | 文を前の文と入れ替え（Option+↑） |
| `.swapSentenceDown` | 文を次の文と入れ替え（Option+↓） |
| `.smartSelectExpand` | スマート選択拡大（Shift+Option+→） |
| `.smartSelectShrink` | スマート選択縮小（Shift+Option+←） |
| `.selectSentenceUp` | 文選択を上に拡張（Shift+Option+↑、未選択なら現在の文を選択） |
| `.selectSentenceDown` | 文選択を下に拡張（Shift+Option+↓、未選択なら現在の文を選択） |
| `.pass` | UIKit に委任 |

## SentenceBoundary — 文境界検出ユーティリティ（enum）

日本語テキストの文・句・カッコ境界を検出する。UIKit 非依存。

カッコ内外でスキャン範囲を自動切り替え:
- カッコ外: テキスト全体をスキャン。カッコ内の文末記号は無視（カッコをスキップ）
- カッコ内: カッコの内側に限定。閉じカッコ直前が暗黙の文末

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
static func previousSentenceStart(in text: String, before position: String.Index) -> String.Index
static func nextSentenceEnd(in text: String, after position: String.Index) -> String.Index
static func clauseRange(in text: String, at position: String.Index,
                         within sentence: Range<String.Index>) -> Range<String.Index>
static func enclosingBrackets(in text: String, at position: String.Index)
    -> (inner: Range<String.Index>, outer: Range<String.Index>)?
```

## BlockRangeProvider — ブロック境界検出型（typealias）

```swift
public typealias BlockRangeProvider = @Sendable (String, String.Index) -> Range<String.Index>?
```

アプリ固有のブロック境界（シーン区切り、段落グループ等）を検出するクロージャ。
`nil` を返すと `.block` レベルはスキップされる。

## SmartSelectionLevel — スマート選択レベル（enum）

| ケース | 説明 |
|---|---|
| `.none` | 選択なし |
| `.insideBrackets` | カッコ内側 |
| `.includingBrackets` | カッコを含む |
| `.sentence` | 文全体 |
| `.block` | ブロック（境界定義はアプリ側から注入） |

## SmartSelectionState — スマート選択状態（struct）

```swift
init(blockRangeProvider: BlockRangeProvider? = nil)
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `blockRangeProvider` | `BlockRangeProvider?` | ブロック境界検出（アプリ側から注入） |
| `level` | `SmartSelectionLevel` | 現在の拡大レベル |
| `origin` | `String.Index?` | 起点位置 |
| `currentRange` | `Range<String.Index>?` | 現在の選択範囲 |

| メソッド | 説明 |
|---|---|
| `expand(in:cursor:)` | 次レベルに拡大（範囲が包含される場合もスキップ） |
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

## KeyModifierFlags — 修飾キーフラグ（OptionSet, Hashable）

`.shift`, `.control`, `.alternate`, `.command`

## KeymapDefinition — キーマップ定義（struct, Codable）

### メタデータ

| プロパティ | 型 | 説明 |
|---|---|---|
| `formatVersion` | `String` | フォーマットバージョン（`"1.0"`） |
| `name` | `String` | 表示名 |
| `description` | `String?` | 説明 |
| `author` | `String?` | 配列の原作者 |
| `contributor` | `[String]?` | 派生版の改変者 |
| `basedOn` | `String?` | 派生元の配列名 |
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
| `modeKeys` | `[ModeKeyTrigger: KeyAction]?` | モード切替キー（修飾キー付き対応、英数/かな切替） |
| `extensions` | `[String: String]?` | アプリ固有拡張 |

### 関連型

- `InputBehavior` enum: `.sequential(characterMap: [Character: Character])`, `.chord(config: ChordConfig)`
- `ChordConfig` struct: `hidToKey`, `lookupTable`, `specialActions`, `simultaneousWindow`, `englishLookupTable?`, `englishSpecialActions?`, `shiftKeys`
- `ShiftKeyConfig` struct: `key: ChordKey`, `singleTapAction: KeyAction?`
- `ModeKeyTrigger` struct: `keyCode: HIDKeyCode`, `modifiers: KeyModifierFlags`（空 = 修飾キー不問）。`Hashable` 準拠
- `SuffixRule` struct: `vowel: String`, `suffix: String`
- `ControlBindings` struct: `emacsBindings`, `ctrlSemicolonAction?`, `ctrlColonAction?`（`static let default` あり）

### メソッド

```swift
static func expandInputMappings(inputBase:suffixRules:explicitMappings:) -> [String: String]?
static let currentFormatVersion = "1.0"
```

## ExpandedKeymap — 事前展開済みキーマップ（struct, Sendable）

`KeymapDefinition` から一度だけ構築し、`InputManager.updateKeymap()` で適用する。
ランタイムでのプレフィックスセット構築や `_comment` フィルタリングを排除する。

```swift
init(definition: KeymapDefinition)
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `definition` | `KeymapDefinition` | 元のキーマップ定義 |
| `inputMappings` | `[String: String]?` | マージ済み入力マッピング（`_comment` フィルタ済み） |
| `prefixSet` | `Set<String>` | greedy longest-match 用プレフィックス集合 |
| `characterMap` | `[Character: Character]` | 半角→全角変換テーブル（sequential のみ） |
| `keyRemap` | `[Character: Character]` | キーリマップ（物理→論理） |
| `chordData` | `ExpandedChordData?` | Chord 事前展開データ（chord のみ） |

## ExpandedChordData — Chord 事前展開データ（struct, Sendable）

`ChordConfig` から構築される Chord 配列のルックアップデータ。

| プロパティ | 型 | 説明 |
|---|---|---|
| `hidToChordKey` | `[HIDKeyCode: ChordKey]` | HID→ChordKey 変換 |
| `lookupTable` | `[UInt64: String]` | ビットマスク→出力文字列 |
| `specialActions` | `[UInt64: KeyAction]` | ビットマスク→特殊アクション |
| `shiftKeyConfigs` | `[ChordKey: KeyAction?]` | シフトキー→単打時アクション |
| `simultaneousWindow` | `TimeInterval` | 同時打鍵判定窓（秒） |
| `englishLookupTable` | `[UInt64: String]?` | 英語モード用ルックアップ |
| `englishSpecialActions` | `[UInt64: KeyAction]?` | 英語モード用特殊アクション |

## ModeKeyTriggerCoding — モードキー文字列変換（enum）

`ModeKeyTrigger` と `"ctrl+space"` 形式文字列の相互変換。

```swift
static func parse(_ string: String) -> KeymapDefinition.ModeKeyTrigger?
static func format(_ trigger: KeymapDefinition.ModeKeyTrigger) -> String?
```

- `parse("ctrl+space")` → `ModeKeyTrigger(keyCode: .keyboardSpacebar, modifiers: .control)`
- `format(trigger)` → `"ctrl+space"`

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
| `romajiJIS` | `KeymapDefinition` | 標準ローマ字（JIS） |
| `standardRomajiTable` | `[String: String]` | ベースローマ字テーブル（標準 IME 準拠、外来音・小書き含む） |
| `allKeymaps` | `[(id: String, definition: KeymapDefinition)]` | 全組み込みキーマップ（US/JIS 各配列） |
| `h2zMapUS` | `[Character: Character]` | 半角→全角マップ（US） |
| `loadBundleKeymap(_ name: String) -> KeymapDefinition?` | Bundle からキーマップ読み込み |

`allKeymaps` に含まれる組み込みキーマップ:
- `builtin:romaji_us` / `builtin:romaji_jis` — ローマ字
- `builtin:azik_us` / `builtin:azik_jis` — AZIK
- `builtin:tsuki2-263_us` / `builtin:tsuki2-263_jis` — 月配列2-263
- `builtin:nicola_us` / `builtin:nicola_jis` — NICOLA
- `builtin:romaji_colemak_us` / `builtin:romaji_colemak_jis` — ローマ字(Colemak)
- `builtin:shingeta_us` / `builtin:shingeta_jis` — 新下駄配列
- `builtin:tsubame_us` / `builtin:tsubame_jis` — つばめ配列

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

## SimultaneousKeyBuffer — 同時打鍵バッファ（@MainActor クラス、pressesEnded ベース）

押下中キーの集合（heldKeys）で同時打鍵を判定する。タイマー不要。
- 単打: keyUp（全キーリリース）で出力
- chord: 2/3キー目の keyDown で即出力
- シフトホールド: chord 確定後にシフトキーのみ残存 → shiftMode に自動遷移

```swift
init()
func keyDown(_ key: ChordKey)
func keyUp(_ key: ChordKey)
func reset()
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `simultaneousWindow` | `TimeInterval` | idle ゲーティング閾値（秒）。直前の確定からこの時間以内のキーは chord 判定をスキップ（ZMK `require-prior-idle-ms` 相当） |
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
     showInvisibles: Bool = false,
     scrollOffLines: Int = 5)
```

| プロパティ | 型 | デフォルト | 説明 |
|---|---|---|---|
| `font` | `UIFont` | monospacedSystemFont 18pt | |
| `lineSpacing` | `CGFloat` | `0` | |
| `textAlignment` | `NSTextAlignment` | `.natural` | |
| `showInvisibles` | `Bool` | `false` | |
| `scrollOffLines` | `Int` | `5` | Vim の scrolloff 相当。カーソルが上端・下端からこの行数以内に入らないようスクロールを自動調整 |
| `typingAttributes` | `[NSAttributedString.Key: Any]` | 計算プロパティ | |

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
| `onFittingCharsPerLineChange` | `((Int) -> Void)?` | テキストコンテナに1行で収まる全角文字数の変化通知（コンテナ幅・フォント変更時に発火） |
| `onSentenceNavigation` | `((NSRange, [CGRect]) -> Void)?` | 文ナビゲーション通知（フォーカスモード用） |
| `onUserScroll` | `(() -> Void)?` | ユーザーのタッチスクロール時コールバック（フォーカスモード解除用） |
| `blockRangeProvider` | `BlockRangeProvider?` | ブロック境界検出（スマート選択用） |
| `blockSeparator` | `String?` | ブロック間セパレータ（swapBlock のセパレータ正規化用、nil で無効） |
| `isFindInteractionEnabled` | `Bool` | UIFindInteraction による検索置換 UI を有効にする（iOS 16+、デフォルト `false`） |

## ScrollAlignment — スクロール配置方法（enum）

`scrollRevision` によるプログラム的スクロール時のカーソル配置方法。

| ケース | 説明 |
|---|---|
| `.minimal` | 最小限のスクロール（デフォルト、`scrollRangeToVisible` + `enforceScrolloff`） |
| `.top` | カーソルを上端から `scrollOffLines` 行目に配置 |

## UndoableEdit — アンドゥ可能な外部テキスト編集リクエスト（struct）

App Intent 等からプログラム的にテキストを変更する際、`IMETextViewRepresentable` の
`undoableEdit` Binding にセットすると `undoManager` に登録され Cmd+Z で元に戻せる。

```swift
init(text: String, cursorLocation: Int, selectionLength: Int = 0)
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `text` | `String` | 変更後のテキスト全体 |
| `cursorLocation` | `Int` | 変更後のカーソル位置（UTF-16 offset） |
| `selectionLength` | `Int` | 変更後の選択長（UTF-16 単位、通常 0） |

## IMETextViewRepresentable — SwiftUI ラッパー

```swift
init(inputManager: InputManager, keyRouter: KeyRouter, editorStyle: EditorStyle = .init(),
     text: Binding<String> = .constant(""), cursorLocation: Binding<Int> = .constant(0),
     selectionLength: Binding<Int> = .constant(0), scrollRevision: Int = 0,
     scrollAlignment: ScrollAlignment = .minimal,
     onKeyEvent: ((IMETextView.KeyEventInfo) -> Void)? = nil,
     onKeyDown: ((HIDKeyCode, Date) -> Void)? = nil,
     onKeyUp: ((HIDKeyCode, Date) -> Void)? = nil,
     onEnglishModeChange: ((Bool) -> Void)? = nil,
     onCaretRectChange: ((CGRect) -> Void)? = nil,
     onFittingCharsPerLineChange: ((_ count: Int) -> Void)? = nil,
     onScrollRequest: ((IMETextView, Int) -> Void)? = nil,  // deprecated: scrolloff が自動適用
     blockRangeProvider: BlockRangeProvider? = nil,
     blockSeparator: String? = nil,
     onSentenceNavigation: ((_ sentenceRange: NSRange, _ rects: [CGRect]) -> Void)? = nil,
     onUserScroll: (() -> Void)? = nil,
     textRangeRectsProvider: TextRangeRectsProvider? = nil,
     isFindInteractionEnabled: Bool = false,
     invisibleSpaceColor: UIColor? = nil,
     invisibleFullWidthSpaceColor: UIColor? = nil,
     invisibleTabColor: UIColor? = nil,
     invisibleNewlineColor: UIColor? = nil,
     undoableEdit: Binding<UndoableEdit?> = .constant(nil))
```

## TextRangeRectsProvider — テキスト範囲 rect プロバイダ（クラス）

テキスト範囲の視覚 rect を任意のタイミングで問い合わせるためのプロバイダ。
IMETextViewRepresentable が makeUIView で内部のクロージャを設定する。

```swift
init()
```

| プロパティ | 型 | 説明 |
|---|---|---|
| `getRects` | `@MainActor (NSRange) -> [CGRect]` | 指定 NSRange の視覚 rect 配列を返す。未設定時は空配列 |

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
init(predictions: [PredictionItem], selectedIndex: Int? = nil,
     font: Font, anchor: CGRect? = nil, bounds: CGSize? = nil)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `selectedIndex` | `Int?` | Tab で巡回選択中の候補インデックス。nil = 未選択 |
| `anchor` | `CGRect?` | カーソル矩形（配置のアンカー）。`bounds` と共に指定すると自動配置が有効になる |
| `bounds` | `CGSize?` | 表示領域のサイズ（overlay の親ビューサイズ） |

自動配置ルールは CandidatePopup と同一。

関連型: `PredictionItem` struct（`text: String`, `annotation: String?`）
