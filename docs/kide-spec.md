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

### Phase 0: 環境準備
- `android-kide/` プロジェクト雛形
- GiDE の `hid/` パッケージをコピーして `com.msonrm.kide.hid` に変換
- Compose プロジェクトとして起動できる状態まで
- Placeholder MainActivity で BT HID Device 役の初期化のみ

### Phase 1: USB OTG キーボード受信プロトタイプ
- USB HID キーボードを `InputDevice` として認識
- `dispatchKeyEvent` で KeyEvent を捕捉
- 受信した KeyEvent をログ表示するだけ（HID 送出はしない）
- 物理キーが正しく `KEYCODE_*` + `scanCode` で取れることを実機確認

### Phase 2: シンプル置換配列（Dvorak / Colemak / 大西）
- KeymapDefinition v1 JSON のパース
- Android KeyEvent → HID Usage 変換テーブル
- 配列選択 UI
- 「物理 A キーを Dvorak A キーで打つ」相当の挙動を実機確認

### Phase 3: 前置シフト配列（AZIK / 月配列）
- シフト状態管理
- ローマ字展開モードでの送出

### Phase 4: 同時打鍵 chord（薙刀式 / 親指シフト）
- KeyLogicKit の `SimultaneousKeyBuffer` / `ChordKey` を Kotlin port
- KanaToJisKeyTable（JIS かな出力モード）の追加
- ローマ字 / JIS かな 切替 UI

### Phase 5: UX 仕上げ
- 配列ビジュアライザ Compose 移植（`KanaEditor/UI/KeyboardPanel/KeyboardView.swift` を参考）
- 配列ハブ JSON のインポート（URL からダウンロード or ファイル選択）
- 接続状態の細やかな表示
- 受信側 OS 別のセットアップガイド (Mac / iPad / Windows / Quest)

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
