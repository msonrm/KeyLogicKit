# hechima 電文 v0 — 「かな → 文節/候補」境界のプロトコル仕様

hechima スタックの変換エンジン境界を流れるメッセージの正典。
「**返り値の形 = 将来の IME 通信プロトコルの電文形式として設計する**」という
設計方針（統合スペック v1）の実装であり、型定義の正典は
[`web/src/hechima/protocol.ts`](../web/src/hechima/protocol.ts)（`Hechima.*` として公開）。

## 1. 三つのトランスポート、一つのペイロード

同じペイロード（§2）が 3 つの運び方で流れる。上位層（セッション・候補 UI）は
どのトランスポートかを知らない:

| トランスポート | 実装 | 状態 |
|---|---|---|
| C API（ccall 直呼び） | `hechima-wasm` の `hechima_convert` / `hechima_resize`（JSON 文字列を返す） | 実装済み |
| **Worker postMessage RPC** | `hechima-worker.js`（本書の主対象。§3） | 実装済み（v0.4.0） |
| ネットワーク延伸 | WebRTC DataChannel 等（インプットハブ構想。スマホ母艦→受信側サイト） | 将来 |

## 2. ペイロード: `WireSegment`

```json
{ "segments": [ { "key": "きょうは", "candidates": ["今日は", "京は", "きょうは"] }, ... ] }
```

- `key` = 文節のよみ（ひらがな）。全文節の `key` を結合すると入力よみに一致する
- `candidates` = 変換候補。先頭が第一候補
- `segments` が無い / 空 / パース不能は「結果なし」= 呼び元は現状維持 or フォールバック

これは `hechima_convert` の返す JSON と同形。セッション層の `cb.convert` /
`cb.resize` が返す `ConvertSegment[]` はこの `segments` 配列そのもの。

## 3. Worker RPC（電文 v0）

`hechima-worker.js`（classic worker。`npm run build:hechima` で
`web/public/hechima/` に出力）とホストの間の postMessage 契約。

### ホスト → Worker

| 電文 | フィールド | 意味 |
|---|---|---|
| `init` | `wasmJs?`, `dataUrl?`, `learning?`, `scope?` | wasm ロード + 辞書取得。パスは worker スクリプト位置からの相対 URL（既定 `./hechima-wasm.js` / `./mozc.data`）。`learning` 省略 = true、`scope` 省略 = "default"（v0.8.0+）。1 worker につき 1 回 |
| `convert` | `id`, `kana`, `maxCands?` | かな漢字変換（maxCands 既定 9） |
| `resize` | `id`, `segIdx`, `offset`, `maxCands?` | 文節伸縮。直近の convert 結果の `segIdx` 文節（0 起点）のよみを `offset`（よみ文字数 ±）だけ伸縮して再変換 |
| `reconvert` | `id`, `surface`, `maxCands?` | 再変換（v0.10.0+）。表記 → 逆変換でよみ → 変換（応答 result の keys がよみ）。ステートレス |
| `learn` | `id`, `kana`, `sizes`, `values` | 確定内容の学習（v0.8.0+）。値は**エンジン中立**（候補 index ではなく表示値）— dedupe や UI 並べ替えに頑健で、エンジン差し替えでも電文不変。Mozc worker では変換を再現し値一致で確定 → FinishConversion（all-or-nothing = 誤学習防止） |
| `revert` | `id` | 直近の `learn` の取り消し（v0.9.0+。確定アンドゥの学習巻き戻し = Mozc RevertConversion。不成立 learn の後は no-op = 誤巻き戻し防止） |
| `dictList` / `dictAdd` / `dictRemove` | `id`（+ `reading`,`word`,`pos?` / `index`） | ユーザー辞書（v0.11.0+）。応答は `dict`（更新後の一覧）。wasm が /tmp/user_dictionary.db を直接編集し ReloadAndWait で即反映。永続化は worker の OPFS に相乗り（clearLearning では消えない） |
| `clearLearning` | `id` | OPFS の学習保存分を削除（v0.8.0+。メモリ内学習は再ロードまで残る） |

### Worker → ホスト

| 電文 | フィールド | 意味 |
|---|---|---|
| `progress` | `loaded`, `total` | 辞書ダウンロード進捗（`total` 不明時は 0） |
| `ready` | `protocol`, `version`, `features` | 初期化完了。`protocol` = 電文版数（現在 0）、`version` = hechima バンドル版、`features` = 実行時機能検出（`resize` / `learn` / `persist` = OPFS 永続化可） |
| `error` | `message` | 初期化失敗（init に対する終端応答） |
| `result` | `id`, `segments`, `error?` | convert / resize の結果。`segments: null` = 結果なし。`error` は診断用付帯情報で契約上は null と同義 |
| `learned` | `id`, `ok` | learn / clearLearning の結果（v0.8.0+） |
| `dict` | `id`, `entries`, `error?` | 辞書操作の結果（v0.11.0+。entries = 一覧、失敗 null） |

