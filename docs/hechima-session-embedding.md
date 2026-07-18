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
  [`docs/hechima-protocol.md`](hechima-protocol.md)（電文 v0 = worker RPC 仕様） /
  [`hechima-wasm/README.md`](../hechima-wasm/README.md)

## 1. ビルド

```bash
cd web
npm run build:hechima    # public/hechima/hechima.js（可読 UMD）+ hechima.min.js（minify）
npm run test:hechima     # build:engine + build:hechima → node でゴールデンを実行
```

- 形式は **UMD、グローバル名 `Hechima`**（`<script>` / `importScripts` / `require` の 3 通り）。
- バンドルは約 16KB（KeymapEngine へは**型のみ参照**なので同梱されない = 分離ベンダリング可能）。
- v0.4.0+ は **`hechima-worker.js`**（hechima-wasm を動かす Worker 本体、IIFE。min 版も）を
  併せて出力する。`new Worker("hechima-worker.js")` で読み、`Hechima.connectWorker` で接続する
  （電文 v0。仕様は [`docs/hechima-protocol.md`](hechima-protocol.md)）。
- 出力先 `web/public/hechima/` はコミット対象。型定義は手書きの
  [`hechima.d.ts`](../web/public/hechima/hechima.d.ts)（cb 契約の明文化を兼ねる）。
- タグ付き GitHub Release（`hechima-v*`）にも添付する。取り込み側は `Hechima.version` を記録する。

## 2. cb 契約（ホストの差し替え点。5 点）

`Hechima.createFep(cb)` に渡すコールバック。**ホスト固有物はすべてここに閉じる**
（QuuBee = PC-98 VRAM/SJIS、エディタ = DOM、試打サイト = 表示要素）:

| コールバック | 型 | 意味 |
|---|---|---|
| `show(segments)` | `({text, kind, candidates?, candidateIndex?, additional?, additionalIndex?})[]` | 未確定表示を描画。`kind`: `yomi`（未確定よみ）/ `focus`（注目文節）/ `other`（非注目）。候補選択中は各文節に `candidates`（候補一覧、読み取り専用コピー）と `candidateIndex`（選択位置）が載る（v0.5.0+）。注目文節には展開済みの `additional`（追加候補 = ひらがな/カタカナ、↑ で段階展開）と `additionalIndex`（領域内選択中のみ）も載る（v0.6.0+）。UI は additional を通常候補の上に注釈付きで表示する |
| `hide()` | | 表示消去（バッファが空になった） |
| `commit(text)` | `string` | 確定文字列を出力。**呼び元が hide → 注入の順で処理する**（セッションは commit 時に hide を呼ばない） |
| `hostKey(name)` | `string`（省略可） | ホスト文書へ実キーを 1 打注入（name = `KeyboardEvent.code` 名: `'ArrowLeft'` / `'Backspace'` 等）。編集キー二重経路の委譲先 |
| `convert(yomi)` | `(string) → Promise<[{key, candidates}] \| null>`（省略可） | かな漢字変換。null/省略/失敗 = フォールバック（よみ 1 文節・カナ/かな巡回） |
| `resize(segIdx, offset)` | `(number, number) → Promise<[{key, candidates}] \| null>`（省略可、v0.2.0+） | 文節伸縮（hechima-wasm v0.2.0+ の `hechima_resize`）。offset はよみ文字数（±）。null/空/失敗 = 伸縮不能（現状維持）。未提供なら editSegment* は無害に飲まれる |
| `learn(segments)` | `({key, value})[] → void`（省略可、v0.8.0+） | 確定内容の学習通知（fire-and-forget）。候補選択中の確定時に よみ+確定表示値 の列で呼ばれる（英字合成の確定では呼ばれない）。connectWorker の callbacks() を繋げば Mozc の学習に流れる。ホストが同じイベントを自前蓄積して独自の再ランキングに使ってもよい |

## 3. 公開 API（`Hechima.*`）

