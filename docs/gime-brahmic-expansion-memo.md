# GIME Brahmic + Abjad 拡張 設計メモ

**状態**: Devanagari Android PoC 着手中（2026-04-23）
**発端**: セッション 2026-04-22 の余談から発展した設計討議を記録として残す
**更新履歴**:
- 2026-04-23: 子音 varga / stop / 母音の全レイヤーを
  **varnamala 時計回り**方式に改訂（朗唱順と指の運動を同期させる設計原則）

## 概要

GIME は既に CJK + 英語 + 韓国語をカバーしているが、既存アーキテクチャ
（mode + resolver + composer パターン）は**アジア系の構造化スクリプト全般**
に適用可能性があり、射程を Devanagari → 他の Brahmic 系 → Abjad 系へ
拡張すれば **世界人口の 40% 強** を覆うことができる。

### 市場規模

| 文字系統 | 話者数（概算） |
|---|---|
| CJK（漢字・仮名・ハングル） | ~16 億 |
| Devanagari（Hindi / Marathi / Nepali 等） | ~7.5 億 |
| 他の Brahmic（Bengali / Tamil / Telugu / Gujarati / Kannada / Malayalam / Punjabi / Thai / Burmese / Tibetan 等） | ~8 億 |
| Abjad（Arabic / Persian / Urdu / Hebrew 等） | ~4 億 |
| **合計** | **~35 億** |

### なぜゲームパッドが構造化スクリプトに効くか

Latin 系と違い、アジア系スクリプトは全て **「子音群 × 母音群」の 2 次元積**
で記述できる:

- **音節文字**（仮名・ハングル）: 子音 × 母音マトリクス
- **アブギダ**（Devanagari, Thai, Tamil, Burmese, Tibetan 等）: 子音 + 母音
  ダイアクリティカル
- **アブジャド**（Arabic, Hebrew）: 子音 + 母音記号

これは**ゲームパッドの「レイヤー × グリッド」入力モデルと同型**で、
加えて発音位置による**音声学的な自然分類**（軟口蓋・歯・唇・etc.）が
レイヤー選択の mnemonic になる。VR での blind typing では「どこに何が
あるか」を phonological 直感で導出できる利点が致命的に効く。

### Leapfrog 論

アジア圏は既に物理キーボード時代に**Latin QWERTY + IME patch 文化**で
しのいできた（romaji→仮名、pinyin/zhuyin→漢字、ITRANS→Devanagari）。
**誰もネイティブキーボードを持っていない**。VR 入力はこれを reset する
機会で、先行者利得のない市場の方が構造最適解（gamepad-native）に
早く移行する可能性が高い。歴史的 leapfrog（固定電話 → モバイル、
クレジットカード → UPI/Alipay）と同型パターン。

---

## Devanagari 入力モデル

### 合成アルゴリズム（Korean 받침 式の類推）

Devanagari の音韻論的前提:

- 子音は固有の **schwa (a)** を背負っている（क 単独で "ka"）
- 次の子音が来ると **virama (्)** で schwa を殺し conjunct 化
  （क + ् + ष = क्ष "kṣa"）
- 母音 matra が来ると schwa を置換して akshara 確定（क + ि = कि "ki"）

これを入力モデルに落とすと、**Korean 받침 の「即時適用 + 巻き戻し」と同型**:

```
[user types]    [buffer]          [display]
  क             [क]               क        (schwa 付きで "ka")
  + ष           [क, ष]            क्ष       (rewind: halant 挿入、conjunct 化、末尾 schwa)
  + ट           [क, ष, ट]         क्ष्ट      (三重 conjunct)
  + matra ि     [क, ष, टि]        क्ष्टि     (末尾 schwa を i matra に置換、確定)
```

**Virama はユーザーが明示的に打たない**のが重要（自動挿入）。
ただし「schwa 無しで明示的に切りたい場合」のための halant 終端キーは必要。

### 確定トリガー

akshara cluster が確定する条件:

1. **母音 matra 入力** → 末尾 schwa を matra で置換して確定
2. **独立母音入力** → 現 cluster を inherent schwa のまま確定し、新 cluster 開始
3. **明示的 halant キー** → schwa 無しで確定（Sanskrit 文末等）
4. **スペース / 句読点** → 現 cluster を確定

