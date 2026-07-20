# 記事第 1 弾 素材メモ + 事実裏取り表(Note アナウンス / Zenn 技術本編)

**状態: 執筆支援資料(2026-07-20 作成)**。数値・日付・URL はすべてこの日にリポジトリ実物
(ファイルサイズ・golden 実行・VENDOR.md・依頼書)で裏取り済み。執筆時はここだけ見れば
事実確認が済むようにしてある。骨子は会話で確定済み(Note 6 節 / Zenn 8 章)。

---

## A. 事実裏取り表(確認日 2026-07-20)

### バージョンと成果物

| 項目 | 値 | 出典 |
|---|---|---|
| hechima(変換セッション層) | **v0.13.0**(insertKana = かな直接注入) | labo Release `hechima-v0.13.0` / VENDOR.md |
| keymap-engine(配列エンジン) | **v1.4.0**(相互シフト mutual + 英数モード chord) | labo main `84199d5` / VENDOR.md |
| flick-engine(フリック UI) | **v1.1.1** | labo `98cd721` / VENDOR.md |
| hechima-wasm(Mozc 本体) | **v0.7.1**(ユーザー辞書 + よみ Mozc 純正検証) | Release `hechima-wasm-v0.7.1` |
| wasm provenance | fcitx5-mozc `fd530f6` / emsdk **3.1.69** | BUILD_INFO.txt / VENDOR.md |
| hechima-wasm.js | **97.9 KB** | vendor 実測(ls) |
| hechima-wasm.wasm | **2.72 MB**(2,723,747 B) | 同上 |
| mozc.data(辞書) | **18.9 MB**(18,890,236 B)= 初回 DL の主 | 同上 |
| 互換性 | hechima 0.13.0 は KeymapEngine >= 1.4.0 必須 / flick は hechima 0.13.0+ 必須 | VENDOR.md |

### テスト数(2026-07-20 実行確認)

| 種別 | 数 | 備考 |
|---|---|---|
| hechima セッション golden | **82 ケース**(12 ファイル) | `npm run test:hechima`。実 Mozc E2E 込み(CI) |
| 配列エンジン共有 golden | **54 ケース**(5 配列)全 pass | `npm run test:engine`(node)。Swift/kide ランナーとも共有 = 3 プラットフォームパリティ |
| flick golden | **20 ケース** | flick-engine 同梱 |
| vitest(web ユニット) | **99 件**全 pass | `npx vitest run` |

### ビルド・実測値

| 項目 | 値 | 出典 |
|---|---|---|
| wasm フルビルド(CI) | 約 21〜24 分(protoc 5 分 + ninja 15 分が支配) | CI run 実測(2026-07-13/14) |
| ビルドキャッシュ命中時 | **約 2 分** | R0 キャッシュ導入後の実測 |
| hechima_init | 75 ms(CI ubuntu runner。**ブラウザ実測値は撮影時に取る → §E**) | CI ログ |
| COOP/COEP | pthreads → SharedArrayBuffer 必須 → サイト全体 `_headers` で付与 | hechima-wasm/README.md:96 |
| NDEBUG の罠 | mozc `candidate.h` が `#ifndef NDEBUG` で `std::string log` メンバを増やし **sizeof が変わる** → ライブラリ(Release)とラッパーで食い違うと ABI 破壊。ラッパーも必ず -DNDEBUG | hechima-wasm/README.md:83-91 |
| OPFS 永続化 | `hechima/user/<scope>/` に segment.db / boundary.db / user_dictionary.db。学習リセットは学習 2 ファイルのみ削除(辞書と分離) | worker 実装 / メモ |

### 発端・命名(一次情報 = docs/hechima_handoff.md、2026-07-13)

| 項目 | 内容 |
|---|---|
| QuuBee | https://github.com/msonrm/quubee 。PC-98 の **HLE FEP**(FEP を高位エミュレーションし、実 DOS FEP の代わりに現代の変換エンジンへ接続)に Mozc wasm が必要だった = すべての発端 |
| 移管の流れ | QuuBee ローカルの属人ビルド(`~/development/mozc-wasm-build/` 620MB)→ 2026-07-13 labo へ移管・CI 化・Release 配布(第 1 弾)→ 07-14 変換セッション層 fep.js 407 行を TS 移植(第 2 弾) |
| hechima 由来①(語源遊び) | へちまの語源 = 糸瓜(とうり)→「と」が**いろは順で「へ」と「ち」の間**だから「へち間」。かな順の言葉遊びが名前そのもの = 配列ラボの主題と一致 |
| hechima 由来②(IM 隠し) | **h-e-c-h-[im]-a に IM(input method)が隠れている**。だから野暮な `-ime` は付けない |
| hechima 由来③(推し) | 眉村ちあき「ヘチマで体洗ってる」 https://youtu.be/FIG4pFtsIEs (hechima repo README 由来欄に記載済み) |
| luffa lang labo | luffa = へちまの英名(変換遊びのもう一回転)、L.L.L. = logical-layout-labo と同イニシャルの系譜。通称 = へちまラボ。ドメイン luffa-lang-labo.dev(2026-07-18 取得、$12.20/年) |
| ポジション | fcitx5-js(フル IME を載せる)とも azooKey(Swift、wasm 版なし)とも被らない空き位置(依頼書の分析) |
| 帰属 | **powered by Mozc**。BSD-3(Google)+ 辞書 = BSD-3 + NAIST License + Public Domain(CC BY-SA の Mozc UT は不同梱)。全文 THIRD_PARTY_NOTICES.md |

