# 記事第 1 弾 素材メモ + 事実裏取り表(Note アナウンス / Zenn 技術本編)

**状態: 役目を終えた執筆支援資料(2026-07-20 作成 / 2026-07-23 追補・第一弾公開)**。
**第一弾は 2026-07-23 に公開済み**(Zenn 技術本編 + Note アナウンス。公開稿は msonrm さんが
執筆したもので、本ファイルの叩き台ドラフトとは別物)。以後この資料は ①第二弾(縦書き)の
素材 ②事実値の再利用元(§A) として参照する。**公開した記事 URL は §F に追記すること(未了)**。

数値・日付・URL はすべてリポジトリ実物(ファイルサイズ・golden 実行・VENDOR.md・依頼書)で
裏取り済み。骨子は会話で確定済み(Note 6 節 / Zenn 8 章)。

**2026-07-23 の再検証で確認した差分**(数値・版・テスト数は全て再実行して 07-20 と一致):

- **サイトがポータル化**(07-22 hechima `5f897cd`)。`/` = 紹介 + 実験一覧 + フッター
  (エンジン読込ゼロ)、ローマ字の試打は **`/romaji/`** へ移設。一覧順 = 標準IME →
  フリック入力 → 薙刀式 → 縦書きIME。→ 記事の舞台設定・GIF 台本①・Note のリンクを修正済み
- **`/tategaki/`(縦書き)は動作完成・TOP 掲載済み**だが、**第一弾では触れない方針**
  (msonrm さん判断 07-23。第二弾 = Note 物書き向けの主役で扱う。noindex 維持中)。
  Zenn 章 8 の「これから」から縦書きを削除し、代わりに COI 非依存化を置いた
- **`/gamepad/`(ゲームパッド日本語入力)も第一弾では扱わない**。隠しページ + noindex
  運用のため縦書きと同じ扱い。GamepadEngine v1.6.0 / golden 27 ケースが別途あるが、
  記事中の golden 集計(82 + 54 + 20)には含めない
- **COI × Safari キャッシュ事象**(07-21 発見・多層防御済み)を Zenn 罠 2 に追記。
  恒久策 = 単スレッド wasm 化が「これから」の項目に昇格(下表参照)
- **flick の "auto" モード撤去**(07-23 hechima `81d747f`)。タッチ端末でトップに
  フリックボタンが出る挙動は廃止 → トグルが出るのは `/flick/` のみ(開いたら即表示)
- **組み込みガイドは「最小 1 本を同梱」で決着**(07-23)。hechima repo に
  `EMBEDDING.md`(公開向けクイックスタート + cb 必須 3 + COOP/COEP 制約 + 版の
  組み合わせ)を新設し、詳細は同梱の `hechima.d.ts` に委譲。labo の詳細ガイド 5 本
  (909 行)は private 前提の記述(build 手順・`../web/src/` リンク・QuuBee 依頼書参照)
  のため非公開のまま。→ Zenn リンク欄の「組み込みガイド同梱」は事実になった

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

### テスト数(2026-07-20 実行確認 / 2026-07-23 再実行して一致)

| 種別 | 数 | 備考 |
|---|---|---|
| hechima セッション golden | **82 ケース**(12 ファイル) | `npm run test:hechima`。実 Mozc E2E 込み(CI) |
| 配列エンジン共有 golden | **54 ケース**(5 配列)全 pass | `npm run test:engine`(node)。Swift/kide ランナーとも共有 = 3 プラットフォームパリティ |
| flick golden | **20 ケース** | flick-engine 同梱 |
| vitest(web ユニット) | **99 件**全 pass | `npx vitest run` |
| (gamepad golden **27 ケース**) | 記事では**使わない** | `npm run test:gamepad`。ゲームパッドは第一弾の対象外 |

### ビルド・実測値

