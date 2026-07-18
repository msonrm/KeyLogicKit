# KeymapEngine 単体バンドル — 組み込みガイド / 仕様

`web/src/engine` の入力エンジン（キーマップ配列変換 → かな解決）を、React / DOM / Next に依存しない
1 ファイルにまとめて外部ホスト（QuuBee 等）へ配布するための公開 API とビルド手順、そして
アダプタ設計に必要な仕様の明確化をまとめる。

- **スコープ**: 物理キー入力 → かな解決まで。**かな漢字変換は含まない**（辞書変換はホスト側 IME / Mozc が担当）。
- **正しさの正典**: `Tests/golden/cases/*.json`（ゴールデンコーパス）。エンジン改善は「ファイル差し替え」で取り込み側に入る。
- 関連: [`web/README.md`](../web/README.md) / [`docs/keymap-format.md`](keymap-format.md) / [`Tests/golden/README.md`](../Tests/golden/README.md)

## 1. ビルド

```bash
cd web
npm run build:engine     # public/engine/keymap-engine.js（可読 UMD）+ keymap-engine.min.js（minify）
npm run test:engine      # build:engine → node で require してゴールデンケースを実行
```

- バンドラは Vite 8 同梱の **rolldown** を使用（追加の devDependency なし）。スクリプトは [`web/scripts/build-engine.mjs`](../web/scripts/build-engine.mjs)。
- **形式**: UMD。ブラウザの素の `<script>`、Worker の `importScripts`、node の `require` の 3 通りで読める。
  グローバル名は **`KeymapEngine`**。ESM 専用ではないのでバンドラ無しのプレーン script tag 構成でも取り込める。
- React / DOM / Next への依存は持たない（純ロジック）。依存が混入するとビルドが解決エラーで落ちる。
- **出力先 `web/public/engine/` はコミット対象**。取り込み側（QuuBee）は次のいずれかで 1 ファイルを入手する:
  - リポジトリから直接 vendor（`web/public/engine/keymap-engine.min.js` を clone / 認証付き raw 取得）。取り込みバージョンは commit SHA と `KeymapEngine.version` で記録。
  - Vercel デプロイ先の固定 URL `<labo-site>/engine/keymap-engine.js` から取得（常に最新）。
  - エンジンを変更したら `npm run build:engine` を再実行してコミットし直す（成果物とソースを同期）。

## 2. 公開 API（`KeymapEngine.*`）

| シンボル | 種別 | 説明 |
|---|---|---|
| `version` | `string` | このバンドルのバージョン。取り込み側が記録する。API・打鍵挙動を変えたら SemVer で更新される |
| `decodeKeymap(json)` | `(unknown) → ExpandedKeymap` | keymap JSON を検証しつつ `InputEngine` に渡せる形へ展開。`formatVersion` メジャー不一致は明確なエラー |
| `InputEngine` | `class` | 入力エンジン本体（下記メソッド一覧） |
| `keyEventFromBrowser(e)` | `(BrowserKeyLike) → KeyEvent \| null` | DOM `KeyboardEvent` 風オブジェクトから `KeyEvent` を組み立てる便宜関数。未知 code は `null` |
| `browserCodeToHID(code)` | `(string) → number \| undefined` | `KeyboardEvent.code`（"KeyA" 等）→ HID usage code の生テーブル |
| `hidNameToCode(name)` | `(string) → number \| undefined` | HID usage 名（"a" / "space" / "international4" 等、JSON キーマップの表記）→ HID code |
| `hidNameToBrowserCode` / `hidCodeToName` | 関数 | 逆引き補助 |
| `KeyModifierFlags` | `object` | 修飾キーのビットフラグ定数（下記） |
| `expandKeymap` / `decodeKeymapDefinition` | 関数 | 低レベル API（定義だけ欲しい場合。通常は `decodeKeymap` で足りる） |
| `createBuiltinRomajiUS` / `createBuiltinRomajiJIS` | `() → ExpandedKeymap` | 組み込み標準ローマ字テーブル |

### InputEngine のメソッド

