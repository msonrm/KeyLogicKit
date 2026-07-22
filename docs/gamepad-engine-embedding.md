# GamepadEngine（ゲームパッド日本語入力フロント）単体バンドル — 組み込みガイド / 仕様

ゲームパッド（W3C Standard Gamepad Layout）駆動の**日本語かな入力フロント**。左手＝子音行・
右手＝母音の同時押しでかなを解決し、UMD 1 ファイルで提供する。hechima セッション
（[`hechima-session-embedding.md`](hechima-session-embedding.md)）へ注入して変換込みの
日本語入力を成立させる。マッピングの全体像は [`gamepad-mapping.md`](gamepad-mapping.md)。

```
GamepadEngine.start（Gamepad API を rAF ポーリング）
  → 状態機械（machine.ts・純ロジック）+ 右スティック/LS/RS エッジ検出
  → GamepadOp 列 → ホストが FepSession へ配線（insertKana / feed）→ 変換
GamepadEngine.mount（DOM ビジュアライザ・任意）← onState で毎フレーム更新
```

- 実装: labo `web/src/gamepad/`。keymap-engine / hechima / flick と同じ配布パターン
  （成果物コミット + Vercel 静的配信 + Release 添付なし = labo main から取得）
- **hechima v0.13.0+（`insertKana`）とセットで使う**。KeymapEngine は不要
  （ゲームパッドは配列エンジンを使わずかなを直接解決する。`fep.setEngine(null)` の内蔵経路）
- **日本語のみ**。試打サイトの英語 T9・韓国語 2ボル式・中国語は含まない（それらは
  `web/src/engine/` + React の GamepadPage 側にのみ存在。この単体バンドルは日本語に絞ってある）

## 1. ビルド

```bash
cd web && npm run build:gamepad   # → public/gamepad/gamepad-engine.{js,min.js}
npm run test:gamepad              # ビルド + resolver ゴールデン（node）
```

グローバル名 `GamepadEngine`、UMD（`<script>` / `importScripts` / `require`）。約 24KB（min 12.6KB）。
取り込み側（へちま言語ラボ等）は `GamepadEngine.version` を記録する。成果物 `public/gamepad/` は
コミット対象。エンジン改変時は `build:gamepad` を再実行してコミットし直す。

## 2. 公開 API（`GamepadEngine.*`）

| シンボル | 説明 |
|---|---|
| `version` | このバンドルのバージョン（SemVer） |
| `start(opts) → GamepadController` | Gamepad API の polling を開始（ブラウザ専用）。`opts = { onOp, getComposingTail, onState?, enabled? }` |
| `mount(container) → GamepadVisualizer` | 操作ビジュアライザ（日本語）を container に生成。`{ update(state), destroy() }` |
| `createResolver(host) → GamepadResolver` | rAF・タイマー抜きの純核（自前ループ・テスト用）。`stepFrame(frame)` / `action(a)` / `syncPrev(f)` / `reset()` |
| `resolveYouonOp(tail)` / `resolveDakutenOp(tail)` | 合成末尾に拗音後置シフト / 濁点トグルを適用した置換 op（診断・テスト用） |
| `createMachineState()` / `stepJapanese(f, s)` | 低レベル状態機械（診断用） |

`GamepadController`: `setEnabled(on)`（入力の有効/無効。無効中もビジュアライザは更新される）/
`stop()`（polling 停止 + イベント解除）/ `connected`（接続状態）。

## 3. GamepadOp の配線（ホストの責務）

`onOp(op)` に届く操作列を次のように配線する（フリックの FlickOp と同じ二語彙）:

| op | 配線 | 説明 |
|---|---|---|
| `{type:"kana", text, replace}` | `fep.insertKana(text, replace)` | かな注入。`replace > 0` は eager 巻き戻し・拗音（か→きゃ）・濁点トグルの末尾置換 |
| `{type:"key", tap}` | `fep.feed(tap)` → **false（未消費）ならホストのエディタ操作として実行** | 機能キー・ナビゲーション（下表） |

`{type:"key"}` の `tap.key` 一覧と、hechima セッションでの解釈（セッションが自身の状態で振り分ける）:

| tap（key ± 修飾） | ゲームパッド操作 | composing / Phase 2 | idle |
|---|---|---|---|
| `"Backspace"` | R🕹← | 末尾削除 / よみに戻す | ホストが 1 字削除 |
| `"Enter"` | LS 押込み・R🕹↓ 3連 | 確定 / 結合確定 | `feed` が false → ホストが改行挿入 |
| `"Escape"` | RS 押込み | 取消 | false → 無反応 |
| `" "`（Space） | L🕹↓（**合成中のみ**） | 変換開始 / 次候補 | — |
| `"ArrowDown"` | L🕹↓（**未入力時**） | — | カーソル下（v1.3.0+。未入力時に Space だと空白が入るのを回避） |
| `"ArrowUp"` | L🕹↑ | 前候補 | カーソル上 |
| `"ArrowLeft"` / `"ArrowRight"` | L🕹← / → | 文節移動 | false → ホストがカーソル移動 |
| `"ArrowLeft"` / `"ArrowRight"` + `shiftKey` | **RT + L🕹← / →** | **文節伸縮**（v1.2.0+） | false |
| `"Backspace"` + `ctrlKey` | **Start**（戻す） | **確定アンドゥ**（v1.2.0+） | false → ホストが文書 undo |

