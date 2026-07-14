# Hechima（変換セッション層）単体バンドル — 組み込みガイド / 仕様

`web/src/hechima` の変換セッション層（よみ入力 → 非同期変換 → 複数文節の候補選択 → 確定 →
編集キー二重経路）を、React / DOM / Next に依存しない 1 ファイルにまとめて外部ホスト
（QuuBee 等）へ配布するための公開 API とビルド手順。QuuBee HLE FEP の `fep.js`（実証済みの
純状態機械）を labo に移管したもの（依頼書: `docs/hechima_session_handoff.md`）。

- **スコープ**: 入力体験のセッション制御。**配列エンジンは含まない**（`setEngine` で注入。無ければ内蔵ローマ字）。
  **かな漢字変換も含まない**（`cb.convert` で注入。無ければフォールバック = カナ/かな巡回）。
- **レイヤ**: `hechima`（セッション）→ `hechima-keymap`（= KeymapEngine。setEngine で注入）
  ＋ `hechima-wasm`（= Mozc wasm。cb.convert で注入）。変換エンジンは差し替え可能な内部部品
  （API 境界 = かな→文節/候補 JSON）。
- **正しさの正典**: `web/src/hechima/golden/*.json`（セッション・ゴールデン）。
- 関連: [`docs/keymap-engine-embedding.md`](keymap-engine-embedding.md) /
  [`hechima-wasm/README.md`](../hechima-wasm/README.md)

## 1. ビルド

```bash
cd web
npm run build:hechima    # public/hechima/hechima.js（可読 UMD）+ hechima.min.js（minify）
npm run test:hechima     # build:engine + build:hechima → node でゴールデンを実行
```

- 形式は **UMD、グローバル名 `Hechima`**（`<script>` / `importScripts` / `require` の 3 通り）。
- バンドルは約 12KB（KeymapEngine へは**型のみ参照**なので同梱されない = 分離ベンダリング可能）。
- 出力先 `web/public/hechima/` はコミット対象。型定義は手書きの
  [`hechima.d.ts`](../web/public/hechima/hechima.d.ts)（cb 契約の明文化を兼ねる）。
- タグ付き GitHub Release（`hechima-v*`）にも添付する。取り込み側は `Hechima.version` を記録する。

## 2. cb 契約（ホストの差し替え点。5 点）

`Hechima.createFep(cb)` に渡すコールバック。**ホスト固有物はすべてここに閉じる**
（QuuBee = PC-98 VRAM/SJIS、エディタ = DOM、試打サイト = 表示要素）:

| コールバック | 型 | 意味 |
|---|---|---|
| `show(segments)` | `({text, kind})[]` | 未確定表示を描画。`kind`: `yomi`（未確定よみ）/ `focus`（注目文節）/ `other`（非注目） |
| `hide()` | | 表示消去（バッファが空になった） |
| `commit(text)` | `string` | 確定文字列を出力。**呼び元が hide → 注入の順で処理する**（セッションは commit 時に hide を呼ばない） |
| `hostKey(name)` | `string`（省略可） | ホスト文書へ実キーを 1 打注入（name = `KeyboardEvent.code` 名: `'ArrowLeft'` / `'Backspace'` 等）。編集キー二重経路の委譲先 |
| `convert(yomi)` | `(string) → Promise<[{key, candidates}] \| null>`（省略可） | かな漢字変換。null/省略/失敗 = フォールバック（よみ 1 文節・カナ/かな巡回） |
| `resize(segIdx, offset)` | `(number, number) → Promise<[{key, candidates}] \| null>`（省略可、v0.2.0+） | 文節伸縮（hechima-wasm v0.2.0+ の `hechima_resize`）。offset はよみ文字数（±）。null/空/失敗 = 伸縮不能（現状維持）。未提供なら editSegment* は無害に飲まれる |

## 3. 公開 API（`Hechima.*`）

| シンボル | 説明 |
|---|---|
| `version` | このバンドルのバージョン（SemVer） |
| `createFep(cb) → FepSession` | セッションを作る |
| `resolveRomaji(kana, pend, flush)` | 内蔵ローマ字リゾルバ（診断・テスト用） |
| `fallbackConvert(yomi)` | フォールバック変換（診断・テスト用） |

`FepSession`（fep.js の返り値オブジェクトと同一契約）:

| メンバ | 説明 |
|---|---|
| `active` (getter) / `setActive(on)` / `toggle()` | セッション ON/OFF。OFF は未確定を破棄 |
| `feed(e) → bool` | keydown 1 個を消費。**true = 飲んだ**（ホストへ送らない → `preventDefault`）。`e` は `{key, code?, repeat?, ctrlKey?...}` の KeyboardEvent 互換 |
| `feedUp(e) → bool` | keyup を消費（SandS の単打 convert が発火）。内蔵ローマ字経路は常に false |
| `setEngine(engine, keyOf)` | KeymapEngine の `InputEngine` を注入（`null` = 内蔵ローマ字）。`keyOf` には `KeymapEngine.keyEventFromBrowser` をそのまま渡せる |
| `pumpEngine()` | `engine.onStateChange`（chord 窓満了）から呼ぶ |
| `reset()` | 全状態クリア |

## 4. 最小統合例

