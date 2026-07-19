# フリックマップ定義フォーマット仕様書 flick-1

## 概要

フリックマップ定義フォーマットは、タッチスクリーン向けのフリック入力方式をデータ駆動で
定義する JSON フォーマットである。12キー標準フリックのほか、任意グリッドのかな直接入力・
ローマ字出力型（アルテ系）を 1 つのスキーマで表現する。

キーマップ定義フォーマット v1（`docs/keymap-format.md`）が**物理キーボード**という
デバイスクラスを対象とするのに対し、本フォーマットは**タッチグリッド**を対象とする
別フォーマットである（ゲームパッドかな入力が KeyRouter をバイパスするのと同じ整理）。
ただしアクション語彙は keymap v1 の specialActions と共有し、意味論を揃える。

実装（リファレンスランタイム）は labo `web/src/flick/`（UMD バンドル `FlickEngine`）。
組み込みガイドは `docs/flick-engine-embedding.md`（PR-C で作成予定）。

### 設計思想

- **データ駆動**: フリック配列の追加・変更にコード変更が不要
- **グリッド自由**: 12キー（4×5）固定ではなく任意の rows×cols。iPad 横持ちの
  片手 3 列ペインなども同じスキーマで表現する（後述「分割レイアウト」）
- **宣言的**: テーブル定義のみ。ジェスチャ判定・状態はランタイムが担う
- **セッション層と疎結合**: 出力は「かな挿入」と「意味キー（KeyTap）」に正規化され、
  hechima セッション（`FepSession`）へ注入される。変換エンジンには依存しない

## トップレベル構造

```jsonc
{
  "formatVersion": "flick-1",
  "name": "12キー標準フリック",
  "description": "iOS/Android 標準相当の12キーフリック（任意）",
  "author": "原作者名（任意）",
  "contributor": "派生版作者名（任意）",
  "basedOn": "派生元の配列名（任意）",
  "license": "SPDX-License-Identifier（任意）",
  "output": "kana",
  "flickConfig": { ... },
  "postModifyCycles": [ ... ],
  "initialLayer": "kana",
  "layers": { ... }
}
```

### 必須フィールド

| フィールド | 型 | 説明 |
|---|---|---|
| `formatVersion` | string | `"flick-1"` 固定 |
| `name` | string | フリックマップの表示名 |
| `layers` | object | レイヤ定義（1 つ以上） |

### 任意フィールド

| フィールド | 型 | 既定 | 説明 |
|---|---|---|---|
| `output` | `"kana"` \| `"romaji"` | `"kana"` | キー値の解釈（後述） |
| `flickConfig` | object | 全て既定値 | ジェスチャ判定・UI の調整 |
| `postModifyCycles` | string[] | 内蔵標準テーブル | `postModify` の変換系列（後述） |
| `initialLayer` | string | `"kana"`（無ければ宣言順の先頭） | 起動時レイヤ |
| `description` / `author` / `contributor` / `basedOn` / `license` | string | — | keymap v1 と同義のメタデータ |

ファイル名がフリックマップの id となる（keymap と同じ運用。例: `flick_standard.json`）。
`_comment` プレフィックスのキーは全オブジェクトで注記用として許可される。

## flickConfig: ジェスチャ判定・UI 設定

```jsonc
{
  "inputStyle": "flick",
  "threshold": 0.35,
  "petalDelayMs": 0,
  "repeat": { "delayMs": 500, "intervalMs": 80 }
}
```

| フィールド | 型 | 既定 | 説明 |
|---|---|---|---|
| `inputStyle` | `"flick"` | `"flick"` | 入力方式。**`"flick+multitap"`（トグル併用）は予約**（後述「将来拡張」。flick-1 実装ではスキーマが `"flick"` のみ許可） |
| `threshold` | number (0.1〜1.0) | 0.35 | フリック判定距離。**セル幅に対する比**（デバイス DPI 非依存） |
| `petalDelayMs` | integer ≥ 0 | 0 | 押下からペタル（花びらガイド）表示までの遅延。0 = 即時表示 |
| `repeat.delayMs` | integer | 500 | `repeat: true` キーの長押しリピート開始まで |
| `repeat.intervalMs` | integer | 80 | リピート間隔 |

ジェスチャ判定（ランタイム仕様）:

- pointerdown 起点。移動距離 < `threshold` × セル幅 → **tap**、以上 → **flick**
- flick 方向は 4 方向、角度 45° 区切り（↑ = -135°〜-45° 等）。ポインタキャプチャで
  キー外リリースでも判定を継続する
- 出力確定は pointerup 時（ペタル表示は視覚ガイドのみ）
- `repeat: true` のキーは長押しで tap 値をリピート発火（フリック値はリピートしない）

## layers: レイヤ定義

```jsonc
"layers": {
  "kana":  { "grid": { "rows": 4, "cols": 5 }, "keys": [ ... ] },
  "eiji":  { "output": "direct", "grid": { "rows": 4, "cols": 5 }, "keys": [ ... ] },
  "digit": { "output": "direct", "grid": { "rows": 4, "cols": 5 }, "keys": [ ... ] }
}
```

レイヤ名は自由（`setLayer` アクションの参照先）。標準 12 キーの慣習は
`kana` / `eiji` / `digit` の 3 レイヤだが、スキーマは強制しない。

| フィールド | 型 | 説明 |
|---|---|---|
| `grid` | object（必須） | `rows` / `cols`（1〜8） |
| `keys` | array（必須） | キー定義（1 つ以上） |
| `output` | `"kana"` \| `"romaji"` \| `"direct"` | このレイヤの出力先（省略時 = トップレベル `output`）。**`"direct"` はレイヤ単位のみ**: 値をセッション（合成）を経由せずホストのエディタへ直接挿入する。標準 12 キーの英字・数字レイヤ用（実 IME と同じく英数字は無変換で直接入力） |

### key: キー定義

```jsonc
{
  "row": 0, "col": 1,
  "label": "あ",
  "tap": "あ",
  "flick": { "left": "い", "up": "う", "right": "え", "down": "お" }
}
```

| フィールド | 型 | 説明 |
|---|---|---|
| `row` / `col` | integer ≥ 0（必須） | グリッド位置（0 起点） |
| `rowSpan` / `colSpan` | integer ≥ 1 | セル結合（既定 1。空白キーの横長等） |
| `label` | string | キー面の表示。省略時は `tap` が文字列ならそれを表示（アクションキーでは必須） |
| `tap` | Value | 単押しの値（省略可 — 省略時、単押しは何もしない） |
| `flick.up/down/left/right` | Value | 各方向の値（すべて省略可） |
| `repeat` | boolean | 長押しリピート（`deleteBack` キー等。既定 false） |

`tap` と `flick` の両方を省略したキーは無効（デコードエラー）。

### Value: 文字列 or アクション

キーの値は次のいずれか:

1. **文字列** — 出力テキスト。`output: "kana"` ならかな（複数文字可。「ゃ」等の
   小書きや「きゃ」のような連字も 1 値で表現できる）、`output: "romaji"` なら ASCII
2. **アクションオブジェクト** — `{ "action": "<name>", ...params }`

## アクション語彙

keymap v1 の specialActions と同じ名前・同じ意味論を使う。実行は hechima セッションの
`feed()` に **KeyTap（KeyboardEvent 互換の最小形）を合成して流す**ことで行われ、
セッションが消費しなかった場合（合成中でない等）はホストのエディタ操作に透過する
（物理キーボードと同じ二重経路）。

| action | 合成 KeyTap | 合成中 / Phase 2 での意味 | 非合成中（透過先） |
|---|---|---|---|
| `deleteBack` | `Backspace` | 末尾 1 字削除 / よみに戻す | ホスト編集（1 字削除） |
| `convert` | `" "`（Space） | 変換開始・次候補 | ホスト編集（空白挿入） |
| `confirm` | `Enter` | 確定 / 結合確定 | ホスト編集（改行） |
| `escape` | `Escape` | 取消 / よみに戻す | （透過） |
| `moveLeft` / `moveRight` | `ArrowLeft` / `ArrowRight` | — / 文節フォーカス移動 | caret 移動 |
| `moveUp` / `moveDown` | `ArrowUp` / `ArrowDown` | — / 候補ナビ・追加候補展開 | caret 移動 |
| `resizeLeft` / `resizeRight` | `Shift+ArrowLeft` / `Shift+ArrowRight` | — / 文節伸縮 | （透過） |

フリック固有のアクション（ランタイム内部で解決、セッションに流れない）:

