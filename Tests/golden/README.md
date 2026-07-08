# ゴールデンテスト・コーパス

キーマップ入力エンジンの**プラットフォーム非依存**な回帰テストコーパス。
「キーマップ + キーイベント列 → 期待されるかな出力」を JSON で記述し、
Swift (KeyLogicKit) / TypeScript (web) / Kotlin (android-kide) の3実装が同じコーパスを消費して検証する。

- **スコープ**: 物理キー入力 → かな解決まで。**かな漢字変換は含まない**（変換辞書はプラットフォームごとに異なるため）。
- **目的**: 3実装の移植パリティを人力同期（"Port of *.swift L439-751" コメント）から機械検証に置き換える。

## ファイル構成

```
Tests/golden/
├── README.md          # 本ファイル（形式仕様）
└── cases/
    ├── romaji_builtin_us.json   # 組み込み標準ローマ字
    ├── azik_us.json             # AZIK（逐次 + suffixRules）
    ├── tsuki2-263_us.json       # 月配列（前置シフト）
    └── nicola_us.json           # NICOLA（親指シフト同時打鍵）
```

注: かわせみ配列のフィクスチャは配列データ未検証のため `keymaps-wip/` 退避と同時に削除した。
検証後に配列を復帰させる際はフィクスチャも一緒に追加すること。

## フィクスチャ形式 (v1)

```json
{
  "keymap": "azik_us",
  "description": "AZIK US の逐次入力",
  "cases": [
    {
      "name": "suffix_kan",
      "steps": [ { "press": "k" }, { "press": "z" } ],
      "expect": { "text": "かん" }
    }
  ]
}
```

### keymap

- `"<name>"` — 正規キーマップ JSON（`web/public/keymaps/<name>.json` = `Sources/KeyLogicKit/Resources/Keymaps/<name>.json`）をロードする
- `"builtin:romaji_us"` / `"builtin:romaji_jis"` — 各実装の組み込み標準ローマ字テーブルを使う

### steps（順に実行）

| ステップ | 意味 |
|---|---|
| `{ "press": "k" }` | キーの down → up（最頻出の単打） |
| `{ "chord": ["space", "w"] }` | 記載順に全キー down → 逆順に up（同時打鍵） |
| `{ "down": "space" }` / `{ "up": "space" }` | down / up の個別制御（シフトホールド等） |
| `{ "wait": 150 }` | 仮想時計を ms 進める（同時打鍵ウィンドウの満了用） |

- キー名は `docs/keymap-v1.schema.json` の `keyName` enum（HID usage 名: `a`〜`z`, `semicolon`, `space`, `rightAlt`, `international4` 等）。
- `press` / `down` に `"char": ":"` を併記すると、そのイベントの文字（`KeyEvent.characters`）を上書きできる（US 配列でのシフト記号等）。省略時は US 配列の非シフト文字を自動導出。
- `"modifiers": ["shift"]` で修飾キーフラグを付与できる。

### タイミングの意味論

- `wait` は**タイマー駆動の実装**（web: `setTimeout`）では仮想時計を進める。**イベント駆動でタイマーを持たない実装**（Swift: pressesEnded ベース）では no-op として扱ってよい。
- 各ケースの終了時、ランナーは**未満了のタイマーをすべて満了させてから**期待値を検証する（末尾の `wait` は不要）。
- 同時打鍵キーマップで単打を連続させる場合は、間に `{ "wait": <window超> }` を挟むこと（挟まないと2打目が chord 判定される — それ自体をテストしたい場合は挟まない）。

### expect

- `{ "text": "かん" }` — ケース終了時の **確定済みテキスト + composing 中かな** の連結
- `{ "confirmed": "か", "composing": "き" }` — 確定/未確定を分けて検証（どちらか一方でも可）

### skip（ケース単位のプラットフォーム除外）

```json
{ "name": "confirm_with_enter", "skip": ["kide"], ... }
```

そのケースを実行しないプラットフォーム ID（`"web"` / `"swift"` / `"kide"`）の配列。
kide は IME を持たないキーボード変換器（HID stroke 出力）のため、以下は `"kide"` を指定して除外する:

1. **IME 意味論のケース**（Enter 確定、親指単打の全角スペース挿入等）
2. **保留状態で終わるケース**: 逐次バッファが「完全一致かつ、より長いエントリのプレフィックス」
   （例: AZIK の `kk` = きん だが `kka` = っか の途中でもある）で終わると、web/Swift は
   composing の**仮解決**（きん）を表示できるが、確定ベースの kide は何も出力しない。
   このようなケースは kide を skip し、代わりに次のキーで曖昧性が解決する
   「確定込みの派生ケース」（`kka` → っか）を全プラットフォーム対象で置くこと。

各ランナーは自分の ID が含まれるケースをスキップしなければならない。

## 期待値の根拠

期待値はキーマップ JSON の `lookupTable` / `inputMappings` / `suffixRules` から手で導出する（実装の出力をコピーしない）。
実装と期待値が食い違った場合、**どちらが正しいかを必ず判断してから**修正すること — 実装のバグなら Issue 化、期待値の誤りならコーパスを直す。

## ランナー

| プラットフォーム | 場所 | 実行方法 |
|---|---|---|
| web (TypeScript) | `web/src/engine/__tests__/golden.test.ts` | `cd web && npm test`（vitest / fake timers） |
| web / node 単体 | `web/scripts/run-golden-node.mjs` | `cd web && npm run test:engine`（ビルド済み UMD バンドルを `require`。QuuBee 統合回帰と同じ経路。仮想クロックで `wait` を進める） |
| Swift (KeyLogicKit) | `Tests/KeyLogicKitTests/GoldenTests.swift` | CI (`swift-test.yml`、iOS Simulator)。iOS 専用パッケージのため macOS + Xcode 必須 |
| Kotlin (android-kide) | `android-kide/app/src/test/.../golden/GoldenTest.kt` | `gradle :app:testDebugUnitTest`（CI: `kide-test.yml`） |

### 実装差メモ（kide）

- kide は IME を持たず、Router の出力は**かな文字列ではなく JIS かな HID stroke 列**。
  ランナーは期待かなを `KanaToJisKeyTable.toStrokes()` で順方向に stroke 化して突き合わせる
  （濁点の 2 stroke 分解も同じ経路なので一致する）。
- AZIK 系キーマップは `AzikRouter`（ASCII ローマ字出力）ではなく
  `SequentialKanaRouter`（かな出力）側を検証対象にする。
- `ChordKanaRouter.fromKeymap` は実機 BT ジッター対策で宣言 window を増幅するため、
  ランナーは JSON 宣言値に戻して実行する。時間は実時間（`System.currentTimeMillis`）なので
  `wait` は実スリープ。

### 実装差メモ（web ⇔ Swift）

- **単打の出力タイミング**: web は keyDown で先行出力（eager output + rollback）、Swift は keyUp（全キーリリース）で出力。最終テキストは同じになるため、コーパスは中間状態を検証しない。
- **時間の扱い**: web は `setTimeout` ベース（ランナーは fake timers）、Swift は実時間（`CFAbsoluteTimeGetCurrent` による inter-key timing + idle ゲーティング。ランナーは `wait` を実スリープで再現）。
- **`.convert` の意味論**: 実アプリの Swift はかな漢字変換を開始するが、ゴールデンのスコープはかな解決までのため、両ランナーとも「composing 中の convert = 確定」として扱う。
