# KIDE — Keyboard Interface Device Emulator

USB OTG 接続の物理キーボードを Bluetooth HID キーボードに化けさせて、
任意の機器に任意の配列で入力できるようにする Android アプリ。

「かえうち」を BT 出力 + ソフトウェアエコシステム + USB Type-C 入力で
再定義した代替案。

## ペルソナ

- HHKB + MacBook の尊師スタイルに馴染んでいるパワーユーザー
- あるいは軽量タブレット (iPad / Surface 等) を使いつつキーボードには
  妥協したくないノマドワーカー
- 新配列（大西配列 / Colemak / Dvorak）や親指シフト・薙刀式を
  「試したい・常用したい」
- ただし「かえうち」のような USB-A ハードウェアは過去の遺物に感じる
- 配列を **試打サイクル単位（分→秒）** で切り替えたい

このペルソナにとっての理想的な代替物として位置付ける。

## 位置付け

GIME ファミリーの第三弾。GIME（自機内ゲームパッド入力）/ GiDE（ゲームパッドを
BT HID 化）に続き、KIDE は「物理 USB キーボードを BT HID 化しつつ配列変換する」
方向。GiDE は構造的限界 (chord 判定 + ローマ字展開で物理キーボード比 2-4x
オーバーヘッド) で諦め、KIDE はその知見を踏襲しつつ、より現実的な範囲で
「物理キーボードに近い体験」を目指す。

## 「かえうち」との比較

| 観点 | かえうち | KIDE |
|---|---|---|
| ハードウェア | 専用機（追加購入） | 手持ちの Android 端末 |
| 入力ポート | USB-A | **USB-C (OTG)** |
| 出力経路 | USB-A 物理接続 | **BT HID ワイヤレス** |
| MacBook 接続 | USB-A 変換ハブ必須 | BT で直結 |
| iPad / Quest / visionOS 接続 | **物理的に不可** | **BT で直結** |
| PC 側ポート占有 | 1 ポート | 0 ポート |
| 配列切替 | 専用ツールで焼き込み | スマホ GUI で即切替 |
| 試打サイクル | 数分〜数十分 | **数秒** |
| 配列共有 | 個別ファイル配布 | **配列ハブ JSON で PR ベース運用** |
| 配列ビジュアライザ | なし | 配列図 + レイヤー追従 + 前置シフト表示 |
| 持ち運び物 | 本体 + ケーブル + 変換アダプタ | スマホ + USB-C ケーブル 1 本 |
| 価格 | 数千〜万円 | **無料 OSS** |

「かえうち」との完全競合ではなく、棲み分け:
- **かえうち**: ハードウェア完結、Windows/Linux + USB-A 派、安定動作優先
- **KIDE**: ソフトウェアエコシステム重視、USB-C / BT 派、試打・配列共有志向

## MVP スコープ

### 入力経路

**USB OTG 接続のキーボード**から Android KeyEvent を受信。BT 接続キーボードは
**HID プロファイル排他制約**（Android スタックの構造上）で HID Device 役と
同時成立しないため対象外。

### 出力経路

`BluetoothHidDevice` で BT HID Device 役を演じ、ホストに HID Report を送出。
基本的に GiDE Phase 0.5 で確立した実装をそのまま流用。

### サポートする配列タイプ

#### Phase 2: シンプルキー置換（1物理キー → 1出力キー）

- **大西配列** / **Colemak** / **Dvorak** / **Norman** 等
- **AZIK** (前置シフト・拡張ローマ字)
- **月配列 2-263 / 2-294** 等の前置シフト系
- 実装: KeymapDefinition v1 JSON をパースして keycode マッピング

#### Phase 4: 同時打鍵 chord 配列

- **薙刀式** v15
- **親指シフト (NICOLA)**
- **新下駄配列** 等
- 実装: KeyLogicKit の `SimultaneousKeyBuffer` / `ChordKey` / `KeyRouter` を
  Kotlin port

### 受信側機器

「かえうち」と同様に **OS 非依存の標準 BT HID キーボード**として認識される
ので、Mac / Windows / Linux / iPad / Quest / visionOS / Chromebook で
動作する想定。MVP では **MacBook + iPad** を主検証対象とする。

### 出力フォーマット

配列定義のセマンティクス（例: 「同時打鍵で『あ』」）を **受信側 IME に
どう渡すか** で 2 通り:

- **ローマ字展開モード**: 「あ」→ `a` を HID 送出。受信側 IME が
  ローマ字入力モードで解釈