| action | params | 説明 |
|---|---|---|
| `setLayer` | `layer`（必須） | レイヤ切替。`layers` に無い名前はデコードエラー |
| `postModify` | — | 直前入力文字の濁点/半濁点/小書きトグル（次節） |

## postModify: ゛゜小トグル

合成中テキストの**末尾 1 字**を変換系列（サイクル）に沿って置き換える。
末尾字がどのサイクルにも含まれない場合・合成中でない場合は何もしない。

対象文字の特定は**セッションの合成表示（cb.show の内容）の末尾を正**とする
（ランタイムの自己追跡ではないため、BS で編集された後もずれない）。
置き換えは `fep.insertKana(次の字, 1)`（1 字置換）で行う。

既定サイクル（内蔵。iOS 標準 12 キーの「゛゜小」と同系列）:

```
かが きぎ くぐ けげ こご  さざ しじ すず せぜ そぞ
ただ ちぢ つっづ てで とど  はばぱ ひびぴ ふぶぷ へべぺ ほぼぽ
あぁ いぃ うぅゔ えぇ おぉ  やゃ ゆゅ よょ わゎ
```

各サイクルは文字列で表現し、押すたびに次の字へ進む（末尾 → 先頭に戻る）。
`postModifyCycles`（トップレベル、string[]）で**完全置換**できる。
`output: "romaji"` では `postModify` は使用不可（デコードエラー）。

## output: "kana" / "romaji" / "direct"

- **`"kana"`（既定）**: 文字列値は `fep.insertKana(text)` でセッションに直接注入される。
  idle = 合成開始 / 合成中 = 連結 / 候補選択中 = 現候補を確定して新規合成（かな追加の
  標準セマンティクス）/ よみ復帰中 = よみに連結。
- **`"romaji"`**: 文字列値は 1 字ずつ KeyTap（`{key: 文字}`）としてセッションの
  `feed()` に流し、既存のローマ字解決（`resolveRomaji`）に委ねる。
  フリックでローマ字ペアを打つ方式（アルテ系）のための出力型。値は ASCII 限定。
- **`"direct"`（レイヤ単位のみ）**: 文字列値をセッションを経由せずホストのエディタへ
  直接挿入する（`postModify` は使用不可）。標準 12 キーの英字・数字レイヤ用
  （実 IME と同じく英数字は無変換で直接入力）。トップレベル `output` には指定できない。

## 分割レイアウト（設計考慮）

グリッドは自由サイズなので、iPad 横持ちの**片手ペイン**（例: 右手側 3 列 —
かな 10 キーを縦に並べ、上下の行に `convert` / `confirm` / `deleteBack` / カーソルを
配置）も 1 つのフリックマップとして表現できる。

左右分割（右手 = 入力、左手 = 候補選択）は、**フリックマップ 2 枚をホストが並べて
mount する**か、左手側を候補選択専用のホスト UI（`FepSession` の
`SegmentView.candidates` / `selectCandidate()`）として実装する。候補選択 UI は
フリックマップの守備範囲外（セッション層の候補 API の領分）。

## 将来拡張（予約 — flick-1 では未実装）

keymap v2 スケッチ（`docs/keymap-v2-sketch.md`）と同じ流儀で、判断の座標系だけ先に置く:

- **`inputStyle: "flick+multitap"`**: トグル併用（同キー連打で あ→い→う→…、
  タイムアウトで確定）。サイクル順の既定 = `[tap, left, up, right, down]`、
  キーに `cycle` 配列で上書き。`multitapTimeoutMs` を flickConfig に追加。
  置換は `insertKana(次の字, 1)` で表現できるため additive に実装可能
- **8 方向 / カーブフリック**: `flick` に `upLeft` 等の斜め 4 方向、または 2 段方向
  （下→右 のような軌跡）。判定が変わるため flick-2 案件
- **2 タッチ（ポケベル式）**: 2 打で 1 かなを座標指定する別 inputStyle
- **ターンフリック**: ペタルの多段展開

## バージョニング方針

- `formatVersion` は `"flick-1"` 固定。additive な追加（新アクション・任意フィールド）は
  flick-1 のまま行い、ランタイムのバージョンで表現する
- ジェスチャ判定の意味論が変わる拡張（8 方向等）は `"flick-2"` に上げる

## JSON Schema

`docs/flickmap-v1.schema.json` を参照。CI バリデーション（web-test への組み込み）は
リファレンスランタイム実装（PR-C）と同時に導入する。
