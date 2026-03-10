# キーマップ定義フォーマット仕様書 v1.0

## 概要

キーマップ定義フォーマットは、日本語入力方式をデータ駆動で定義する JSON フォーマットである。
逐次入力（ローマ字、AZIK、月配列等）と同時打鍵入力（薙刀式、NICOLA 等）の両方を 1 つのスキーマで表現する。

特定のプラットフォームや変換エンジンに依存しない汎用フォーマットとして設計されている。

### 設計思想

- **データ駆動**: 入力方式の追加・変更にコード変更が不要
- **物理キー中心**: USB HID Keyboard/Keypad Page 準拠のキー名でキーを識別し、OS のキーボードレイアウト差異を吸収
- **宣言的**: テーブル定義のみ。制御フローはランタイムが担う
- **拡張可能**: `extensions` オブジェクトと `x-` プレフィックスでアプリ固有の拡張が可能

## トップレベル構造

```json
{
  "formatVersion": "1.0",
  "name": "キーマップ名",
  "description": "説明（任意）",
  "author": "作者名（任意）",
  "license": "SPDX-License-Identifier（任意）",
  "keyboardLayout": "us",
  "targetScript": "hiragana（任意）",
  "behavior": { ... },
  "controlBindings": { ... },
  "inputMappings": { ... },
  "extensions": { ... }
}
```

### 必須フィールド

| フィールド | 型 | 説明 |
|---|---|---|
| `formatVersion` | string | `"1.0"` 固定 |
| `name` | string | 表示名 |
| `keyboardLayout` | string | 対象物理配列（`"us"` / `"jis"`） |
| `behavior` | object | 入力方式定義（後述） |

### 任意フィールド