| シンボル | 説明 |
|---|---|
| `version` | このバンドルのバージョン（SemVer） |
| `createFep(cb) → FepSession` | セッションを作る |
| `resolveRomaji(kana, pend, flush)` | 内蔵ローマ字リゾルバ（診断・テスト用） |
| `fallbackConvert(yomi)` | フォールバック変換（診断・テスト用） |
| `connectWorker(worker, opts?) → WorkerConnection`（v0.4.0+） | hechima-worker への接続（id 相関・ready 待機・resize 機能検出）。`conn.callbacks()` を cb にスプレッドすると convert/resize が配線される |
| `HECHIMA_PROTOCOL_VERSION`（v0.4.0+） | 電文プロトコル版数（[`hechima-protocol.md`](hechima-protocol.md)） |

`FepSession`（fep.js の返り値オブジェクトと同一契約）:

| メンバ | 説明 |
|---|---|
| `active` (getter) / `setActive(on)` / `toggle()` | セッション ON/OFF。OFF は未確定を破棄 |
| `feed(e) → bool` | keydown 1 個を消費。**true = 飲んだ**（ホストへ送らない → `preventDefault`）。`e` は `{key, code?, repeat?, ctrlKey?...}` の KeyboardEvent 互換 |
| `feedUp(e) → bool` | keyup を消費（SandS の単打 convert が発火）。内蔵ローマ字経路は常に false |
| `setEngine(engine, keyOf)` | KeymapEngine の `InputEngine` を注入（`null` = 内蔵ローマ字）。`keyOf` には `KeymapEngine.keyEventFromBrowser` をそのまま渡せる |
| `pumpEngine()` | `engine.onStateChange`（chord 窓満了）から呼ぶ |
| `selectCandidate(index) → bool`（v0.5.0+） | 候補選択中に注目文節の候補を直接選択。候補 UI の数字キー/クリックからホストが呼ぶ（キー routing には関与しない = どのキーで呼ぶかはホスト方針）。範囲外・非候補選択中は false |
| `reset()` | 全状態クリア |

## 4. 最小統合例