### 主要な日付(2026 年)

| 日付 | 事象 |
|---|---|
| 07-11 | 大岡俊彦さん「薙刀式のデメリット」(「同時押し」という語のツケ・用語発明の要請) |
| 07-13 | hechima-wasm 移管完了・Release v0.1.0(依頼書の完了定義 3 点達成) |
| 07-14 | セッション層移管(hechima v0.1.0)→ v0.2.0 文節伸縮 → v0.3.0 chord 修正 |
| 07-18 | 薙刀式を相互シフト(judgment=mutual)へ切替。luffa-lang-labo.dev 取得・repo public 化 |
| 07-19 | v0.12.0(機能キー)/ v0.13.0(insertKana)/ フリック UI 完成(実機 4 回) |
| 07-20 | サイト実験ページ制(/ ・ /naginata/ ・ /flick/) |

### 三つの不自由(Zenn 章 7 / Note 節 3 の裏付け)

1. **iPadOS + 物理キーボード**: サードパーティ IME が物理キーボードで一切効かない。
   本リポジトリ(KanaEditor の pressesBegan 横取り)自体がこの不自由から生まれた = 一人称で書ける
2. **配列の常駐ソフト**: DvorakJ(綴り注意: 大文字 J)・Karabiner-Elements 等は OS ごとに別物。
   iPadOS にはその穴すら無い →「薙刀式を iPad の物理キーボードで」は OS 側では原理的に不可能
3. **chrome.input.ime の借地**: 2020 年 Win/Linux 廃止 → ChromeOS も「代替手段はまだ無い」と
   明言したまま廃止宣告(ChromeOS 119 以降に削除)。理由は Lacros(OS 側都合)+ 3 年間利用が
   極少(不自由→使われない→消される、の悪循環)。
   出典: https://chromeos.dev/en/posts/chrome-input-ime-deprecation /
   https://groups.google.com/a/chromium.org/g/chromium-extensions/c/0ybWrEVaE-I/m/8QOeRmxrBQAJ
   ※「使えない」と断言せず「選択肢が極端に絞られ、その存在自体が不確実」の言い方で

---

## B. Zenn 章別素材メモ

**タイトル**: PC-98 のために Mozc を WebAssembly 化したら、ブラウザに日本語入力環境が生えた
**topics**: `日本語入力` `WebAssembly` `mozc` `IME` / 分量 8,000〜12,000 字
**検索ハンドル**: 冒頭付近で「へちまラボ / luffa lang labo / 日本語入力」を必ず併記

| 章 | ねらい | 使う事実(§A 参照) | 注意 |
|---|---|---|---|
| 1 デモ先出し | 30 秒で「動くもの」を見せる | GIF 3 本 + 3 実験 URL | GIF は §E |
| 2 発端 | 間違えた順番の物語 | QuuBee HLE FEP → wasm → 汎用スタック(発端・命名表) | QuuBee の一人称ディテールは msonrm さん加筆(§E) |
| 3 wasm の罠 | 技術記事としての本体 | NDEBUG(sizeof の具体)/ 2.72MB+18.9MB / COOP-COEP / CI 21 分→2 分 | 数値は表の値のまま使う |
| 4 層と命名 | 設計思想の見取り図 | keymap-engine / hechima / hechima-wasm、電文(定義文 §D)、cb 契約 必須 3+省略可 7、命名 3 由来 | UI 非同梱(cb 契約)は「弱点でなく証拠」の反転で |
| 5 見えない仕事 | 「普通」の再現コスト | golden 82+54+20、確定アンドゥ/文節伸縮/Shift+英字/再変換/学習巻き戻し | golden の初出定義 §D |
| 6 機能ツアー | 薙刀式とフリック | 相互シフト = 状態ベース(時間窓でないと v18 定義で確定した話 + 大岡さん 07-11 記事)、inputmode="none"、候補バー、OPFS | 大岡さんへの敬意を明示 |
| 7 思想ひと口 | IME→FEP の円環 | 三つの不自由(上表)。締め「OS のものだった日本語入力を、手元に返してもらう」 | ひと口で止めて続編予告 |
| 8 将来 + 案内 | 次への導線 | 寄生先ひと口(VS Code / Obsidian / ブラウザ拡張)、縦書き予告、repo / 組み込みガイド、powered by Mozc | 過約束しない(「実験場なので要望駆動」) |

