# QuuBee への作業指示書 — hechima v0.12.0 追随（薙刀式 相互シフト化 + 機能キー実挙動修正）

> この文書は logical-layout-labo 側の Claude が書き、QuuBee 側の Claude セッションに渡すための
> 指示書です。docs/hechima_v030_quubee_handoff.md（v0.3.0 追随）の続報にあたります。
> 質問・調整は msonrm さん経由で。

## 要旨（30 秒版）

薙刀式の同時押し判定が**本家仕様と違っていた**ことが判明した。時間窓（`simultaneousWindow`
80ms）判定は解釈違いで、正しくは**「相互シフト」= ミリ秒を一切見ない状態ベース判定**
（作者の一次資料で確定。§1）。keymap-engine **v1.3.0** で判定モード `judgment: "mutual"` を
実装し、naginata JSON を切り替えた。

続けてラボサイト（luffa-lang-labo.dev）の実打フィードバックで機能キー 3 件を修正した
（keymap-engine **v1.4.0** / hechima **v0.12.0**。§2）: 英数モードから H+J で日本語に
戻れない / 合成中の V+M が確定にならない / mutual の再入 reset バグ。

**QuuBee 側の作業 = `hechima.js` + `keymap-engine.js` + naginata JSON の 3 点セット
差し替えのみ**（コード変更なし。cb も現行のままでよい）。ただし**必ず 3 点同時に**（下記の互換性）。

## 差し替える成果物

| ファイル | 取得元 | 版 |
|---|---|---|
| `hechima.js`（+ 任意で `hechima.d.ts`） | Release **hechima-v0.12.0** | `Hechima.version` = "0.12.0" |
| `keymap-engine.js` | labo main の `web/public/engine/keymap-engine.js`（`84199d5` 以降。Release には添付されない） | `KeymapEngine.version` = **"1.4.0"** |
| naginata JSON（jis/us、vendoring している分すべて） | labo main の `web/public/keymaps/naginata_{jis,us}.json` | v18 のまま。`chordConfig` に **`"judgment": "mutual"`** の行があるのが目印 |

- **互換性（重要）**: 3 点セットで差し替えること。特に**旧エンジン（≤1.2.0）は `judgment`
  フィールドを黙って無視して時間窓のまま動く**（クラッシュしないので JSON だけ差し替えても
  気づかない）。逆に新エンジン + 旧 JSON も時間窓のまま（`judgment` 省略の既定 = `window`）。
- v0.3.0 のときの制約（hechima は keymap-engine >= 1.2.0 必須）も引き続き有効。
  0.12.0 + 1.4.0 の組は labo golden（hechima 72 ケース含む）+ ラボサイト実機で確認済み。
- **hechima-wasm / mozc.data: v0.2.0 のままで可**（今回の変更はエンジン/セッション層のみ）。
- cb（show/hide/commit/hostKey/convert/resize の現行 6 点）: 変更不要。
- labo は private リポジトリのまま。取得は従来どおり msonrm さん経由で。

## 1. 薙刀式の相互シフト化（judgment=mutual）

本家の定義（一次資料）:

- 大岡俊彦氏ブログ 2026-07-11 記事（oookaworks.seesaa.net/article/521112645.html）:
  「ミリ秒を見ていない。Aを押しながらB、またはBを押しながらA」。正式名は**相互シフト**
- v18 定義ファイルの 1 行目は「**順に打鍵する配列**」— DvorakJ のタイミング窓式
  （「同時に打鍵する配列」）を使っていない。全同時押しはホールド面の双方向定義
- なお配列定義（JSON のかな面）は v18 定義ファイルと機械照合済みで一致（159 エントリ。
  唯一の系統差 = ヴ→ゔ は IME 読みバッファの正規化で意図的）。今回の修正はすべて実装側

挙動の変わり方:

| 観点 | 旧（window、〜v1.2.0） | 新（mutual、v1.3.0+） |
|---|---|---|
| chord 判定 | 80ms 窓内の重なり | **時間不使用**。押しっぱなし中にもう 1 キーで chord |
| 連続シフト | スペース（SandS）のみ | **任意の chord キーに一般化**（J 押しっぱなしで濁音連打可。編集モードの D+F ホールドと同機構） |
| 単打の出力 | 窓満了タイマー | **keyUp で出力**（タイマー無し） |
| 未定義の組合せ | — | fall-through で単打解決 + disarm（撫で打ちロールオーバー自由） |
| 定義済みペアのロールオーバー誤爆 | 窓が抑止していた | **仕様**（本家どおり撫で打ち前提。誤爆したら本家でも誤爆する打ち方） |