- **JIS かな展開モード**: 「あ」→ JIS かなキーコードを HID 送出。
  受信側 IME がかな入力モードで解釈

GiDE Phase 3 で明らかになったとおり、JIS かな展開のほうが stroke 数で
30-50% 有利。MVP ではローマ字展開を先行実装し、Phase 4 以降で JIS かな
展開を追加（同じ配列を両方の出力で試せるようにする）。

### キー配列の OS-側設定

受信側 OS の入力ソースはユーザーが手動で切替える前提（自動切替なし）:

- MacBook: 「英字」/「日本語 - ローマ字」/「日本語 - かな」
- iPad: 同上
- Windows: 「英語」/「日本語ローマ字入力」/「日本語かな入力」

これにより OS 別の分岐コードを完全に排除（GiDE で確立した方針）。

## アーキテクチャ概要

```
[USB キーボード] --USB OTG-->
  Android KeyEvent (ACTION_DOWN / ACTION_UP)
    → KeyRouter（KeyLogicKit から移植）
       - シンプル置換: keycode マッピング
       - 前置シフト: シフト状態管理
       - 同時打鍵: SimultaneousKeyBuffer
    → KeyAction
       - .printable(c): ASCII を送出
       - .composedKana(kana, replaceCount): かなを送出（ローマ字 or JIS かな）
       - .specialKey(key): Enter / Tab / 矢印 等
    → KeystrokeEmitter（GiDE から流用）
       - 配列ごとに合計された HID stroke 列
    → BluetoothHidDevice → HID Report
    → 受信機側 OS が標準 BT キーボード入力として処理
```

## モジュール構成

monorepo (`logical-layout-labo`) 内に `android-kide/` を追加。

```
android-kide/
  app/
    src/main/
      java/com/msonrm/kide/
        hid/           ← GiDE から流用（KeystrokeEmitter / HidKeyboardManager 等）
        input/         ← 新規。USB OTG キーボード受信 + KeyEvent ハンドリング
        engine/        ← KeyLogicKit から Kotlin port
                         - KeymapDefinition / KeymapCodable
                         - KeyRouter / ChordKey / SimultaneousKeyBuffer
                         - KanaToRomajiTable（GiDE から流用）
                         - KanaToJisKeyTable（Phase 4 で新規）
        ui/            ← 配列選択 / ビジュアライザ / 接続状態
        MainActivity.kt
    res/...
  build.gradle.kts
  app/build.gradle.kts
  ...
```

### コード取り込み方針

- **GiDE の `hid/` パッケージ**は 1:1 で `com.msonrm.kide.hid` にコピーして
  パッケージだけ差し替え。HID 送信の振る舞いは GiDE で実機検証済みなので
  そのまま流用する。
- **GiDE の `KanaToRomajiTable`** はローマ字展開モードで流用。
- **KeyLogicKit** (`Sources/KeyLogicKit/IME/*.swift`) は Kotlin port。
  データ駆動設計なので機械的に移植可能（Swift と Kotlin の文法差を吸収
  する程度の修正で済む想定）。

GIME / GiDE と同様、共通モジュール化（composite build / submodule 等）は
しない。コピー追従でメンテする。

## 配列定義の流用

`web/public/keymaps/*.json` に既に存在する配列定義をそのまま読み込めるように
する。`KeymapDefinition v1` JSON Schema (`docs/keymap-v1.schema.json`) に
準拠。Phase 2 以降、Android 側で同じスキーマを Kotlin で再パースする。

これにより:
- 配列ハブ Web サイトで新配列が増えたら、KIDE でも自動的に試せる
- ユーザーが自作した配列 JSON を import する経路を共通化
- 配列の検証は Web 側で済んでいるものを KIDE で再利用

## レイテンシ予測

物理 BT キーボードを基準（1.0x）として:

| 配列タイプ | 入力レイテンシ | 出力 stroke 数 | 体感 |
|---|---|---|---|
| シンプル置換（Dvorak/Colemak） | +5-10ms | 1:1 | **★★★★☆** 物理比 1.5x、ほぼ気にならない |
| 前置シフト（月配列/AZIK） | +5-10ms | 1 stroke | **★★★★☆** 同上 |
| 同時打鍵 chord（JIS かな出力） | +20-40ms | 1-2 stroke | **★★★☆☆-★★★★☆** chord 判定の自然な遅延 |
| 同時打鍵 chord（ローマ字出力） | +20-40ms | 2-3 stroke | **★★★☆☆** GiDE と同じローマ字展開オーバーヘッド |