| 項目 | 値 | 出典 |
|---|---|---|
| wasm フルビルド(CI) | 約 21〜24 分(protoc 5 分 + ninja 15 分が支配) | CI run 実測(2026-07-13/14) |
| ビルドキャッシュ命中時 | **約 2 分** | R0 キャッシュ導入後の実測 |
| hechima_init | 75 ms(CI ubuntu runner。**ブラウザ実測値は撮影時に取る → §E**) | CI ログ |
| COOP/COEP | pthreads → SharedArrayBuffer 必須 → サイト全体 `_headers` で付与 | hechima-wasm/README.md:96 |
| COI × Safari キャッシュ事象 | iPad Safari で URL 欄からの再 navigation 後、COI は維持のまま**キャッシュ済み応答の再利用だけが誤ブロック**され CSS/worker が全滅・新規タブにも波及・キャッシュ削除まで復旧不能。多層防御 = ①小型アセット全部 `no-store` ②worker は `?t=` でキャッシュバスト ③インライン復旧スクリプトで 1 回だけ自動リロード ④診断常設。恒久策 = **COI 非依存化(単スレッド wasm)**で、寄生先向け投資から iPad Safari の実害対応に昇格 | docs/hechima-tategaki-notes.md §6(2026-07-21)/ hechima `d12e260` |
| NDEBUG の罠 | mozc `candidate.h` が `#ifndef NDEBUG` で `std::string log` メンバを増やし **sizeof が変わる** → ライブラリ(Release)とラッパーで食い違うと ABI 破壊。ラッパーも必ず -DNDEBUG | hechima-wasm/README.md:83-91 |
| OPFS 永続化 | `hechima/user/<scope>/` に segment.db / boundary.db / user_dictionary.db。学習リセットは学習 2 ファイルのみ削除(辞書と分離) | worker 実装 / メモ |
| 初回 DL(体感) | **約 5 秒**(通信環境依存)。記事では「YouTube がそこそこ見られる回線なら同じくらい」の目安表現を推奨 | msonrm 実測 2026-07-20 |
| 変換初速(体感) | DL 済みならタイムラグほぼ無し。「ひょっとしたら iPad 標準 IME より快適かも」(体感。記事では体感と明記して使う) | 同上 |

### 発端・命名(一次情報 = docs/hechima_handoff.md、2026-07-13)

| 項目 | 内容 |
|---|---|
| QuuBee | https://github.com/msonrm/quubee 。PC-98 の **HLE FEP**(FEP を高位エミュレーションし、実 DOS FEP の代わりに現代の変換エンジンへ接続)に Mozc wasm が必要だった = すべての発端 |
| 擬似 FEP の動機(本人談 2026-07-20) | ① PC-98 用のフリーの FEP は現存しない ② **VZ Editor を起動しても日本語が打てないとつまらない** ③ 以前から IME を自作したかった。→ 章 2 の核。「VZ Editor」はレトロ読者に刺さる固有名詞なので必ず出す |
| 移管の流れ | QuuBee ローカルの属人ビルド(`~/development/mozc-wasm-build/` 620MB)→ 2026-07-13 labo へ移管・CI 化・Release 配布(第 1 弾)→ 07-14 変換セッション層 fep.js 407 行を TS 移植(第 2 弾) |
| hechima 由来①(語源遊び) | へちまの語源 = 糸瓜(とうり)→「と」が**いろは順で「へ」と「ち」の間**だから「へち間」。かな順の言葉遊びが名前そのもの = 配列ラボの主題と一致 |
| hechima 由来②(IM 隠し) | **h-e-c-h-[im]-a に IM(input method)が隠れている**。だから野暮な `-ime` は付けない |
| hechima 由来③(推し) | 眉村ちあき「ヘチマで体洗ってる」 https://youtu.be/FIG4pFtsIEs (hechima repo README 由来欄に記載済み) |
| luffa lang labo | luffa = へちまの英名(変換遊びのもう一回転)、L.L.L. = logical-layout-labo と同イニシャルの系譜。通称 = へちま言語ラボ。ドメイン luffa-lang-labo.dev(2026-07-18 取得、$12.20/年) |
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
**検索ハンドル**: 冒頭付近で「へちま言語ラボ / luffa lang labo / 日本語入力」を必ず併記

| 章 | ねらい | 使う事実(§A 参照) | 注意 |
|---|---|---|---|
| 1 デモ先出し | 30 秒で「動くもの」を見せる | GIF 3 本 + 3 実験 URL(`/romaji/` ・ `/naginata/` ・ `/flick/`。トップは案内所) | GIF は §E |
| 2 発端 | 間違えた順番の物語 | QuuBee HLE FEP → wasm → 汎用スタック(発端・命名表) | QuuBee の一人称ディテールは msonrm さん加筆(§E) |
| 3 wasm の罠 | 技術記事としての本体 | NDEBUG(sizeof の具体)/ 2.72MB+18.9MB / COOP-COEP + **COI × Safari キャッシュ事象と多層防御** / CI 21 分→2 分 | 数値は表の値のまま使う |
| 4 層と命名 | 設計思想の見取り図 | keymap-engine / hechima / hechima-wasm、へちま蔓(定義文 §D)、cb 契約 必須 3+省略可 7、命名 3 由来 | UI 非同梱(cb 契約)は「弱点でなく証拠」の反転で |
| 5 見えない仕事 | 「普通」の再現コスト | golden 82+54+20、確定アンドゥ/文節伸縮/Shift+英字/再変換/学習巻き戻し | golden の初出定義 §D |
| 6 機能ツアー | 薙刀式とフリック | 相互シフト = 状態ベース(時間窓でないと v18 定義で確定した話 + 大岡さん 07-11 記事)、inputmode="none"、候補バー、OPFS | 大岡さんへの敬意を明示 |
| 7 思想ひと口 | IME→FEP の円環 | 三つの不自由(上表)。締め「OS のものだった日本語入力を、手元に返してもらう」 | ひと口で止めて続編予告 |
| 8 将来 + 案内 | 次への導線 | 新配列追加、寄生先ひと口(VS Code / Obsidian / ブラウザ拡張)、**COI 非依存化**、repo + `EMBEDDING.md`、powered by Mozc | 過約束しない(「実験場なので要望駆動」)。**縦書き・ゲームパッドには触れない** |