| メソッド | 説明 |
|---|---|
| `constructor(keymap: ExpandedKeymap)` | `decodeKeymap()` の結果を渡す |
| `processKey(event: KeyEvent): EngineState` | keydown を処理し、更新後の状態を同期で返す |
| `processKeyUp(event: KeyEvent): EngineState` | keyup を処理（chord バッファのシフトホールド判定等に必要） |
| `getState(): EngineState` | 現在の状態を取得 |
| `setKeymap(keymap: ExpandedKeymap): void` | 配列を切り替え（composing 中なら確定してから） |
| `reset(): void` | 全状態を初期化（confirmed / composing / mode / バッファ） |
| `onStateChange: (() => void) \| null` | **タイマー駆動の chord 確定などを通知するコールバック**（§5.2） |
| `onHostAction: ((action: KeyAction) => boolean) \| null` | **編集・移動・確定アクションのホスト委譲フック**（§5.6、v1.1.0+。v1.2.0 で convert/confirm/insertAndConfirm も転送） |
| `takeConfirmedText(): string` | 確定テキストを取り出して内部を空にする（差分取り出し。§5.3） |
| `setSimultaneousWindow(ms: number \| null): void` | 同時打鍵ウィンドウ(ms)を上書き。`null` でキーマップ既定に戻す（`judgment: "mutual"` の配列では無視される） |
| `isChord: boolean` (getter) | この配列が同時打鍵方式か |

### EngineState

```ts
interface EngineState {
  confirmedText: string;   // 確定済みテキスト（accumulate。takeConfirmedText で引き取り可）
  composingKana: string;   // 変換前の確定かな（未確定）
  pendingBuffer: string;   // 逐次バッファの生の保留文字列（ローマ字途中など）
  pendingDisplay: string;  // 上記を表示用にかな仮解決したもの
  inputMode: "japanese" | "english";
  isComposing: boolean;    // composingKana か pendingBuffer に中身があるか
}
```

`KeyEvent` / `KeyModifierFlags`:

```ts
interface KeyEvent { keyCode: number; characters: string; modifiers: number; }
const KeyModifierFlags = { SHIFT: 1, CONTROL: 2, ALT: 4, META: 8 };
```

## 3. 最小統合例

```html
<script src="keymap-engine.js"></script>
<script>
  const raw = await (await fetch("keymaps/naginata_us.json")).json();
  const engine = new KeymapEngine.InputEngine(KeymapEngine.decodeKeymap(raw));

  // タイマー駆動の chord 確定を拾う（§5.2）
  engine.onStateChange = () => render(engine.getState());

  addEventListener("keydown", (e) => {
    if (e.repeat) return;                          // OS オートリピートは呼び元でフィルタ（§5.1）
    const ev = KeymapEngine.keyEventFromBrowser(e);
    if (!ev) return;                               // 変換テーブルに無いキーはゲストへ透過
    e.preventDefault();
    render(engine.processKey(ev));
  });
  addEventListener("keyup", (e) => {
    const ev = KeymapEngine.keyEventFromBrowser(e);
    if (ev) engine.processKeyUp(ev);
  });

  function render(state) {
    const confirmed = engine.takeConfirmedText();  // 確定分を Mozc へ流す
    if (confirmed) sendToMozc(confirmed);
    showComposition(state.composingKana + state.pendingDisplay);
  }
</script>
```

## 4. ゴールデンテストの再利用

`Tests/golden/cases/*.json` は「キーイベント列（down/up + wait）→ 期待かな出力列」を素データで記述したもの。
node 単体ランナー [`web/scripts/run-golden-node.mjs`](../web/scripts/run-golden-node.mjs) がビルド済みバンドルを
`require` して回すので、QuuBee 側の統合回帰でも同じケース・同じ回し方を流用できる。形式仕様は
[`Tests/golden/README.md`](../Tests/golden/README.md)。

タイミングを決定的に扱うため、ランナーはグローバルの `setTimeout` / `clearTimeout` を仮想クロックへ差し替える。
実ブラウザ（QuuBee 実行時）は本物のタイマーを使うので、`wait` を実スリープで再現するか、
同様に仮想クロックを差し込む（境界ちょうどのケースは実時間では非決定的なので web 限定にしてある）。

---

## 5. 仕様の明確化（アダプタ設計向け Q&A）