---

## ゲームパッドレイアウト（提案）

### 前提

- GIME 既存の mode 切替で Devanagari モードに入る前提
- LS / LB 等の意味は Devanagari モード時に再割当て（韓国語 자모 모드 と同じ作法）

### 設計原則: varnamala 時計回り

Devanagari ネイティブにとって最強の prior knowledge は **वर्णमाला
(varnamala) の朗唱順**（就学期から刷り込まれる）。音声学的マトリクス
として美しい配置より、**朗唱順を時計回り（↑→→→↓→←→中立）に辿れる**
配置の方が blind typing で圧倒的に強い。指は暗唱と同期して動けば
迷わない。この原則を全レイヤー（varga / stop / 母音）で貫く。

### 子音レイヤー: パンチャヴァルガ (पञ्चवर्ग)

Devanagari 子音は音声学的に 5 分類 (varga) + 非 varga 8 個 = 33。
LS 5 位置に varnamala 順（क→च→ट→त→प）を時計回りに載せる:

| varnamala 順 | varga | 子音 | LS 方向 |
|---|---|---|---|
| 1 | कवर्ग (軟口蓋) | क ख ग घ ङ | **LS ↑** |
| 2 | चवर्ग (口蓋) | च छ ज झ ञ | **LS →** |
| 3 | टवर्ग (そり舌) | ट ठ ड ढ ण | **LS ↓** |
| 4 | तवर्ग (歯) | त थ द ध न | **LS ←** |
| 5 | पवर्ग (唇) | प फ ब भ म | **LS 中立** |

各 varga 内も同じ原理: **varnamala 順の 4 stop を時計回りに**。
鼻音は各 varga に 1 個のみなので D-pad 不要で LB 単独に直送:

| varnamala 順 | 分類 | क行 例 | D-pad 方向 |
|---|---|---|---|
| 1 | 無気無声 | क | **↑** |
| 2 | 有気無声 | ख | **→** |
| 3 | 無気有声 | ग | **↓** |
| 4 | 有気有声 | घ | **←** |
| 5 | 鼻音 | ङ | **LB 単独** |

cardinal 直結（「この方向 = この子音」の 1 対 1）方式を採用し、
**1 子音 = 1 アクション**を死守する（conjunct 連鎖の流暢さ優先）。

### 非 varga 子音 8 個: LS 押し込み + LT サブレイヤー

य र ल व (semivowel 4) + श ष स ह (sibilant + h の 4) を収める:

- **L3 (LS 押し込み)** でサブモード突入
- **LT 押下有無** で 2 サブレイヤー切替（semivowel / sibilant）
- **D-pad 4 方向** で各サブレイヤー内の 4 子音を確定

### 母音レイヤー

短母音 6 個（a, i, u, ṛ, e, o）+ 長母音 6 個（ā, ī, ū, ṝ, ai, au）+ 独立形
の表と matra の出し分け。

face button 4 個も **varnamala 順（a→i→u→e）を時計回り**に配置:

| varnamala 順 | 母音 | face button |
|---|---|---|
| 1 | a (अ) | **↑（Y / △）** |
| 2 | i (इ) | **→（B / ○）** |
| 3 | u (उ) | **↓（A / ×）** |
| 4 | e (ए) | **←（X / □）** |

残る母音は RS に配置:

- **RS ←** = o（ओ）
- **RS ↓** = ṛ（ऋ、低頻度だが Sanskrit で必須）
- **RS →** = **長母音 post-shift**（直前母音を長母音に昇格:
  a→ā, i→ī, u→ū, ṛ→ṝ, e→ai, o→au）
  - `ए/ऐ` と `ओ/औ` は音声学的には別母音だが、guna/vrddhi 系列的には
    ペアなので「伸ばす」操作で対応する設計を採用（Sanskrit 純粋主義には
    譲歩を要求するが、実用入力としては筋が通る）

独立母音 vs matra の分岐は**合成状態から自動判定**（cluster 開始時点なら
独立母音、子音入力後なら matra）。

### 修飾子マッピング