## C. Note 節別素材メモ(2,000〜3,000 字)

タイトル最有力: 「インストールなしで薙刀式が打てるサイトを作りました」

| 節 | 中身 | 素材 |
|---|---|---|
| 1 | 冒頭 GIF +「リンクを開くだけで、薙刀式が打てます」 | iPad 薙刀式 GIF |
| 2 | できること 3 つ + 各実験ページへ直リンク(トップは案内所) | /romaji/ ・ /naginata/ ・ /flick/ |
| 3 | なぜ(ひと口): iPad で配列どころか IME が使えない実体験を軸に | 三つの不自由の要約。深掘りは Zenn へ |
| 4 | 注意書き: OS IME オフ / 打鍵は外部送信なし / 初回のみ辞書 19MB | §A 数値 |
| 5 | **これから**: いま新配列は薙刀式だけ。NICOLA・月配列・AZIK などの定義は用意済み(ページを足すだけ)。配列は JSON で書ける形式 →「新配列はとりあえずへちま言語ラボで試せる」場所へ。**載せてほしい配列があれば教えてください** + 寄生先ひと口 | keymap-engine v1.4.0 は逐次/時間窓/相互シフト全対応(裏付け済み)。**縦書きは第二弾の主役なので第一弾では書かない** |
| 6 | 案内: サイト / GitHub / Zenn 記事 / 要望歓迎 | ~~公開順: Zenn 先 → Note が URL を貼る~~ → **実際は Note 先(07-20)・Zenn 後(07-23)。Note 側に Zenn の URL が未記載**(§F 参照。追記は msonrm さんの Note 編集作業) |

## D. 用語初出の定義文例(内輪語対策)

- **へちま蔓**(Zenn 章 4): 「エンジンとのやりとりは『かな列を渡すと文節と候補が返ってくる』変換
  プロトコルとして固定してあります。呼び名は『へちま蔓』——へちまは蔓（つる）植物で、蔓が棚を伝って伸びるように、
  層と層をつなぐ一本の経路、というくらいの意味です」(説明役 = 変換プロトコル、名前役 = へちま蔓。以降はへちま蔓のみ)
- **cb 契約**(章 4): 初出は「ホスト側が実装する数個のコールバック(未確定表示・確定・キー委譲…)
  の取り決め」→ 以降「cb 契約」
- **golden**(章 5): 「打鍵列と期待出力のペアを固定した回帰テスト(いわゆるゴールデンテスト)」
- **FEP**(章 2 or 7): DOS/PC-98 時代の「ユーザーランドに住む日本語入力」の呼び名。OS に取り込まれて
  IME になった → hechima はそれを wasm で巻き戻す(退行ではなく再発明)
- **相互シフト**(章 6): 「キーを押している間だけ、他のキーの意味が変わる」状態ベースの同時打鍵。
  ミリ秒の時間窓では判定しない

## E. 要実測・要撮影(msonrm さん側 + 撮影台本は別途 (b))

- [ ] GIF ①: PC ローマ字 + 候補ポップアップ + 学習(**`/romaji/`**。トップは案内所)15〜30 秒
- [ ] GIF ②: iPad + 物理キーボードで薙刀式(`/naginata/`)— 記事の最強の画
- [ ] GIF ③: iPhone フリック + 候補バー(`/flick/`)
- [x] ブラウザ実測 → §A に反映済み(初回 DL 体感 5 秒 / 変換タイムラグほぼ無し。2026-07-20)
- [x] QuuBee 発端の一人称 → §A に反映済み(フリー FEP 不在 / VZ Editor / IME 自作願望)
- [ ] novel-writer / 寄生先には触れる場合、章 8 のひと口に留める(構想段階のため)

## G. GIF 撮影台本(3 本)

**共通**: mp4 で撮って GIF 化(幅 800px・10〜15fps 目安、ffmpeg か Gifski)。各 15〜30 秒。
ライト/ダークはどちらかに統一。①②は冒頭にアドレスバー(URL)が一瞬映る構図だと
「開くだけ」が伝わる。撮り直しは「クリア」(+必要なら「学習リセット」)で初期状態に戻せる。