### 5.1 KeyEvent の正確な形

```ts
interface KeyEvent { keyCode: number; characters: string; modifiers: number; }
```

- **`keyCode`**: **HID Usage code**（USB HID Usage Tables の値。例: A=0x04, Space=0x2c, international4=0x8a）。
  ブラウザの `KeyboardEvent.keyCode`（非推奨）でも `.code`（文字列）でもない。
  `.code` からは `browserCodeToHID("KeyA")` で変換する（`keyEventFromBrowser` が内部で使用）。
  変換テーブルは [`web/src/engine/hid-key-codes.ts`](../web/src/engine/hid-key-codes.ts)。
- **`characters`**: そのキーが生成する文字（`KeyboardEvent.key` が 1 文字ならそれ）。
  逐次（ローマ字系）配列のルーティングと、英字モードの生入力（`directInsert`）で使う。
  同時打鍵（chord）配列では `keyCode` が主で `characters` は基本未使用。US 配列のシフト記号など
  `.key` と物理キーがずれる場合に正しい文字を載せるためのフィールド。
- **`modifiers`**: `KeyModifierFlags`（SHIFT=1 / CONTROL=2 / ALT=4 / META=8）のビット OR。
- **timestamp は無い**。`KeyEvent` はタイムスタンプを持たず、エンジンはタイムスタンプを一切消費しない。
  時間窓方式（`judgment: "window"`）の同時打鍵判定は**エンジン内部の `setTimeout`（ホストの時計）**で行う（§5.2）。単位は ms。
  → 呼び元はイベントの時刻を渡す必要がない。渡しても無視される。
- **OS オートリピート（`repeat=true` の keydown）はエンジンが無視しない**。素通しすると `processKey` が
  再入して同時打鍵バッファの状態を壊す（保持中キーの再押下として扱われる）。
  **呼び元が `KeyboardEvent.repeat === true` を必ずフィルタすること**（例は §3）。

### 5.2 chord の非同期解決（onStateChange）

- **内部タイマー駆動**。同時打鍵バッファ（[`simultaneous-buffer.ts`](../web/src/engine/simultaneous-buffer.ts)）は
  `setTimeout(window_ms)` で単打／同時打鍵／シフトホールドを判定する。
  `window_ms = round(keymap.behavior.config.simultaneousWindow[秒] × 1000)`（例: NICOLA 0.1→100ms、薙刀式 0.08→80ms）。
  `engine.setSimultaneousWindow(ms)` で上書き可能。
- **打鍵の即時出力は同期**（`processKey` の戻り値に反映済み。1 打目は eager 出力し、2 打目で同時打鍵成立なら巻き戻して差し替え）。
  一方、**ウィンドウ満了を待って初めて決まる確定**（単打の確定、シフト単打アクション、遅延 specialAction 等）は
  後から非同期に届く。これを **`onStateChange` コールバック**で通知する。
- 呼び元の実装:
  ```js
  engine.onStateChange = () => render(engine.getState());
  ```
  `onStateChange` は「`processKey`/`processKeyUp` の戻り値だけでは拾えない状態変化」で呼ばれる
  （タイマー満了時が主。eager 出力時に同期で呼ばれることもあるが冪等なので、常に最新 `getState()` を読めばよい）。
- **期待タイミング**: 最後の関連 keydown / keyup から概ね `window_ms`（80〜100ms）後に `onStateChange` が来る。
  ホストの `setTimeout` 精度に依存するが、ウィンドウはブラウザ/nodeの最小クランプ（~4ms）より十分大きいので実用上問題ない。
- **決定的テスト**: グローバル `setTimeout` を仮想クロックに差し替えれば時間を厳密に進められる
  （ゴールデンランナーがこの方式）。
- **`judgment: "mutual"`（相互シフト、v1.3.0+）**: 薙刀式など状態ベース判定の配列は
  **タイマーを一切使わない**。chord は 2 キー目の keydown、単打確定は keyup で、
  すべて `processKey` / `processKeyUp` の呼び出し内に同期解決される
  （`onStateChange` は従来どおり配線してよいが、mutual ではタイマー起因の遅延通知は発生しない）。
  `setSimultaneousWindow` は無視される。keymap 側の仕様は
  [`docs/keymap-format.md`](keymap-format.md) の「judgment: 判定方式」を参照。