| 修飾子 | スロット | 備考 |
|---|---|---|
| **Halant (्)** | **RT tap** | 明示的 schwa 無し終端。使用頻度中 |
| **Nukta (़)** | **RB tap**（直前子音に後置） | क → क़ 等の Persian 借用音 |
| **Anusvara (ं) ↔ Chandrabindu (ँ)** | **RS ↑ cycle**（2-step） | 鼻音強度の系列、Korean 평격경 と同型 |
| **Visarga (ः)** | **LT + RT 同時** | Sanskrit 専用の超低頻度 |

全修飾子を単一の LS↑ サイクルに押し込むのは **不自然**（halant は構造、
nukta は借用音 dot、anusvara/chandrabindu は鼻音、visarga は Sanskrit 終端
と、機能が全て別系統）。**機能別に配る**のが正解。

### 物理入力の消費一覧

| 入力 | Devanagari モードでの意味 |
|---|---|
| LS 4 方向 + 中立 | varga 選択（5） |
| L3 (LS 押し込み) | 非 varga モード入口 |
| LT | 非 varga サブレイヤー切替 / modifier 系の組合せ |
| D-pad 4 方向 | varga 内子音（stop 4）/ 非 varga 内子音 |
| LB | 鼻音直送（varga モード時）/ 修飾子組合せ |
| face buttons 4 | 主要短母音 4（a, i, u, e） |
| RS ← | o |
| RS ↓ | ṛ |
| RS → | 長母音 post-shift |
| RS ↑ | anusvara ↔ chandrabindu cycle |
| RB | nukta（直前子音に後置） |
| RT | halant（明示的終端） |
| R3 | 予備（候補系 / モード切替） |

**33 子音 + 11 母音 + 5 修飾子 = 49 の意味単位**をこの空間で取り切れる
見込み。

---

## 実装指針

### アーキテクチャ

既存の engine / resolver / composer 3 層構造を踏襲:

- **`DevanagariComposer`**: `KoreanComposer` (Android/iOS 両実装あり) の
  アナロジー。akshara buffer + 即時適用 + 巻き戻しを内部で管理
- `GamepadResolver` に Devanagari 用テーブルを追加（mode enum に拡張）
- `InputManager` / `GamepadInputManager` は非依存（onDirectInsert
  コールバック経由で composer の出力を受け取る）
- engine 層は pure（Android / iOS プラットフォーム非依存）を維持

### PoC 最小セット

1 週間スコープで:

- **33 子音 + 11 母音 matra + halant + backspace**
- 検証文: **`सत्यमेव जयते`**（インド国章、Sanskrit）が正しく打てるか
- conjunct 生成の正しさ: `क्ष्ण`, `त्र`, `द्व` 等の頻出 conjunct
- 独立母音 vs matra の分岐: 語頭 `अ` / 語中 `क + ि`

PoC 完了後に Bengali / Tamil への展開検証。

---

## Brahmic 系への展開

### 共通原理

Devanagari で確立した **「akshara buffer + 即時適用+巻き戻し + halant 自動挿入」**
アルゴリズムは他の Brahmic 系にそのまま適用可能:

- **Bengali** (বাংলা): 子音 ~34 + 母音 ~11 + matra、同じ abugida 構造。
  字体が異なるだけで入力モデルは共通
- **Tamil** (தமிழ்): 子音少なめ（~18、声区別なし）で単純化可能、
  pulli (virama) ベース
- **Telugu** (తెలుగు): Devanagari と近い構造
- **Gujarati** (ગુજરાતી): Devanagari と最も近い、語頭シロス簡略化のみ差分
- **Kannada** (ಕನ್ನಡ) / **Malayalam** (മലയാളം): 同系統
- **Punjabi (Gurmukhi)** (ਪੰਜਾਬੀ): やや変則、子音クラスタ扱いが異なる
- **Thai** (ไทย): Brahmic 系だが声調記号が加わる。子音 44 + 母音 ~15 +
  声調記号 4（重要）。声調を RS↑ サイクルに近い扱いに
- **Burmese** (မြန်မာ): Brahmic 系、conjunct の表記法が独特（stacking）
- **Tibetan** (བོད་): 子音 stacking が特殊で conjunct 表現が垂直方向。
  入力モデルは踏襲可能だが表示は Tibetan 固有