```html
<script src="keymap-engine.js"></script>
<script src="hechima.js"></script>
<script>
  // 実変換: hechima-worker（電文 v0）に接続すると convert/resize が cb 形で得られる。
  // 独自 worker を使う場合は convert(yomi) を自前実装してもよい（QuuBee 方式）
  const conn = Hechima.connectWorker(new Worker("hechima/hechima-worker.js"));
  conn.init();   // 既定 = worker と同階層の ./hechima-wasm.js + ./mozc.data
  const fep = Hechima.createFep({
    show(segments) { renderInline(segments); },
    hide() { clearInline(); },
    commit(text) { clearInline(); insertToDocument(text); },   // hide → 注入の順
    hostKey(name) { injectRealKey(name); },                    // 編集キー委譲
    ...conn.callbacks(),                                       // convert + resize（文節伸縮）
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

薙刀式の T=moveLeft / Y=moveRight / U=deleteBack、space+T/Y=editSegment、space 単打=convert、
M+V=confirm 等のアクションは、ホストが文書を所有する構図では「セッション状態に応じて 3 通り」に
振り分ける必要がある。hechima は `setEngine` 時に **`engine.onHostAction`（KeymapEngine
**v1.2.0+** の正式 API）** を配線し、以下の意味論で処理する（QuuBee 実証済み・golden 化済み）:

| アクション | Phase 2（候補選択中） | 変換前よみ合成中 | 空バッファ |
|---|---|---|---|
| `moveLeft` / `moveRight` | 注目文節を左右へ移動 | **飲む**（よみ内カーソルは持たない） | `cb.hostKey('ArrowLeft'/'ArrowRight')` |
| `deleteBack` | 取消（clear + hide） | **engine 既定**（composingKana 末尾削除） | `cb.hostKey('Backspace')` |
| `editSegmentLeft/Right` | **文節伸縮**（v0.2.0+）: `cb.resize(focus, ∓1)` → 再変換結果で差し替え・フォーカス維持（結合で減った分は clamp）。`cb.resize` 未提供なら飲む | 飲む（確定に倒さない） | 飲む |
| `convert`（SandS 単打等） | **次候補**（注目文節を送る）（v0.3.0+） | engine 既定（確定 → 変換開始） | engine 既定 |
| `confirm`（薙刀式 M+V 等） | **結合確定**（v0.3.0+） | engine 既定 | engine 既定 |
| `insertAndConfirm`（space+M=。等） | **現候補確定 + テキスト確定**（v0.3.0+） | engine 既定 | engine 既定 |

### Phase 2 のキー routing（v0.3.0 で修正）

**v0.2.0 以前は Phase 2 の全 keydown がセッションのナビ処理に直行し、engine に届かなかった**。
そのため space+T のような同時打鍵が Phase 2 では構造的に成立せず、editSegment* は実打鍵で
発火不能だった（QuuBee 報告 `docs/hechima_v020_phase2_chord_feedback.md`。おまけに space が
「次候補」、T が「確定+新規合成」に化ける三重奏）。v0.3.0 の routing:

- **ナビキー**（Enter / Escape / Backspace / ←→↑↓ — chord 語彙に参加しない実キー）→
  セッションが直接処理（結合確定・取消・文節移動・候補送り・**Shift+←→ = 文節伸縮**）
- **それ以外**（印字キー・SandS シフト = space 等）→ **engine へ流し、chord 解決の結果
  （specialAction / かな出力）で解釈**。SandS の tap/hold 判定は engine の専権のまま
- Phase 2 中に engine がかなを出力（= 追加入力）したら「現候補を確定して新規合成」
  （実 IME の標準挙動。pumpEngine が処理）
- keyup は従来どおり常に engine へ（SandS 単打の判定に必須）

### Shift+←→ = 文節伸縮（全配列共通、v0.3.0+）

標準 IME と同じく、**Phase 2 中の Shift+← / Shift+→ で注目文節を伸縮**する。セッション層の
機能なので**配列に依存しない** — 内蔵ローマ字でも任意の keymap でも、`cb.resize` さえ実装して
あれば効く（薙刀式の space+T/Y は同じ機能への配列固有ショートカットという位置づけになる）。
`cb.resize` 未提供なら飲む（候補表示を壊さない）。

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
8. Phase 2 の実打鍵 E2E（v0.3.0+: space+T 同時打鍵 → resize / space 単打 → 次候補 /
   M+V → 結合確定 / かな追加入力 → 確定して継続 / Shift+←→ → 伸縮。specialAction 直叩きでは
   検出できなかった routing バグの再発防止）
9. 候補公開 + 直接選択（v0.5.0+: show の candidates/candidateIndex・selectCandidate の
   範囲外/非 Phase 2 で false・focus 移動後の選択・確定への反映）
10. 英字合成 + 追加候補（v0.6.0+: Shift+英字 → as-typed 筆頭の綴りバリエーション変換・
    混在よみ・BS 全消しでモード終了 / ↑・Shift+Space の段階展開（ひらがな→カタカナ）・
    領域内往復・追加候補の確定）
11. 学習通知（v0.8.0+: 複数文節確定の learnCalls・追加候補確定の値・英字合成/よみのみ確定では
    呼ばない。worker テスト側で実 Mozc の学習 E2E = 2 位学習 → 筆頭反転）

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
- **v0.3.0（Phase 2 routing 修正 + Shift+←→）**: `hechima.js` と `keymap-engine.js`（**v1.2.0**）の
  **2 ファイル差し替えのみ**。QuuBee 側のコード変更は不要（cb.resize は v0.2.0 追随で配線済み）。
  keymap-engine が v1.1.0 のままだと Phase 2 の space 単打が全角スペース挿入に化けるので
  **必ずセットで**差し替えること。