| フィールド | 型 | 説明 |
|---|---|---|
| `description` | string | 入力方式の説明 |
| `author` | string | 作者名 |
| `license` | string | ライセンス識別子（[SPDX](https://spdx.org/licenses/) 推奨） |
| `targetScript` | string | 出力文字体系（`"hiragana"`, `"katakana"` 等） |
| `controlBindings` | object | Emacs 風制御キーバインド（省略時はデフォルト） |
| `keyRemap` | object | キーリマップ（物理キー文字 → 論理キー文字） |
| `inputMappings` | object | 逐次入力用カスタムマッピング |
| `prefixShiftKeys` | array | 前置シフトキーの明示指定（逐次入力用） |
| `bufferDisplayMap` | object | 逐次入力バッファの表示変換（OS 文字 → 表示文字） |
| `extensions` | object | アプリ固有の拡張フィールド |

## behavior: 入力方式定義

`behavior.type` で方式を切り替える。

### sequential（逐次入力）

```json
{
  "type": "sequential",
  "characterMap": {
    "0": "０",
    ",": "、",
    ".": "。"
  }
}
```

- `characterMap`: 半角→全角の 1 文字マッピング。キー・値ともに 1 文字
- キー入力は OS が解決した文字コード（`key.characters` 相当）で判定

**逐次入力固有のトップレベルフィールド:**

- `inputBase`: ベーステーブルの種類（任意）
  - `"romaji"`: 組み込み標準ローマ字テーブルを `inputMappings` のベースとして使用
  - 省略時はベーステーブルなし（`inputMappings` のみ使用）
- `keyRemap`: キーリマップテーブル（任意、object）
  - 物理キー文字 → 論理キー文字のマッピング（1文字→1文字）
  - `inputBase` と併用すると、ベーステーブルのキーを論理キー空間から物理キー空間に自動変換する
  - 展開順序: ベーステーブル（論理）→ suffixRules 展開（論理）→ keyRemap 逆変換（→ 物理）
  - 例: 大西配列では `"d": "a"` （物理キー D → 論理キー a）。標準ローマ字の `ka→か` が `hd→か` に変換される
  - `bufferDisplayMap` が未指定の場合、`keyRemap` を `bufferDisplayMap` としても使用する
  - `suffixRules` と併用可能。suffixRules は論理キー空間で適用されるため、標準ローマ字の拡張がそのまま機能する
- `suffixRules`: サフィックス展開ルール（任意、object）
  - ベーステーブル + `inputMappings` の全エントリに対してサフィックスを自動展開する
  - 各キーは展開トリガーの文字、値は `{ "vowel": "a", "suffix": "ん" }` 形式
  - `vowel`: 対象エントリの末尾母音（"a", "i", "u", "e", "o"）
  - `suffix`: 出力に付加する文字列
  - 展開例: `"z": { "vowel": "a", "suffix": "ん" }` → `ka→か` から `kz→かん` を自動生成
  - 母音単独エントリ（`a→あ` 等）は展開対象外（子音部分が必要）
  - マージ優先順: 明示的 `inputMappings` > サフィックス展開 > `inputBase`
- `inputMappings`: カスタムキーシーケンス→かな変換テーブル
  - 例: `"dq": "ぁ"`（D前置+Q）, `"sl": "が"`（S+L後置濁音）
  - greedy longest-match で解決される
  - `inputBase` / `suffixRules` と併用時は、自動生成されない固有エントリのみ記述すればよい
- `prefixShiftKeys`: 前置シフトキーの明示指定（1文字の文字列の配列）
  - 指定されたキーのみシフトキーとして扱い、⇧ ラベル + シフトレイヤーを可視化パネルに生成する
  - 月配列2-263 等の前置シフト方式: `"prefixShiftKeys": ["d", "k"]`
  - ローマ字系配列（AZIK 等）: `"prefixShiftKeys": []`（子音キーはシフトキーではない）
  - 省略時は `[]` と同等（前置シフトキーなし）
- `bufferDisplayMap`: 未解決バッファの表示変換テーブル（OS 文字 → 表示文字）
  - キー位置リマップ型の配列（大西配列等）で使用
  - バッファに未解決文字が残っている間、OS が報告する文字の代わりに論理配列の文字を表示する
  - 例: `"h": "k"`（大西配列では物理 H = 論理 k。バッファに `h` が入っても `k` と表示）
  - 省略時は OS 報告文字をそのまま表示

### chord（同時打鍵）

```json
{
  "type": "chord",
  "config": {
    "hidToKey": { "a": "A", "space": "space", ... },
    "lookupTable": { "J": "あ", "F+J": "が", ... },
    "specialActions": { "F+G": "chordModeOff", ... },
    "simultaneousWindow": 0.08,
    "shiftKeys": [
      { "key": "space", "singleTapAction": "convert" }
    ],
    "englishLookupTable": { "A": "a", ... },
    "englishSpecialActions": { "F+G": "chordModeOff", ... }
  }
}
```

#### config フィールド

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `hidToKey` | object | 必須 | 物理キー名 → ChordKey マッピング |
| `lookupTable` | object | 必須 | キー組合せ → 出力文字列 |
| `specialActions` | object | 必須 | キー組合せ → 特殊アクション |
| `simultaneousWindow` | number | 必須 | 同時打鍵判定ウィンドウ（秒） |
| `shiftKeys` | array | 必須 | シフトキー定義（0〜2 個） |
| `englishLookupTable` | object | 任意 | 英数モード用 lookup |
| `englishSpecialActions` | object | 任意 | 英数モード用アクション |

#### shiftKeys

```json
{ "key": "space", "singleTapAction": "convert" }
```

- `key`: シフトキーの ChordKey 名（`"space"`, `"leftThumb"`, `"rightThumb"`）
- `singleTapAction`: 単打時のフォールバックアクション（任意）

## controlBindings: 制御キーバインド

```json
{
  "emacsBindings": {
    "h": "deleteBack",
    "m": "confirm",
    "j": "confirmHiragana"
  },
  "ctrlSemicolonAction": "confirmFullWidthRoman",
  "ctrlColonAction": "confirmHalfWidthRoman"
}
```

省略時は macOS 標準「ことえり」準拠のデフォルトが適用される。

## ChordKey 一覧

QWERTY 30 キー + 親指 3 キー:

| 段 | キー |
|---|---|
| 上段 | `Q` `W` `E` `R` `T` `Y` `U` `I` `O` `P` |
| 中段 | `A` `S` `D` `F` `G` `H` `J` `K` `L` `semicolon` |
| 下段 | `Z` `X` `C` `V` `B` `N` `M` `comma` `dot` `slash` |
| 親指 | `space` `leftThumb` `rightThumb` |

### ビットマスク文字列表記

キーの組合せは `+` 区切りで表記する:

- 親指キー（`space`, `leftThumb`, `rightThumb`）は常に先頭
- 残りのキーはアルファベット順にソート
- 例: `"space+A+J"`, `"F+G"`, `"leftThumb+K"`

## KeyAction 一覧

### well-known アクション（パラメータなし）

| アクション | 説明 |
|---|---|
| `convert` | 変換 / 次候補 |
| `convertPrev` | 前候補 |
| `confirm` | 確定 |
| `cancel` | キャンセル |
| `deleteBack` | 1 文字削除 |
| `moveLeft` | 左移動 |
| `moveRight` | 右移動 |
| `moveUp` | 上移動 |
| `moveDown` | 下移動 |
| `editSegmentLeft` | 文節左縮小 |
| `editSegmentRight` | 文節右拡大 |
| `confirmHiragana` | ひらがな確定 |
| `confirmKatakana` | カタカナ確定 |
| `confirmHalfWidthKatakana` | 半角カタカナ確定 |
| `confirmFullWidthRoman` | 全角英数確定 |
| `confirmHalfWidthRoman` | 半角英数確定 |
| `chordModeOff` | 英数モード切替 |
| `chordModeOn` | chord モード復帰 |
| `pass` | ランタイムに委譲 |

### well-known アクション（パラメータ付き `"アクション名:パラメータ"` 形式）

| アクション | パラメータ | 例 |
|---|---|---|
| `printable` | 1 文字 | `"printable:a"` |
| `selectCandidate` | 整数（0〜8） | `"selectCandidate:0"` |
| `chordInput` | ChordKey 名 | `"chordInput:A"` |
| `chordShiftDown` | ChordKey 名 | `"chordShiftDown:space"` |
| `insertAndConfirm` | 文字列 | `"insertAndConfirm:。"` |
| `directInsert` | 文字列 | `"directInsert:a"` |

### アプリ固有アクション（`x-` プレフィックス）

`x-` で始まるアクション名はアプリ固有の拡張として予約されている。
対応していないランタイムは `x-` アクションを安全に無視できる。

```json
"x-myApp:customAction:param"
```

## 物理キー名一覧

USB HID Keyboard/Keypad Page に対応する独自の簡潔な命名を使用する。
特定の OS や言語の API 名には依存しない。

| カテゴリ | キー名 |
|---|---|
| アルファベット | `a` 〜 `z` |
| 数字 | `0` 〜 `9` |
| 制御 | `enter` `escape` `backspace` `delete` `tab` `space` `capsLock` |
| 記号 | `hyphen` `equal` `bracketLeft` `bracketRight` `backslash` `semicolon` `quote` `backquote` `comma` `period` `slash` |
| ナビゲーション | `arrowRight` `arrowLeft` `arrowDown` `arrowUp` `home` `end` `pageUp` `pageDown` |
| ファンクション | `f1` 〜 `f12` |
| JIS 固有 | `international1`(¥/_) `international2`(ひらがな) `international3`(¥) `international4`(変換) `international5`(無変換) `lang1`(かな) `lang2`(英数) |
| 修飾 | `rightAlt` |

## extensions: アプリ固有拡張

`extensions` オブジェクトは、フォーマット仕様の範囲外のアプリ固有データを格納する。
キー名には `x-` プレフィックスを推奨する。

```json
{
  "extensions": {
    "x-inputTableID": "defaultAZIK",
    "x-myApp:setting": "value"
  }
}
```

対応していないランタイムは `extensions` を安全に無視できる。

## バージョニング方針

- `formatVersion` でセマンティックバージョニングを行う
- **マイナーバージョン**（1.0 → 1.1）: フィールド追加等の後方互換変更
- **メジャーバージョン**（1.0 → 2.0）: 破壊的変更
- デコーダは `formatVersion` を確認し、未対応バージョンは明確なエラーを返す

## JSON Schema

バリデーション用の JSON Schema は `docs/keymap-v1.schema.json` に配置している。
エディタの自動補完や CI での事前検証に利用できる。

```json
{
  "$schema": "./keymap-v1.schema.json"
}
```