実装戦略: **共通の `BrahmicComposerCore` を作り、言語別テーブル
（子音・母音・連接規則）だけ差し替える**構造にすれば、1 言語追加
コストを大幅削減可能。

### varga 分類は言語横断で通用

パンチャヴァルガ（5 分類）構造は**全ての Brahmic 系に引き継がれている**
（言語によって子音数の多寡はあるが、分類軸は同じ）。したがって
**LS 方向 = varga** のマッピングは全 Brahmic 言語で共通使用可能。

---

## Abjad 系（補記）

Arabic / Persian / Urdu / Hebrew 等の abjad は**子音主体 + 母音記号
（harakat / nikud）がオプション**という構造で、Brahmic とは違う部分も
多いが、基本思想は共通して流用できる:

### Arabic

- 子音 28 個（声門 / 咽頭 / 軟口蓋 / 口蓋 / 歯茎 / 歯 / 唇 の発音位置分類）
- 母音記号 3 基本 + 長母音マーカー + shadda（重子音）+ sukun（無母音）
- **右から左**の表示は表示層のみの問題で入力モデルは影響しない
- **文字の位置による 4 形態変化**（独立 / 頭 / 中 / 尾）は Unicode
  レイヤで自動処理されるため入力側では意識しない
- 子音分類を LS 方向にマップ、母音 harakat を修飾子扱いにすれば
  基本設計は流用可能

### 設計差分

| 観点 | Brahmic | Abjad |
|---|---|---|
| 母音の扱い | akshara 確定に必須 | 任意（通常は省略） |
| schwa の扱い | 子音単独で存在 | 子音単独で無音 |
| 合成規則 | halant 自動挿入 | shadda / sukun は明示 |

母音省略運用も考えると、**Abjad では「母音未入力でも子音連続 commit 可能」**
というモードを追加する必要がある。Brahmic の自動 schwa 付与ロジックを
「自動無母音（sukun）付与」に置き換える発想で扱える。

この方向は **Devanagari が動いた後のフェーズ 2** の位置づけで、まず
Brahmic 系の汎用性を固めてからの適用が合理的。

---

## 未解決の設計判断 / 要検証項目

1. **e/ai, o/au を length pair 扱いにするか**: RS→ で伸ばす仕様にするか、
   別スロットで独立させるか。実用性 vs 純粋性のトレードオフ
2. **独立母音と matra の切替ロジック**: buffer 状態からの自動判定で
   十分か、明示モードキーが必要か
3. **L3 + LT サブモードの ergonomics**: LS 押し込みは操作として重い。
   代替として RB 長押し等の検討
4. **Devanagari モード中の LS 候補 cycle 機能**: 既存の候補移動機能を
   どこに退避させるか
5. **学習辞書の必要性**: Devanagari 変換は仮名漢字変換ほど曖昧性がない
   （綴り = 発音）ので、変換エンジン自体は不要。ただし**予測変換**で
   単語頭数文字から候補提示する機構はあると打鍵効率が上がる
6. **Zero-width joiner (ZWJ) / non-joiner (ZWNJ)** の扱い: conjunct を
   わざと分解したい専門用途向け

---

## 関連ドキュメント

- `CLAUDE.md` — 既存 GIME アーキテクチャ
- `docs/keymap-format.md` — キーマップ定義仕様（Devanagari 用拡張の参考）
- `docs/gamepad-mapping.md` — 日本語ゲームパッドマッピング（同じ枠組で
  Devanagari 用 mapping 仕様書を書き起こす）
- `Sources/GIME/KoreanComposer.swift` — akshara-cluster 風合成の先例
- `android/.../engine/KoreanComposer.kt` — 同上

---

## 戦略的位置付け（再掲）

GIME は既に「アジア特化ニッチ」に見えるが、実際には**世界人口の
半分弱**を射程に収めている。Devanagari → Brahmic 系 → Abjad 系の
展開で:

- **VR 入力の leapfrog moment** を捉える
- **"世界で最もユニバーサルな VR 入力装置"** というポジション
- 音声入力が使えない無言勢 + VR シナリオで英語が一番苦手言語という
  皮肉な構図を維持（Asian scripts の追加ほど GIME の独自性が強化される）

余談から発展した設計だが、取りこぼすには惜しい芯の話。
