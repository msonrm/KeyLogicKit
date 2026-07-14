# QuuBee への作業指示書 — hechima v0.2.0 追随（文節伸縮）+ 薙刀式 v18

> この文書は logical-layout-labo 側の Claude が書き、QuuBee (https://github.com/msonrm/quubee)
> 側の Claude セッションに渡すための指示書です。docs/hechima_session_handoff.md（QuuBee → labo、
> 第 2 の移管）の返信第 2 便にあたります。質問・調整は msonrm さん経由で。

## 背景（30 秒版）

労側（labo）で **文節伸縮**を実装した。据え置きだった editSegmentLeft/Right（薙刀式
**space+T / space+Y**）が、Mozc の `ResizeSegment` まで通貫でつながる:

```
薙刀式 space+T/Y → engine specialAction → InputEngine.onHostAction
  → hechima セッション（Phase 2 なら cb.resize(focus, ∓1)）
  → hechima-wasm の hechima_resize → Mozc ResizeSegment → 再変換 JSON → 表示差し替え
```

QuuBee 側は **成果物 2 ファイルの差し替え + mozc-worker に RPC 1 本 + bridge の cb に
resize 1 点**で恩恵が入る。cb.resize を実装しなくても後方互換で壊れない
（editSegment* は無害に飲まれる = 現行と同じ見た目）。

あわせて薙刀式が **v18**（作者発表。**め⇔ね の入れ替えのみ**）になったので、
vendoring している keymap JSON の更新も依頼する。

## 1. 差し替える成果物（pin する版）

| ファイル | 取得元 | 版情報 |
|---|---|---|
| `hechima-wasm.js` / `hechima-wasm.wasm` | Release **hechima-wasm-v0.2.0** | fcitx5-mozc `8b3d34c`（v0.1.0 と同一）/ emsdk 3.1.69 / labo `29b6271` |
| `mozc.data` | **差し替え不要**（v0.1.0 と同じ fcitx5-mozc コミットのため内容同一。揃えたければ v0.2.0 添付のものをどうぞ） | 同上 |
| `hechima.js`（+ 任意で `hechima.d.ts`） | Release **hechima-v0.2.0** | `Hechima.version` = "0.2.0"、labo `40aad06` |
| `keymap-engine.js` | **差し替え不要**（v1.1.0 のまま。前回追随で導入済みのはず） | `KeymapEngine.version` = "1.1.0" |
| `web/assets/keymaps/naginata_jis.json`（+ 他に vendoring している naginata があれば全部） | labo main の `web/public/keymaps/naginata_{jis,us}.json`（コミット `cf57718` 以降） | **薙刀式 v18**。§4 参照 |

- hechima-wasm v0.2.0 の C API は**追加のみ**（`hechima_init` / `hechima_convert` は入出力とも互換）。
- 新 API: `hechima_resize(segIdx, offset, maxCands) → JSON 文字列`。
  直近の `hechima_convert` 結果の segIdx 文節（0 起点）のよみを offset（**よみ文字数**、±）だけ
  伸縮し、再変換後の全文節を `hechima_convert` と同形の JSON で返す。
  **伸縮不能（境界）・変換状態なし・範囲外は空文字列** = 呼び元は現状維持にする。
  直近の変換状態はラッパーが static に 1 つだけ保持する（convert を呼ぶたびに更新）。

## 2. mozc-worker.js — RPC を 1 本足す

`hechima_convert` の RPC と同じ形でよい。ccall はこれだけ:

```js
// 既存: convert
const json = M.ccall('hechima_convert', 'string', ['string', 'number'], [yomi, 9]);
// 追加: resize（segIdx = 0 起点の文節番号、offset = よみ文字数 ±）
const json = M.ccall('hechima_resize', 'string', ['number', 'number', 'number'], [segIdx, offset, 9]);
```

- 戻りのパースは convert と共通でよい: `"" or パース失敗 → null`、成功 → `parsed.segments`。
- **機能検出を推奨**: `typeof M._hechima_resize === 'function'` が false（= 古い v0.1.0 の wasm が
  残っている）なら resize RPC を無効化して null を返す。wasm と js の差し替えが同一コミットなら
  実質不要だが、labo の golden ランナーもこの方式で守っている。

## 3. bridge.js — cb に resize を 1 点追加

`Hechima.createFep(cb)` に渡している cb（show / hide / commit / hostKey / convert）に追加:

```js
// convert と同じく Promise でよい。null 解決 = 伸縮不能（fep は現状維持する）
resize(segIdx, offset) { return mozcWorkerRpc('resize', { segIdx, offset }); },
```

セッション側（hechima v0.2.0）の意味論は実装済み・golden 化済み:

| 状態 | editSegmentLeft（space+T）/ editSegmentRight（space+Y） |
|---|---|
| Phase 2（候補選択中） | `cb.resize(focus, ∓1)` → 返った文節列で差し替え。フォーカス維持（結合で文節が減ったら clamp）。in-flight 中の打鍵で結果は世代トークン破棄 |
| 変換前よみ合成中 | 飲む（確定に倒さない） |
| 空バッファ | 飲む（hostKey も出さない — 伸縮に相当する実キーが無いため） |
| `cb.resize` 未実装 | すべて飲む（現行と同じ見た目。段階導入可） |

**wrap は増やさないこと**: v0.1.0 追随で撤去した `chordBuffer.onSpecialAction` の横取りを
復活させる必要は一切ない。editSegment* も `InputEngine.onHostAction` → hechima 経由で届く。

## 4. 薙刀式 v18（キーマップ JSON の差し替え）

作者（大岡俊彦氏）発表の v18。変更は **シフト面の め⇔ね 入れ替えのみ**:

| キー | v17 まで | v18 |
|---|---|---|
| `space+W` | め | **ね** |
| `space+R` | ね | **め** |

- labo main（`cf57718` 以降）の `web/public/keymaps/naginata_{jis,us}.json` をそのままコピー
  （description が「薙刀式v18同時打鍵入力（…）」になっているのが v18 の目印）。
- 影響: `fep_naginata_edit_test` は T/Y/U（編集キー）しか打たないので**期待値変更なし**。
  め/ね を打つ回帰・デモスクリプトがあれば期待値の追随が要る。
- 参考: labo のゴールデンは連続シフトケースの期待値を「りねめ」→「りめね」に更新して
  3 プラットフォームで緑を確認済み。

## 5. 回帰確認（labo 側の実証と同等のもの）

1. 既存回帰 `fep_mozc_test` / `fep_naginata_edit_test` が**無変更で緑のまま**であること
   （resize は追加のみ・editSegment* の既定は「飲む」なので既存ケースに影響しない）。
2. resize の新規回帰（任意だが推奨。labo の golden と同じ判定方式）:
   - **stub**: Phase 2 で editSegmentRight を発火 → cb.resize が `(focus, +1)` で呼ばれ、
     返した文節列に表示が差し替わる。
   - **実 Mozc ラウンドトリップ**: `hechima_convert('きょうはいいてんきですね')` →
     `hechima_resize(0, -1)` で第 1 文節が「きょうは」→「きょう」→ `hechima_resize(0, +1)` で
     **第 1 候補列が元に完全復元**（labo の hechima_wasm_test.js で実証済みの決定的アサート）。
   - 構造だけ見る版: 「あい」変換 → `-1` → `+1` で**初期分節に依らず最終 1 文節に収束**
     （labo golden `mozc_e2e.json` の方式）。
3. 実機で薙刀式: Phase 2 中に space+T / space+Y で文節境界が動き、space+W/R が ね/め に
   なっていること。

## 6. 触らなくてよいもの

- COOP/COEP・SharedArrayBuffer 前提: 変更なし。
- `mozc.data` の fetch パス・辞書名: 変更なし。
- `HechimaModule` / `hechima_init` / `hechima_convert` の呼び出し: 変更なし。
- KeymapEngine: v1.1.0 のままでよい（今回のエンジン側変更はなし）。

## 完了の定義

- hechima-wasm v0.2.0 + hechima v0.2.0 を vendoring（版情報を QuuBee README に控える）。
- mozc-worker に resize RPC、bridge の cb に `resize` が入り、薙刀式 space+T/Y が
  Phase 2 で文節伸縮として動く。
- naginata JSON が v18 に差し替わっている。
- `fep_mozc_test` / `fep_naginata_edit_test` 緑（+ 任意で resize 回帰の追加）。
