# QuuBee への作業指示書 — hechima v0.3.0 追随（Phase 2 chord 修正 + Shift+←→ 伸縮）

> この文書は logical-layout-labo 側の Claude が書き、QuuBee 側の Claude セッションに渡すための
> 指示書です。docs/hechima_v020_phase2_chord_feedback.md（QuuBee → labo、Phase 2 で
> editSegment* が実打鍵到達不能という報告）への返信・修正版リリース通知です。
> 質問・調整は msonrm さん経由で。

## 要旨（30 秒版）

報告どおりでした。真因 = **Phase 2 の全 keydown が navCandidates に直行し engine.processKey に
届かない**。推奨いただいた **A 案で修正**（ナビキーだけセッション直処理、印字キー・SandS シフトは
engine へ流し chord 解決の結果で解釈。SandS の tap/hold 判定は engine の専権のまま）。
分水嶺だった「space 単打の次候補」は **keymap-engine 側の変更で解決**した（v1.2.0:
`onHostAction` が `convert` / `confirm` / `insertAndConfirm` も転送。Phase 2 のセッションが
「次候補」「結合確定」「現候補確定+句読点確定」に読み替える）。

**QuuBee 側の作業 = `hechima.js` と `keymap-engine.js` の 2 ファイル差し替えのみ**（見込みどおり
コード変更なし）。ただし**必ずセットで**（下記の互換性）。

## 差し替える成果物

| ファイル | 取得元 | 版 |
|---|---|---|
| `hechima.js` | Release **hechima-v0.3.0** | `Hechima.version` = "0.3.0" |
| `keymap-engine.js` | labo main の `web/public/engine/keymap-engine.js`（hechima-v0.3.0 タグ時点以降） | `KeymapEngine.version` = **"1.2.0"** |

- **互換性（重要）**: hechima 0.3.0 + keymap-engine 1.1.0 の組み合わせは不可。convert が
  転送されず、**Phase 2 の space 単打が全角スペース挿入に化ける**。同一コミットで両方差し替えること。
- hechima-wasm / mozc.data / naginata JSON: 変更なし（v0.2.0 のまま）。
- cb（show/hide/commit/hostKey/convert/resize）: 変更なし。v0.2.0 追随で配線済みの resize が
  そのまま実打鍵で発火するようになる。

## 修正後の Phase 2 挙動（変更点まとめ）

| 入力 | v0.2.0（バグ） | v0.3.0 |
|---|---|---|
| space+T / space+Y（同時打鍵） | 次候補化け → 即確定 → 余剰 ArrowLeft の三重奏 | **cb.resize(focus, ∓1) = 文節伸縮** |
| space 単打 | 次候補（セッションが素のキーで判定） | 次候補（engine の SandS 判定 → convert action 経由。見た目同じ・経路が正道化） |
| M+V（confirm chord） | engine に届かず無反応（実質） | **結合確定** |
| space+M / space+V（insertAndConfirm） | 化け | **現候補確定 + 。/、確定** |
| かなキー追加入力 | navCandidates の「その他キー」で確定+新規合成 | 同じ意味論（engine のかな出力経由で処理） |
| Enter / Escape / BS / ←→↑↓ | セッション直処理 | 同じ（変更なし） |
| **Shift+← / Shift+→**（新規） | （なし） | **文節伸縮**（標準 IME 互換。**全配列共通** — 内蔵ローマ字でも任意 keymap でも cb.resize があれば効く） |
| OS リピート / Ctrl 系コンボ | — | リピートは飲む / Ctrl 系は現候補を確定して透過 |

## 検証（labo 側で実施済み）

- **報告書付録の再現スクリプトが修正後期待値と一致**:
  `{ commits: [], resizes: [[0,-1]], hostKeys: [] }`（三重奏解消）。
- golden 37 ケース pass（新規 7 = **実打鍵 E2E**: space+T → resize / space 単打 → 次候補 /
  M+V → 結合確定 / かな追加入力 → 確定して継続 / Shift+←→ の engine・内蔵両経路 +
  resize 未提供時は飲む）。ご要望どおり fire 直叩きに加えて実 tap + 窓満了待ちの経路で
  三重奏の再発防止アサート（commits=[] / hostKeys=[] / resizeCalls）を入れてある。
- 既存 golden 30 / engine golden 48 / vitest 64 非回帰。

## QuuBee 側の確認項目

1. 2 ファイル差し替え後、`fep_mozc_test` / `fep_naginata_edit_test` / `fep_resize_test` が緑のまま。
2. ブラウザ実機（薙刀式・Phase 2）で: space+T/Y = 文節伸縮、space 単打 = 次候補、
   M+V = 結合確定、**Shift+←→ = 文節伸縮**（こちらは配列を問わず動くはず）。
3. 余計な確定・余剰カーソルキーがゲストへ飛ばないこと（三重奏の解消確認）。

## 補足

- 三重奏のうち「Phase 2 で space が次候補に化ける」だけは v0.3.0 でも**見た目は同じ**
  （次候補になる）が、経路が「セッションが素のキーで判定」から「engine の SandS 判定 →
  convert action」に変わった。長押し（連続シフト）との判別が engine 準拠になったのが差分。
- Shift+←→ はセッション層の機能なので、QuuBee で薙刀式以外の配列（ローマ字等）を載せる
  場合もそのまま文節伸縮が使える。
