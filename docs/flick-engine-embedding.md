# FlickEngine（フリック入力フロント）単体バンドル — 組み込みガイド / 仕様

flickmap（`docs/flickmap-format.md`）駆動のタッチ入力フロント。フリックキーボード UI と
ジェスチャ解決（resolver）を UMD 1 ファイルで提供し、hechima セッション
（`docs/hechima-session-embedding.md`）へ注入して変換込みの日本語入力を成立させる。

```
FlickEngine.mount（DOM / pointer events）
  → FlickResolver（flickmap 駆動・純ロジック）
  → FlickOp 列 → ホストが FepSession へ配線（insertKana / feed）→ 変換
```

- 実装: labo `web/src/flick/`。keymap-engine / hechima と同じ配布パターン
  （成果物コミット + Vercel 静的配信 + Release 添付なし = labo main から取得）
- **hechima v0.13.0+（`insertKana`）とセットで使う**。KeymapEngine は不要
  （フリックは配列エンジンを使わない。`fep.setEngine(null)` の内蔵経路で動かす）

## 1. ビルド

```bash
cd web && npm run build:flick   # → public/flick/flick-engine.{js,min.js}
npm run test:flick              # ビルド + resolver ゴールデン（node）
```

グローバル名 `FlickEngine`、UMD（`<script>` / `importScripts` / `require`）。
取り込み側は `FlickEngine.version` を記録する。

## 2. 公開 API（`FlickEngine.*`）

| シンボル | 説明 |
|---|---|
| `version` | このバンドルのバージョン（SemVer） |
| `decodeFlickmap(json) → Flickmap` | flickmap JSON の厳格デコード（スキーマ相当の検証。不正は throw） |
| `mount(container, flickmap, opts) → FlickKeyboard` | キーボード UI を container に生成。`opts = { onOp, getComposingTail? }` |
| `createResolver(flickmap, host?) → FlickResolver` | UI 抜きの解決層（自前 UI・テスト用）。`resolve(gesture) → FlickOp[]` |
| `classifyGesture(dx, dy, cellWidth, threshold)` | ポインタ変位 → tap / flick 4 方向（純幾何） |
| `DEFAULT_POST_MODIFY_CYCLES` / `nextPostModify(tail, cycles)` | ゛゜小トグルの既定系列と適用関数 |

`FlickKeyboard`: `element`（ルート要素）/ `layer`（現在レイヤ名）/ `setLayer(name)` /
`destroy()`。

## 3. FlickOp の配線（ホストの責務）

`onOp(op)` に届く操作列を次のように配線する:

| op | 配線 | 説明 |
|---|---|---|
| `{type: "kana", text, replace}` | `fep.insertKana(text, replace)` | かな注入。`replace > 0` は ゛゜小トグルの末尾置換 |
| `{type: "key", tap}` | `fep.feed(tap)` → **false（未消費）ならホストのエディタ操作として実行** | 機能キー（BS/変換/確定/矢印）。物理キーボードの keydown 配線と同じ二重経路 |
| `{type: "text", text}` | エディタへ直接挿入 | direct レイヤ（英字・数字）。セッション非経由 |
| `{type: "layer", layer}` | （任意）レイヤ表示の更新 | `mount` 使用時は UI 再描画済み。通知のみ |

## 4. 最小統合例

```html
<script src="hechima.js"></script>
<script src="flick-engine.js"></script>
<script>
  const fep = Hechima.createFep(cb);          // cb はサイト既存の配線のまま
  fep.setActive(true);

  let composingText = "";                      // cb.show から控える（getComposingTail 用）
  // cb.show の中で: composingText = segments.map(s => s.text).join("");
  // cb.hide の中で: composingText = "";

  const map = FlickEngine.decodeFlickmap(await (await fetch("flickmaps/flick_standard.json")).json());
  const kbd = FlickEngine.mount(document.getElementById("flick-area"), map, {
    getComposingTail: () => composingText,
    onOp(op) {
      if (op.type === "kana") fep.insertKana(op.text, op.replace);
      else if (op.type === "key") { if (!fep.feed(op.tap)) editorApplyKey(op.tap); }
      else if (op.type === "text") editorInsert(op.text);
    },
  });
</script>
```

- `editorApplyKey` / `editorInsert` はホストのエディタ操作（物理キーボードで
  feed が false を返したときと同じ経路を再利用するのが正道）。
- `getComposingTail` は **cb.show で受けた合成表示テキスト**を返す。postModify の
  対象特定に使う（セッションの表示が正 = BS で編集されてもずれない）。

## 5. モバイル統合の注意

- **OS キーボードの抑止**: 編集領域（contenteditable 等）に `inputmode="none"` を
  指定する。hechima は OS IME 非依存なので、これでフリック UI だけが入力手段になる。
  iOS Safari の実機確認を必ず行うこと（宣言だけで済まない場合は `readonly` +
  caret 自前管理へのフォールバックを検討）
- **`touch-action: none`** はキーボードのルート要素に設定済み（スクロールとの競合防止）。
  ページ側でキーボード領域をスクロールコンテナに入れない
- UI テーマは CSS 変数で上書き可能: `--fe-bg` / `--fe-key-bg` / `--fe-key-fg` /
  `--fe-fn-bg` / `--fe-fn-fg` / `--fe-active-bg` / `--fe-petal-bg` / `--fe-petal-fg` /
  `--fe-petal-hot-bg`
- キーボードの高さはホストが container で決める（root は width/height 100% の grid）

## 6. ゴールデンテストの再利用

`web/src/flick/golden/*.json` + `web/scripts/run-flick-golden.mjs`（`npm run test:flick`）。
抽象ジェスチャ列（`{"tap": [row, col]}` / `{"flick": [row, col], "dir": "left"}`）を
resolver に流し、疑似ホスト（かなバッファ + ログ）への適用結果を検証する。
px → tap/flick の判定は vitest（`geometry.test.ts`）、デコーダの受理/拒否は
`decoder.test.ts` が担う。UI（pointer events / ペタル / リピート）は実機確認。