### 相関・互換規約

- `id` は呼び元が採番（単調増分で衝突しない）。応答は同じ `id` をエコーする
- 受信側は**未知のメッセージ種・未知のフィールド・未知の `id` を黙って無視**する
  （前方互換の要）
- in-flight 破棄（変換待ち中の追加打鍵で古い結果を捨てる）は**呼び元の責務**
  （セッション層が世代トークンで実施済み。トランスポートは関知しない）
- 版数規約: 後方互換の拡張（フィールド追加・メッセージ種追加）は `protocol` を
  変えない。既存フィールドの意味変更・削除は `protocol` を上げる

### クライアント側ヘルパ

`Hechima.connectWorker(worker, opts?)` が id 相関・ready 待機・resize 機能検出を
閉じ込める。`conn.callbacks()` を `createFep` の cb にスプレッドすれば配線完了:

```js
const worker = new Worker("hechima-worker.js");
const conn = Hechima.connectWorker(worker, { onProgress: (l, t) => bar(l / t) });
conn.init();   // await せず投げっぱなしでもよい（convert は ready まで待機する）
const fep = Hechima.createFep({ show, hide, commit, hostKey, ...conn.callbacks() });
```

## 4. 既知の制約（v0 の限界と v1 課題）

### resize の状態の持ち方（v0.3.0 wasm + v0.7.0 worker で解決済み）

~~`hechima_resize` は「直近の convert 結果」への stateful 操作で wasm 内に状態を持つ~~
→ **hechima-wasm v0.3.0 の `hechima_convert2`（かな + 文節境界制約 → 再変換）で
C API はステートレスになった**。「直近の変換」という接続固有の状態は hechima-worker
（本質的に 1 ホスト : 1 worker）が持ち、resize 電文（segIdx/offset）を境界制約列に
翻訳して convert2 を呼ぶ。**電文 v0 は無変更**（resize メッセージの意味は同じ）。

- 将来のネットワーク延伸では「接続ごとに状態を持つ」責務がそのままサーバー側の
  接続ハンドラに移る（C API は純関数なので多重化しても安全）
- 旧 `hechima_resize`（wasm 内 static）は互換のため残置（非推奨）。worker は
  `_hechima_convert2` の有無を機能検出し、旧 wasm（v0.2.0）では自動フォールバックする

**残る v1 課題**: 学習（`FinishConversion` 配線 = R2、別途判断）。

### 学習の設計（v0.8.0 で実装済み）

- **二層構造**: エンジン内学習（候補選択 = UserSegmentHistoryRewriter、文節境界 =
  UserBoundaryHistoryRewriter。記録も適用も Mozc 内で完結）+ ホスト側の自由層
  （`cb.learn` に流れる同じ確定イベントをホストが自前で蓄積し、`cb.convert` を wrap した
  再ランキング等に使える — 差し替え点は既存の cb 境界で足りる）
- **永続化は worker 内 OPFS で完結**（`hechima/user/<scope>/segment.db` 等。learn 成功後に
  debounce して書き戻し、init 時に復元）。ホストにバイト列は流れない。OPFS が無い環境は
  「セッション中のみ学習」に degrade（`features.persist` で判別可）
- `scope` は学習の保存単位（将来の「文書/ジャンル/グローバル」スコープ化の入口。
  カスケード合成はエンジン内学習では行わず、ホスト側の再ランキング層の領分）

### 語彙の不足（将来の予約）

以下は v0 に無い。追加はフィールド/メッセージ種の追加（= 後方互換）で行う予定:

| 予約語彙 | 用途 |
|---|---|
| `predict` | 予測変換（StartPrediction） |
| 候補注釈 | `candidates` の要素をオブジェクト化（ひらがな/カタカナ/記号種別等の annotation） |

## 5. テスト

- [`web/scripts/run-hechima-worker-test.mjs`](../web/scripts/run-hechima-worker-test.mjs)
  （`npm run test:hechima` の一部）: ビルド済み worker を環境スタブ内で実行し、
  `connectWorker` との実往復で RPC 配管（id 相関・ready 待機ゲート・resize 機能検出・
  null 契約・init 前 convert・範囲外 resize）を実 Mozc で検証。wasm 不在なら skip
  （CI は web-test.yml が Release から取得）
- 変換の正しさ自体は `run-hechima-golden.mjs`（セッション・ゴールデン）の守備範囲

## 6. 消費者

- **オンライン日本語入力ラボ**（新設サイト、Cloudflare）: `hechima-worker.js` +
  `connectWorker` をそのまま使う想定
- **QuuBee**: 独自の `mozc-worker.js`（本 worker の原型）を使用中。`hechima-worker.js` +
  `connectWorker` への置き換えは**任意**（電文は同系だが init の応答形など細部が異なる。
  置き換える場合は bridge.js の RPC 相関コードを `connectWorker` に委譲できる）