`{type:"key"}` の二重経路はフリック・物理キーボードと同一。**Space・矢印・Shift+矢印・Ctrl+BS は
そのまま `fep.feed(tap)` に流すだけ**で、変換・候補送り・文節移動・文節伸縮・確定アンドゥが成立する
（セッションが状態で解釈する）。`tap.shiftKey` / `tap.ctrlKey` を落とさず feed へ渡すこと。
`confirmOrNewline` は composing 中なら `feed("Enter")` がセッション内で確定処理し、idle なら false を
返すのでホストが改行を挿入する。Start（確定アンドゥ）は hechima のフリック「戻す」ボタンと同一挙動
（`applyFlickHostKey` が `Ctrl+BS` を文書 undo に落とす経路をそのまま流用できる）。

## 4. 最小統合例（hechima へ注入）

```html
<script src="hechima.js"></script>
<script src="gamepad-engine.js"></script>
<script>
  const conn = Hechima.connectWorker(new Worker("hechima/hechima-worker.js"));
  conn.init();

  let composingText = "";                       // cb.show から控える（getComposingTail 用）
  const fep = Hechima.createFep({
    show(segments) { composingText = segments.map(s => s.text).join(""); renderInline(segments); },
    hide() { composingText = ""; clearInline(); },
    commit(text) { composingText = ""; clearInline(); insertToDocument(text); },  // hide → 注入の順
    hostKey(name) { injectRealKey(name); },
    ...conn.callbacks(),                         // convert + resize
  });
  fep.setActive(true);
  // ゲームパッドは配列エンジンを使わない → setEngine は不要（既定の内蔵経路）

  const viz = GamepadEngine.mount(document.getElementById("gp-visualizer"));
  const ctl = GamepadEngine.start({
    getComposingTail: () => composingText,       // 拗音/濁点の対象特定に使う
    onState: viz.update,                         // ビジュアライザ更新
    enabled: false,                              // エディタフォーカスで setEnabled(true)
    onOp(op) {
      if (op.type === "kana") fep.insertKana(op.text, op.replace);
      else if (op.type === "key") { if (!fep.feed(op.tap)) editorApplyKey(op.tap); }
    },
  });
  editorEl.addEventListener("focus", () => ctl.setEnabled(true));
  editorEl.addEventListener("blur", () => ctl.setEnabled(false));
</script>
```

- `editorApplyKey` はホストのエディタ操作（物理キーボードで feed が false を返したときと同じ経路を
  再利用するのが正道）。Backspace / Enter（改行）/ Escape を処理する。
- `getComposingTail` は **cb.show で受けた合成表示テキスト**を返す。拗音・濁点の置換対象特定に使う
  （セッションの表示が正 = BS で編集されてもずれない）。

## 5. 入力マッピング（日本語）

`start` が解決するのは試打サイトの日本語ゲームパッド入力と同一:

- **かな**: 左手（D-pad ±LB）で子音行、右手（RB/X/Y/B/A）で母音。同時押しで 1 字。
  eager output + 300ms 巻き戻し（`docs/gamepad-mapping.md` 参照）
- **LT** 単押し = 拗音後置シフト（か→きゃ・あ→ぁ、対象外は「っ」追加）、**LT+RT** = っ、**RT** 単押し = ん
- **右スティック**: ↑ = 濁点/半濁点トグル、→ = 長音「ー」、← = バックスペース、
  ↓ = 、→。→空白（400ms ダブルタップで昇格、3 連で確定）
- **左スティック**（v1.1.0+）: ↓ = 合成中は変換開始/次候補（Space）・**未入力時はカーソル下**
  （ArrowDown、v1.3.0+。空白の誤入力回避）、↑ = 前候補/カーソル上、←→ = 文節移動/カーソル移動。
  **RT + ←→ = 文節伸縮**（Shift+←→、v1.2.0+）。すべて `key` op として emit し、hechima セッションが
  状態で解釈する（§3 の表）。合成中かどうかは `getComposingTail()` の空判定で見る
- **LS 押込み** = 確定/改行、**RS 押込み** = キャンセル、**Start** = 確定アンドゥ（戻す、v1.2.0+）

> **試打サイトとの差分**: 試打サイトの web 実装（`useGamepadInput.ts`）は右スティックのみで、
> 左スティックの変換・候補・伸縮・アンドゥを実装していない（フル実装は GIME ネイティブ/Android のみ）。
> `GamepadEngine` は v1.1.0 で左スティックのナビゲーション emit、v1.2.0 で文節伸縮（RT+←→）と
> 確定アンドゥ（Start）を追加し、hechima 上での変換・候補・編集を単なる `feed` 配線で成立させる
> （`gamepad-mapping.md` の日本語 composing 仕様に対応）。RT+←→ の伸縮時は RT を「使用済み」に印を
> 付け、RT リリースで「ん」が誤発火しないようにしてある。

## 6. ビジュアライザ

`mount(container)` は日本語モードの操作ガイド（D-pad = 行 / フェイス = 母音 / 中央 = プレビュー /
右スティック = 記号）を DOM で生成する。`start({ onState: viz.update })` で毎フレーム更新される。
配色は CSS 変数で上書き可能:
`--ge-accent` / `--ge-panel-bg` / `--ge-key-bg` / `--ge-key-fg` / `--ge-muted` / `--ge-badge-bg` / `--ge-badge-fg`。

## 7. ゴールデンテストの再利用

`web/src/gamepad/golden/*.json` + `web/scripts/run-gamepad-golden.mjs`（`npm run test:gamepad`）。
フレーム列（派生入力）と抽象アクションを純核 `createResolver` に流し、疑似ホスト（かなバッファ +
キー履歴）への適用結果を検証する。カバレッジ: eager output + 巻き戻し・子音リリース抑止・
拗音（対象/非対象/空）・LT+RT=っ・RT=ん・濁点トグル（か→が→か・は→ば→ぱ→は）・
BS/取消/確定の feed。rAF・タイマー・右スティックのエッジ検出（polling 側）は実機確認。