- **英数モードの chord 解釈（v1.4.0+）**: `englishLookupTable` を持つ配列（薙刀式等）は、
  英数モード（`switchToEnglish` 後）でも chord バッファでキーを解釈する（iOS と同じ設計）。
  単打面は素の英字なので通常タイプはそのまま流れ、`englishSpecialActions`
  （H+J = switchToJapanese）と `englishLookupTable` のシフト面（space+X = 大文字）が機能する。
  修飾キー付き（Shift+h = H、Ctrl 系ショートカット）とキーマップ外キーは chord に参加せず
  直接挿入。`englishLookupTable` の無い配列（NICOLA 等）は従来どおり英数モードで全キー直接挿入。
  英数の chord 出力は composition を経由せず `confirmedText` へ直行する。

### 5.3 confirmedText の運用

- `getState().confirmedText` は確定かなを **accumulate し続ける**（自動クリアしない）。
- 確定分だけを引き取って別バッファ（QuuBee → Mozc）へ流したい場合は **`takeConfirmedText()`** を使う。
  確定テキストを返し、内部 `confirmedText` を空にする。`composing` / `inputMode` には影響しない。
  ```js
  const confirmed = engine.takeConfirmedText();  // 例: "あき"
  if (confirmed) mozc.push(confirmed);
  ```
  - これで毎回の差分取り（前回長を覚えて suffix を取る）は不要。
  - **注意**: 取り出し後は `confirmedText` が空になるため、composing が空のときの `deleteBack` は
    エンジン内で消す対象を持たない（＝確定済みテキストの所有権はホスト側へ移る）。薙刀式の BS を
    「composing 中 = バッファ操作 / バッファ空 = ゲストへ実キー注入」で二重経路にする設計と整合する。
- `takeConfirmedText()` を使わず accumulate のまま使うことも可能（`getState().confirmedText` を表示にそのまま使う等）。

### 5.4 KeyAction の語彙

**重要**: この web エンジンでは **KeyAction は完全に内部表現**であり、呼び元へは surface しない。
呼び元が触るのは `processKey`/`processKeyUp` と `EngineState` だけ。
（KeyLogicKit(Swift) では `KeyRouter.route` が `KeyAction` をアプリ層へ返すが、web の `InputEngine` は
`routeKey` → `executeAction` を内部で閉じている。）

各 `KeyAction`（[`types.ts`](../web/src/engine/types.ts)）の意味と `EngineState` への作用:

| KeyAction | 発火元 | EngineState への作用 |
|---|---|---|
| `printable{char}` | 文字キー（逐次） | 逐次バッファ経由で `composingKana` にかなを追加 |
| `chordInput{key}` / `chordShiftDown{key}` | 文字キー（chord） | 同時打鍵バッファへ keyDown（結果は eager 出力 or タイマー後に `composingKana`） |
| `convert` | シフト単打(convert) / idle 時スペース | composing 中 = 確定 / idle = 全角(日) or 半角(英)スペース挿入 |
| `confirm` | Enter/Tab/Space(composing)/Ctrl+M/Ctrl+J / specialAction | `composingKana` を `confirmedText` へ確定 |
| `cancel` | Escape / Ctrl+G / specialAction | composing を破棄 |
| `deleteBack` | Backspace / Ctrl+H / specialAction | バッファ → composing → confirmed の順に 1 文字削除 |
| `moveLeft`/`moveRight`/`moveUp`/`moveDown`/`editSegmentLeft`/`editSegmentRight` | specialAction | **web はカーソル制御を持たないため composing を確定**（要ホスト側の二重経路対応） |
| `toggleInputMode` | modeKeys | 確定してから `inputMode` を反転 |
| `switchToEnglish` | modeKeys / specialAction | 確定してから英字モードへ |
| `switchToJapanese` | modeKeys / specialAction | 日本語モードへ（確定はしない。chord バッファはリセット） |
| `insertAndConfirm{text}` | specialAction `insertAndConfirm:X` | `text` を composing に足して確定（例: 。/ 、） |
| `directInsert{text}` | 英字モードの印字キー | `characters` をそのまま `confirmedText` へ |
| `insertSpace{shifted}` | idle 時スペース（逐次） | 全角/半角スペースを `confirmedText` へ |
| `pass` | 該当なし | 何もしない（§5.5） |