## C. Note 節別素材メモ(2,000〜3,000 字)

タイトル最有力: 「インストールなしで薙刀式が打てるサイトを作りました」

| 節 | 中身 | 素材 |
|---|---|---|
| 1 | 冒頭 GIF +「リンクを開くだけで、薙刀式が打てます」 | iPad 薙刀式 GIF |
| 2 | できること 3 つ + 各実験ページへ直リンク | / ・ /naginata/ ・ /flick/ |
| 3 | なぜ(ひと口): iPad で配列どころか IME が使えない実体験を軸に | 三つの不自由の要約。深掘りは Zenn へ |
| 4 | 注意書き: OS IME オフ / 打鍵は外部送信なし / 初回のみ辞書 19MB | §A 数値 |
| 5 | **これから**: いま新配列は薙刀式だけ。NICOLA・月配列・AZIK などの定義は用意済み(ページを足すだけ)。配列は JSON で書ける形式 →「新配列はとりあえずへちまラボで試せる」場所へ。**載せてほしい配列があれば教えてください** | keymap-engine v1.4.0 は逐次/時間窓/相互シフト全対応(裏付け済み) |
| 6 | 案内: サイト / GitHub / Zenn 記事 / 要望歓迎 | 公開順: Zenn 先 → Note が URL を貼る |

## D. 用語初出の定義文例(内輪語対策)

- **電文**(Zenn 章 4): 「エンジンとのやりとりは『かな列を渡すと文節と候補が返ってくる』変換
  プロトコルとして固定してあります。呼び名は『電文』——銀行の勘定系みたいですが、レトロ起源の
  プロジェクトなので気に入っています」(説明役 = 変換プロトコル、名前役 = 電文。以降は電文のみ)
- **cb 契約**(章 4): 初出は「ホスト側が実装する数個のコールバック(未確定表示・確定・キー委譲…)
  の取り決め」→ 以降「cb 契約」
- **golden**(章 5): 「打鍵列と期待出力のペアを固定した回帰テスト(いわゆるゴールデンテスト)」
- **FEP**(章 2 or 7): DOS/PC-98 時代の「ユーザーランドに住む日本語入力」の呼び名。OS に取り込まれて
  IME になった → hechima はそれを wasm で巻き戻す(退行ではなく再発明)
- **相互シフト**(章 6): 「キーを押している間だけ、他のキーの意味が変わる」状態ベースの同時打鍵。
  ミリ秒の時間窓では判定しない

## E. 要実測・要撮影(msonrm さん側 + 撮影台本は別途 (b))

- [ ] GIF ①: PC ローマ字 + 候補ポップアップ + 学習(トップ `/`)15〜30 秒
- [ ] GIF ②: iPad + 物理キーボードで薙刀式(`/naginata/`)— 記事の最強の画
- [ ] GIF ③: iPhone フリック + 候補バー(`/flick/`)
- [ ] ブラウザ実測: 初回 DL 体感時間(回線明記)+ 2 回目以降の起動 + 変換初速(章 3 用。
      CI の init 75ms はランナー値なのでブラウザ値を別途)
- [ ] QuuBee 発端の一人称ディテール(当時何をしていて、なぜ FEP が要ったか)— 私が知り得ない部分
- [ ] novel-writer / 寄生先には触れる場合、章 8 のひと口に留める(構想段階のため)

## F. リンク集

- サイト: https://luffa-lang-labo.dev / /naginata/ / /flick/
- リポジトリ: https://github.com/msonrm/hechima (組み込みガイド・THIRD_PARTY_NOTICES 同梱)
- QuuBee: https://github.com/msonrm/quubee
- Mozc: https://github.com/google/mozc / fcitx5-mozc: https://github.com/fcitx/fcitx5-mozc
- 薙刀式(大岡俊彦さん): https://oookaworks.seesaa.net/ / 07-11 記事:
  https://oookaworks.seesaa.net/article/521112645.html / v18 定義:
  http://oookaworks.up.seesaa.net/image/E89699E58880E5BC8Fv18.txt (Shift_JIS)
- chrome.input.ime 廃止: §A 三つの不自由の出典 2 本
- 眉村ちあき「ヘチマで体洗ってる」: https://youtu.be/FIG4pFtsIEs