```html
<script src="keymap-engine.js"></script>
<script src="hechima.js"></script>
<script>
  const fep = Hechima.createFep({
    show(segments) { renderInline(segments); },
    hide() { clearInline(); },
    commit(text) { clearInline(); insertToDocument(text); },   // hide → 注入の順
    hostKey(name) { injectRealKey(name); },                    // 編集キー委譲
    convert(yomi) { return mozcWorkerRpc(yomi); },             // hechima-wasm 等
  });
  fep.setActive(true);

  // 新配列（keymap-format）を使う場合はエンジンを注入
  const raw = await (await fetch("keymaps/naginata_jis.json")).json();
  const eng = new KeymapEngine.InputEngine(KeymapEngine.decodeKeymap(raw));
  eng.onStateChange = () => fep.pumpEngine();                  // 配線はホスト側で行う
  fep.setEngine(eng, (tap) => KeymapEngine.keyEventFromBrowser(tap));

  addEventListener("keydown", (e) => { if (fep.feed(e)) e.preventDefault(); });
  addEventListener("keyup", (e) => { fep.feedUp(e); });
</script>
```

## 5. 編集キーの二重経路（`InputEngine.onHostAction` 経由）

薙刀式の T=moveLeft / Y=moveRight / U=deleteBack 等の編集アクションは、ホストが文書を
所有する構図では「セッション状態に応じて 3 通り」に振り分ける必要がある。hechima は
`setEngine` 時に **`engine.onHostAction`（KeymapEngine v1.1.0+ の正式 API）** を配線し、
以下の意味論で処理する（QuuBee 実証済み・golden 化済み）:

| アクション | Phase 2（候補選択中） | 変換前よみ合成中 | 空バッファ |
|---|---|---|---|
| `moveLeft` / `moveRight` | 注目文節を左右へ移動 | **飲む**（よみ内カーソルは持たない） | `cb.hostKey('ArrowLeft'/'ArrowRight')` |
| `deleteBack` | 取消（clear + hide） | **engine 既定**（composingKana 末尾削除） | `cb.hostKey('Backspace')` |
| `editSegmentLeft/Right` | **文節伸縮**（v0.2.0+）: `cb.resize(focus, ∓1)` → 再変換結果で差し替え・フォーカス維持（結合で減った分は clamp）。`cb.resize` 未提供なら飲む | 飲む（確定に倒さない） | 飲む |

- 旧方式（QuuBee が暫定でやっていた `engine.chordBuffer.onSpecialAction` の外部 wrap）は
  **撤去してよい**。`onHostAction` が同じ判定点をエンジンの正式 API として提供する。
- `onHostAction` は routeKey 由来（composing 中の実矢印キー・BS）にも発火する。このため
  **composing 中の実 ←→ は「確定」ではなく「飲む」に変わる**（旧 fep.js + wrap では
  moveLeft→confirmComposition で変換開始まで走っていた。新挙動のほうが実 IME に近い）。

## 6. ゴールデンテストの再利用

`web/src/hechima/golden/*.json` が「キー/タップ列 → 期待 show/commit/hostKey」の素データ。
node ランナー [`web/scripts/run-hechima-golden.mjs`](../web/scripts/run-hechima-golden.mjs) が
ビルド済み UMD を `require` して回す（QuuBee の統合回帰でも同じケースを流用できる）。
形式（steps / expect の語彙）はランナー冒頭のコメント参照。カバレッジ:

1. ローマ字 n 規則（konnichiha / minna / nn 単独 / xtu / 促音）
2. 句読点即確定（空 = 全角即確定、文中 = composition 内全角、数字 = 透過）
3. in-flight race（変換待ち中の打鍵で古い結果を世代トークンで破棄）
4. 複数文節（focus 移動・注目文節だけ候補送り・Enter 結合確定・Escape 戻し・追加入力確定）
5. 編集キー二重経路（空 / Phase 2 / 合成中 × T/Y/U。specialAction 直接発火 + 実打鍵 E2E）
6. 実変換 E2E（hechima-wasm 接続で kyouhaiitenkidesune → 今日はいい天気ですね。
   `hechima-wasm/dist/` にバンドル + 辞書が無ければ skip。env `HECHIMA_WASM_JS` / `MOZC_DATA` で上書き可）
7. 文節伸縮（v0.2.0+: Phase 2 の editSegment → `cb.resize` 呼び出し・resize 未提供/合成中は飲む・
   実 Mozc での -1 → +1 ラウンドトリップ。`hechima_resize` 未搭載の wasm では E2E ケースを skip）

タイミングは仮想クロックで決定的に進める（mozc E2E のみ実タイマー — wasm 初期化と干渉するため）。

## 7. QuuBee 側の追随（参考。labo の作業対象ではない）

- `web/assets` に `hechima.js` を vendoring、`fep.js` のセッション核を `Hechima.createFep` へ差し替え
  （bridge.js の cb 実装 = VRAM show / SJIS commit / PC-98 hostKey / mozc-worker convert は残す）。
- `setEngine` 内の暫定 `onSpecialAction` wrap を撤去（hechima が `onHostAction` を配線する）。
  **KeymapEngine も v1.1.0 以上に更新すること**（onHostAction が無いと編集キーが二重経路にならない）。
- 回帰 `fep_mozc_test` / `fep_naginata_edit_test` が緑のままを確認
  （naginata edit の Part A は `web/src/hechima/golden/naginata_edit.json` と同等）。
- 文節伸縮（v0.2.0）を使うには: hechima-wasm を **v0.2.0** に差し替え（`hechima_resize` 追加。
  convert の入出力は互換）、mozc-worker に `hechima_resize` の RPC を足し、cb に
  `resize(segIdx, offset)` を実装する。薙刀式 space+T/Y が Phase 2 で文節伸縮になる。