GiDE と比較した致命的優位:
- chord 判定が単純化（pressesEnded ベース、タイマー不要）
- HID stroke 数の削減（シンプル置換なら 1:1、JIS かな出力なら平均 1.5x）
- eager output 巻き戻し（BS）が原理的に発生しない

## Phase 分け

### Phase 0: 環境準備 ✅ (PR #575 merged)
- `android-kide/` プロジェクト雛形
- GiDE の `hid/` パッケージをコピーして `com.msonrm.kide.hid` に変換
- Compose プロジェクトとして起動できる状態まで
- Placeholder MainActivity で BT HID Device 役の初期化のみ

### Phase 1: USB OTG キーボード受信プロトタイプ ✅ (PR #576, #577 merged)
- USB HID キーボードを `InputDevice` として認識
- `dispatchKeyEvent` で KeyEvent を捕捉
- 受信した KeyEvent をログ表示
- **発見**: `KeyEvent.scanCode` は **Linux evdev keycode** で、USB HID Usage
  ではない (例: Q キー = scanCode 0x10 = KEY_Q)。`EvdevToHidUsageTable` で
  変換が必要

### Phase 2: シンプル置換配列 ✅ (PR #578, #581 merged)
- `EvdevToHidUsageTable` (evdev → HID Usage 変換)
- `SimpleKeyRemap` data class + Identity / Dvorak / Colemak ハードコード
- `HidModifier.fromMetaState` (metaState → HID modifier byte)
- 配列選択 UI + Send to host トグル (誤送出防止のセーフガード)
- CapsLock を Android シングルソースに揃え、letter キーには Shift bit に
  XOR で翻訳 (HID modifier byte には CapsLock bit がないため)
- `dispatchKeyEvent` で Tab / Enter / 矢印 / PageUp/Down も含めて捕捉
- CapsLock keypress は consume せず Android system に流して状態同期

### Phase 3: AZIK 拡張ローマ字 ✅ (PR #582)
- `KeyRouter` interface + `KeyInput` data class 抽象化
- `KeyAction` sealed class: `None / SingleStroke / RollbackAndSendString`
- `SimpleKeyRemapRouter`: Phase 2 のシンプル置換を Router 化
- `AzikRouter`: eager + BS rollback、任意長最長一致
- `AzikTable`: `azik_us.json` の suffix + inputMappings を ASCII シーケンスに
  事前展開 (約 190 規則)
- 最適化: 共通プレフィックス削減 (例: `kf → ki` を `BS×0 + i` の 1 stroke で送出)
- マッチ後 buffer クリアで誤連鎖展開防止 (例: `kzji → かんじ` を正しく)
- `interStrokeDelayMs` default を 3ms に下げ (USB OTG 入力は BT より信頼度高)
- 月配列は出力モデルが JIS かななので Phase 4 以降に分離

### Phase 4: 同時打鍵 chord + JIS かな出力 (着手中、NICOLA chord PoC まで)

**完了済み:**
- `assets/keymaps/` への JSON 同梱 (`romaji_colemak_us.json` / `azik_us.json` / `nicola_us.json`)
- `com/msonrm/kide/keymap/` パッケージ
  - `KeymapDefinition` + `KeymapLoader`: `org.json` だけで KeymapDefinition v1
    (`web/public/keymaps/*.json`) をパース。sequential / chord 両 behavior を
    扱える。`_comment_*` キーは無視。
  - `RomajiBaseTable`: `Sources/KeyLogicKit/IME/DefaultKeymaps.swift` の
    `standardRomajiTable` を Kotlin port (約 250 規則)。`inputBase: "romaji"`
    展開時のベース。
  - `KeymapExpansion`: 2 系統の展開を提供:
    - `expandToAzikAsciiTable`: AZIK ASCII 出力 router 用 (base 差分のみ kana→ASCII)
    - `expandToKanaTable`: JIS かな出力 router 用 (base 含む全エントリーを kana のまま)
- `SimpleKeyRemap.fromKeymap(def)` で `keyRemap` フィールドから物理→論理 HID Usage マップを構築
- `AzikRouter.fromKeymap(def)` で JSON 由来テーブル (ASCII 出力) を受け取る形に refactor。
  ハードコード `AzikTable.MAP` (約 190 規則) を削除。
- `KanaToJisKeyTable` (`engine/`): かな → JIS かな入力モードでの HID stroke 列。
  Mac の「日本語 - かな入力」(ANSI 物理) を基準にした 50 音 + 濁音/半濁音
  (2 stroke 合成) + 小書き (Shift+key) + 句読点。OS 別分岐は持たず、ごく
  標準的な ANSI HID キーボードとして振る舞う。