- **呼び元へ surface される KeyAction は無い**（すべて `executeAction` が内部消費）。観測できるのは `EngineState` の変化のみ。
- 型に定義はあるが現行 web エンジンが**生成しない**もの: `convertPrev`（予約・未使用）、`chordKeyUp`
  （keyup は `processKeyUp` が `executeAction` を介さず直接 chord バッファへ渡すため）。

### 5.5 `pass` アクションの意味論

- `pass` = **エンジンは何もしない**（`executeAction` の `pass` は no-op。挿入も削除もしない）。
- QuuBee の「ゲスト（DOS 側）へキー透過」に使う解釈は **正しい**。ただし文脈で扱いが分かれる:
  - **composing 中の `pass` = 消費（スワロー）**。変換中に IME が扱わないキーを漏らさないため、
    web アプリはキーを飲む（`routeKey` の設計: 「composing 中はキーを消費」）。→ この間はゲストへ流さない。
  - **idle（composing 空）の `pass` = 透過候補**。エンジンが関与しないので、呼び元がゲストへ流してよい。
- エンジンは `processKey` の戻り値で「pass だったか（消費したか）」を明示しない（KeyAction を surface しないため）。
  呼び元は **`EngineState.isComposing` と `inputMode` でゲート**するのが推奨:
  - IME OFF / パススルーモード → そもそもエンジンへ入れず、ゲストへ直送。
  - IME ON → 全キーをエンジンへ。`isComposing` が false のまま状態が変わらないキー（未マップ記号等）は
    ホスト側でゲストへ流す。`keyEventFromBrowser` が `null`（変換テーブル外の code）を返すキーも同様に透過。
- 「編集系アクションの二重経路」（composing 中 = バッファ操作 / バッファ空 = PC-98 実キー注入）は、
  `getState().isComposing` を見てホスト側で分岐する（薙刀式のカーソル・BS・言語切替がここに乗る）。

### 5.6 `onHostAction` — 編集・移動アクションのホスト委譲（v1.1.0+）

エンジンは文書を所有しない（確定テキストは `takeConfirmedText` でホストへ渡る）ため、
カーソル移動や空バッファでの BS は「ホスト文書への操作」としてホストに委譲する必要がある。
`onHostAction` はそのための**エンジン既定処理の前に呼ばれるフック**:

```js
engine.onHostAction = (action) => {
  // action.type: "moveLeft" | "moveRight" | "moveUp" | "moveDown"
  //            | "editSegmentLeft" | "editSegmentRight" | "deleteBack"
  // true を返す = ホストが消費（エンジン既定を実行しない）
  // false / 未設定 = エンジン既定（move* = 確定 / deleteBack = バッファ末尾削除）
};
```

- **対象アクション**: `moveLeft` / `moveRight` / `moveUp` / `moveDown` /
  `editSegmentLeft` / `editSegmentRight` / `deleteBack`、および v1.2.0+ で
  `convert` / `confirm` / `insertAndConfirm`（候補選択 UI を持つセッション層が
  「次候補」「結合確定」等に読み替えるための先取り。未消費なら既定どおり確定/挿入）。
- **発火源は 2 系統とも通る**: routeKey 由来（composing 中の実矢印キー・BS）と
  chord specialAction 由来（薙刀式 T/Y/U 等）のどちらも `executeAction` 経由でこのフックに来る。
- **未設定なら挙動は従来と完全互換**（v1.0.0 と同じ）。
- 変換セッション層 **hechima**（`docs/hechima-session-embedding.md`）はこのフックを使って
  「候補選択中 = 文節移動 / 合成中 = 飲む or エンジン既定 / 空 = `cb.hostKey` で実キー委譲」の
  三状態に振り分ける。**旧方式（`engine.chordBuffer.onSpecialAction` を外から wrap する横取り）は
  不要になった**ので使わないこと（内部プロパティへの依存で、エンジン更新で壊れる）。