**テストへの影響（重要）**: mutual はタイマーを一切使わないため、**仮想クロックの時間送りで
発火するものが無くなる**。`engine.onStateChange`（chord 窓満了の遅延通知）も薙刀式では
発火しなくなる（配線は残してよい — window 判定の配列では引き続き必要）。回帰スクリプトが
「keydown → 80ms 進める → 出力を期待」という形なら **keyup を送る形に直す**こと。
keydown/keyup を正しく対で送っているテストは最終出力が変わらないはず。

## 2. 機能キーの実挙動修正（3 件）

| # | 症状 | 修正 | 層 |
|---|---|---|---|
| ① | 英数モード（F+G）から **H+J で日本語に戻れない**（web） | 英数モードにも chord 解釈を実装。`englishLookupTable` を持つ配列（薙刀式）は英数でも chord バッファでキーを解釈（**H+J = switchToJapanese、space+X = 大文字面**が効くように）。単打面は素の英字なので通常タイプは従来どおり。修飾キー付き（Shift+h 等）・テーブル外キー・`englishLookupTable` の無い配列（NICOLA 等）は従来どおり直接挿入。英数の chord 出力は composition を経由せず confirmedText へ直行 | engine v1.4.0 |
| ② | 合成中の **V+M が「変換開始」に化ける**（確定にならない） | 本家 v18 の VM = Enter・「、{Enter}」に合わせ、合成中（文節無し・よみ復帰でもない）の confirm / insertAndConfirm は**無変換で即確定**。Phase 2 の V+M（結合確定）・よみ復帰中の V+M（よみのまま確定）・SandS 単打 space（= convert で変換開始）は従来どおり | hechima v0.12.0 |
| ③ | F+G（switchToEnglish）後のロールオーバーで**次の 1 打鍵が消える** | mutual の部分リリース発火 → コールバックが `reset()` を再入的に呼び stale フラグが残るバグ。発火を状態更新の最後に移動 | engine v1.4.0 |

## 3. v0.3.0 → v0.12.0 のその他のセッション挙動差分

差し替えだけで入る、**ユーザーに見える挙動変更**（いずれも標準 IME 準拠への意図的変更）:

- **Phase 2 の BS / U（deleteBack）/ Escape = 「よみに戻す」**（旧: 全クリア。v0.8.1）。
  よみ復帰状態の編集も入る: BS = 末尾 1 字削除 / Enter・V+M = よみのまま確定 /
  space 単打 = 再変換 / かな追加 = 連結して合成継続
- **Phase 2 先頭での ↑ = 追加候補の段階展開**（ひらがな→カタカナ。旧: 末尾候補へ wrap。v0.6.0）
- **Shift+英字 = 英字合成サブモード**（内蔵ローマ字経路のみ。配列エンジン経路は不変 =
  薙刀式の打鍵には影響しない。v0.6.0 / v0.11.1）
- 候補の表示値 dedupe（v0.5.1）/ Phase 2 で Shift 単体押下が確定に化けるバグ修正
  （v0.8.2 — **Shift+←→ の文節伸縮がブラウザ実機で効くようになる**）
- `cb.show` の SegmentView に `candidates` / `candidateIndex` / `additional` /
  `additionalIndex` が追加（後方互換。無視すれば従来どおり。候補ポップアップ UI を
  作るなら利用可。v0.5.0 / v0.6.0）

opt-in（今回は不要。使う場合は wasm/worker 更新が絡むので別便で）:
学習（cb.learn、wasm v0.4.0+）/ 確定アンドゥ（cb.retract + unlearn、v0.5.0+）/
再変換（cb.reconvert、v0.6.0+）/ ユーザー辞書（worker 電文、v0.7.x）。
cb 契約は計 10 点（必須 3 + 省略可 7）に拡張済み — 詳細は `docs/hechima-session-embedding.md`
と `docs/hechima-protocol.md`。labo 正典の `hechima-worker.js` + `Hechima.connectWorker` に
乗り換えると配線が縮む（これも任意）。

## 4. 確認項目

1. 既存回帰（`fep_mozc_test` / `fep_naginata_edit_test` / `fep_resize_test`）が緑。
   時間送り依存のケースがあれば keyup 駆動に直す（§1 テストへの影響）。
2. ブラウザ実機（薙刀式）で:
   - J 押しっぱなしで濁音連打（連続シフトの一般化）
   - F+G → 英字タイプ → **H+J で日本語に復帰**（①）
   - 合成中 V+M = **無変換で即確定**（②）
   - F+G 直後のロールオーバーで 1 打目が消えないこと（③ の再発確認)
   - Phase 2 の BS = よみ戻し（§3 の新挙動）
3. 余計な確定・余剰キーがゲストへ飛ばないこと（v0.3.0 の三重奏チェックと同じ観点）。

## 完了の定義

- hechima.js（0.12.0）+ keymap-engine.js（1.4.0）+ naginata JSON（mutual）の 3 点を
  同一コミットで vendoring（版情報を QuuBee README に控える）。
- 回帰緑 + 実機で §4-2 の 5 点が確認できること。