- `SequentialKanaRouter` (`engine/`): AZIK と同じ JSON 定義から **JIS かな出力モード**
  の router を構築。eager+rollback ではなく **buffer + 最長一致 + 完成 kana 単位で emit**
  モデル (`n` や `q` は次入力まで defer する標準ローマ字 IME 相当の挙動)。
- `KeyAction.EmitStrokes(List<KanaStroke>)` 新規。`HidKeyboardManager.executeAction`
  で複数 HID stroke の順次送出に対応 (`interStrokeDelayMs` が自動で挟まる)。
- `MainActivity.buildAvailableRouters()` で起動時に assets を一括ロード:
  - `behavior: sequential` + `keyRemap` あり → `SimpleKeyRemapRouter` (Colemak 等)
  - `behavior: sequential` + `inputBase`/`suffixRules` → **`AzikRouter` (ASCII 出力)
    と `SequentialKanaRouter` (かな出力) を両方並べる**
  - `behavior: chord` → ChordBuffer 未実装のため skip + log
- 副産物として AZIK の対応規則が増加 (旧 hardcoded 約 190 規則 → JSON 由来は
  単語ショートカット `kt→こと` 等を含む全範囲)
- Identity / Dvorak はハードコード継続 (JSON 等価物が `web/public/keymaps/` に無いため)

**Phase 4 後半 + 月配列 完了済み:**

- 月配列 2-263 (US) を `assets/keymaps/tsuki2-263_us.json` として同梱。
  `MainActivity.buildAvailableRouters` の振り分け条件を緩和し、`inputMappings`
  だけを持つ前置シフト系 JSON も `AzikRouter` (ASCII 出力) +
  `SequentialKanaRouter` (JIS かな出力) の両モードで router 化されるようにした。
  月配列の `d` / `k` 前置シフトは router の buffer + 最長一致ロジックで
  自然に表現される (`d` は単体で table に無い → prefix 扱いで wait、`dq` で確定)。
- `KanaToJisKeyTable` に単独濁点 `゛` / 半濁点 `゜` を追加。月配列の `l → ゛`
  / `/ → ゜` のような独立 kana を JIS HID stroke として送出可能に。

**Phase 4 後半 完了済み (chord PoC):**
- `engine/ChordKey.kt`: `KeyLogicKit/IME/ChordKey.swift` の Kotlin port。33 キー
  (QWERTY 30 + space + leftThumb + rightThumb) の bit mask (Long)。
- `engine/SimultaneousKeyBuffer.kt`: `SimultaneousKeyBuffer.swift` の Kotlin port、
  KIDE 用にシンプル化 (3 キー chord 差し替えは未実装、ASCII rollback 系も省略)。
  Phase enum (accumulating / passthrough / shiftMode) + inter-key timing +
  idle gating + シフトモード移行 を含む。
- `engine/ChordKanaRouter.kt`: chord JSON 定義を `SimultaneousKeyBuffer` と
  組み合わせて消費するルーター。`KanaToJisKeyTable` で kana を JIS HID stroke
  に変換して emit。Right Alt 等の HID Usage 表に無いキーを scanCode で検出する。
- `KeyRouter` interface に `keyDown(input, emit)` / `keyUp(input, emit)` を追加
  (sequential router はデフォルト実装で route() を 1 回呼ぶだけ。chord router は
  直接 override)。
- `MainActivity.dispatchKeyEvent` で ACTION_UP も router に渡すようにリファクタ。
  ChordKanaRouter は keyUp で single tap / shift release 判定を行う。
- NICOLA (`nicola_us.json`) を `ChordKanaRouter.fromKeymap` でロード。
  - 左親指 = Space、右親指 = Right Alt (ANSI) または 変換キー (JIS)
  - 30 letter chord (Q→。 等の単独) + 60 chord (leftThumb+X / rightThumb+X)
  - 受信側 OS の入力ソースを「日本語 - かな入力」に切替えて使う

**残り:**
- NICOLA 実機検証
- 3 キー chord 差し替え (薙刀式向け)
- 薙刀式 / 新下駄 (chord JSON → router)
- 月配列の本対応 (前置シフト + JIS かな出力)
- ローマ字 / JIS かな 切替 UI (現状は router 一覧に両モードを並べる暫定 UI)