### GIF ① ふだんどおりのローマ字(**`/romaji/`**、20〜25 秒)

準備: OS IME オフ(英数直接入力)/ `/romaji/` を開く / 「クリア」→「学習リセット」
(手順 4 の学習デモを確実に効かせるため)
※ 07-22 のポータル化でトップは案内所になり、試打の実体は `/romaji/` に移設された。
アドレスバーを映すなら `/romaji/` の URL が出る構図でよい

1. ローマ字で「へちまはぶらうざでうごきます」と打つ → **Space で変換**
2. 「へちま」の文節で Space をさらに押して**候補ポップアップ**を見せる →
   初回の先頭候補と違うもの(「ヘチマ」等、何でもよい)を数字キーで選択
3. **Enter 確定** → 改行
4. 「へちま」だけ再入力 → Space → **さっき選んだ候補が先頭に来ている** = 学習の画

ポイント: 映像は「普通に見える」ことに徹する(下線・候補窓・学習が全部ページ製で
あることは記事本文が説明する)。

### GIF ② iPad + 物理キーボードで薙刀式(`/naginata/`、20〜30 秒)

準備: iPad のハードウェアキーボードを**英語(ABC)**にして OS 側 IME を挟まない /
`/naginata/` を開く / キーボード種別(JIS/US)を選ぶ

構図: **可能ならキーボードと画面が同時に入る実写(スマホ横持ち)を推奨** —
「物理キーボードで打っている」ことが一般読者にも伝わる。無理なら画面収録のみでも成立。

1. ページタイトルとパンくずが一瞬映る(「URL を開くだけ」の画)
2. 薙刀式で短文を**ゆっくり**打つ(例: 「なぎなたしきで かける」)。速度より
   「本当に動いている」感を優先。倍速編集はしない
3. Space 変換 → Enter 確定(余裕があれば **M+V 同時押し確定** = 配列民向けの一瞬芸)

加点(必須ではない): 押しっぱなしの連続シフト、space+T / space+Y の文節伸縮。

### GIF ③ iPhone でフリック(`/flick/`、15〜25 秒)

準備: iPhone Safari で `/flick/` を開くだけ(キーボードが勝手に出る = それ自体が画)

1. ページを開く → 下から**自前キーボードが出現**(OS キーボードは出ない)
2. フリックで「へちまらほ」と打つ → **゛゜小 をタップ** → 「へちまらぼ」(トグルの画)
3. 変換(空白キーの表示が「**変換**」に変わっている)→ **候補バー**からタップ選択 →
   改行キー(表示「**確定**」)で確定

加点: 候補バーを横に一往復スクロール(「ポップアップではなくバー」が伝わる)、
「←」の上下フリックで候補送り。

## F. リンク集

- **公開した記事(第一弾)**:
  - Zenn 技術本編(2026-07-23): https://zenn.dev/msonrm/articles/70a34fbc8cc8a9
    「PC-98のためにMozcをWebAssembly化してたら、ブラウザ内完結な日本語入力環境ができた」
    → サイト / GitHub(msonrm/hechima) へのリンクあり
  - Note アナウンス(2026-07-20 22:55): https://note.com/msonrm/n/n153cfddb5398
    「いろんなやりかたで日本語が打てる実験場サイト『へちま言語ラボ』を公開しました」
    → サイトへのリンクあり。**Zenn 記事へのリンクは未記載**(本文は「Zenn に書く予定」のまま)
  - ※ 実際の公開順は **Note 先(07-20) → Zenn 後(07-23)** で、§C 6 節の想定(Zenn 先 → Note が
    URL を貼る)とは逆になった。第二弾(縦書き)から相互リンクを張るときの起点は上記 2 本
- サイト: https://luffa-lang-labo.dev (案内所) / /romaji/ / /naginata/ / /flick/
  ※ /tategaki/ ・ /gamepad/ は第一弾では出さない
- リポジトリ: https://github.com/msonrm/hechima (`EMBEDDING.md` = 最小の組み込みガイド・
  `hechima.d.ts` = 型定義 + cb 契約・THIRD_PARTY_NOTICES 同梱)
- QuuBee: https://github.com/msonrm/quubee
- Mozc: https://github.com/google/mozc / fcitx5-mozc: https://github.com/fcitx/fcitx5-mozc
- 薙刀式(大岡俊彦さん): https://oookaworks.seesaa.net/ / 07-11 記事:
  https://oookaworks.seesaa.net/article/521112645.html / v18 定義:
  http://oookaworks.up.seesaa.net/image/E89699E58880E5BC8Fv18.txt (Shift_JIS)
- chrome.input.ime 廃止: §A 三つの不自由の出典 2 本
- 眉村ちあき「ヘチマで体洗ってる」: https://youtu.be/FIG4pFtsIEs