### Phase 5: UX 仕上げ (未着手)
- 配列ビジュアライザ Compose 移植（`KanaEditor/UI/KeyboardPanel/KeyboardView.swift` を参考）
- 配列ハブ JSON のインポート（URL からダウンロード or ファイル選択）
- 接続状態の細やかな表示
- 受信側 OS 別のセットアップガイド (Mac / iPad / Windows / Quest)
- TuningCard 復活 (interStrokeDelayMs / coalesceWindowMs スライダー)

## 実機検証ノート (Phase 3 までの実測)

### iPad の Apple Japanese IME はラグ大

実機検証で **iPad の標準日本語 IME (ローマ字モード) は KIDE 入力に対して
顕著な遅延**を示すことを確認。これは Android 側 (KIDE)・BT HID 経路では
なく、iPad の IME 処理時間が支配的:

- **ライブ変換 OFF**: 「最悪」(連続入力で目に見えるラグ)
- **ライブ変換 ON**: 「かなり悪い」(若干軽減するが実用には足りない)
- **iPad + Siberia (自作エディタ、システム IME 非依存)**: **快適**
  → iPad のシステム IME 自体が遅延要因と確定

### KIDE 側でできる最適化 (Phase 3 で実施済)

- HID stroke 数削減 (共通プレフィックス削減、buffer クリア)
- `interStrokeDelayMs` 短縮 (10ms → 3ms)
- 物理的下限は BT HID の service interval (~7.5ms) で、0ms にしても
  ワイヤ上の挙動はほぼ変わらない

### Phase 3 後の検証スコープ (Phase 4 と並行で実施予定)

iPad のシステム IME は遅いが、ペルソナの主力は **MacBook + HHKB の
尊師スタイル** や **Windows / Surface のノマドワーカー**。これらの OS の
標準 IME 実装 (ことえり / Google IME / MS-IME 等) は iPad と異なり、
実用域のレイテンシで動く可能性が高い。

優先順位:
1. **MacBook (BT HID) + ことえり** での AZIK 検証
2. **Windows / Surface + MS-IME** での検証
3. Quest / visionOS は副産物

各機種の動作所感は本ファイルに継続的に追記する。

## 既知のリスクと検証ポイント

### USB OTG キーボードの認識互換性

Android が USB HID キーボードを認識するには、キーボードの HID Descriptor が
標準準拠している必要。HHKB / Realforce / Apple Magic Keyboard などの主要
プロダクトは問題ない想定だが、ゲーミングキーボード等で変則的な Descriptor
を持つ場合は要検証。

### Android 端末の給電と USB OTG

OTG ホスト動作中は Android が USB バスへ給電する。長時間使用すると電池
消費が無視できないので、**電源パススルー対応の USB-C ハブ**を介すと
電源とキーボードを同時接続できる。

### キーボードの N-key rollover

同時打鍵 chord 配列（薙刀式 / 親指シフト）では複数キー同時押しが必要。
HID Boot Keyboard 互換の 6KRO で実用上 OK だが、稀に押下が重なるケース
（フェイル）あり。NKRO 対応キーボード推奨。

### `BluetoothHidDevice` のホスト互換性

GiDE Phase 0.5 で Pixel 10 + iPad を確認済み。Android 機種依存差は残るので
README にサポート機種・推奨機種を明記する想定。

### 受信側 OS の入力ソース設定

- MacBook の Hiragana / Katakana 「ローマ字」「かな」モードの挙動差
- iPad の日本語 IME の「ライブ変換」OFF 推奨（GiDE Phase 3 の知見）
- 受信側に何も設定変更させない MVP は不可能。セットアップガイドを充実
  させる方針。
- 受信側 OS 別の分岐コードは置かず、ごく標準的な BT HID キーボードとして
  振る舞う。Mac / iPad / Windows / Surface / Chromebook / Linux / Quest /
  visionOS いずれも同じ HID Report で動作する想定 (Phase 0.5 で GiDE が
  実証済みの方針)。

## 参考

- `GiDE-spec.md`: ゲームパッド版の MVP スペック
- `docs/gide-spec-eval.md`: GiDE 実現可能性評価 + KIDE 派生案
- `KeyLogicKit/IME/SimultaneousKeyBuffer.swift`: 同時打鍵バッファ参考実装
- `web/public/keymaps/*.json`: 配列ハブの JSON 定義群
- かえうち: https://kaeuchi.jp/ — ベンチマーク対象

## ライセンス

GIME / GiDE と同じ MIT License。

---

このスペックは MVP 着手前の方針共有を目的とした軽量版。実装詳細は
Claude Code 上で既存コードを参照しつつ再検討する。
