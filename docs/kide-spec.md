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

### Phase 4: 同時打鍵 chord + JIS かな出力 ✅ (PR #588, #594, #595, #598)

**核仮説 validation は完了**。Phase 4 の柱だった以下の経路が実機 (iPad の
「日本語 - かな入力」モード) で動作することを確認:

1. **JSON ローダー基盤**: `web/public/keymaps/*.json` を Kotlin でパースして
   router を組み立てる経路。`KeymapDefinition` + `KeymapLoader` +
   `RomajiBaseTable` + `KeymapExpansion`。配列追加が JSON 配置 + 起動の 2 ステップ
   で済むようになった。
2. **JIS かな直接出力**: `KanaToJisKeyTable` + `KeyAction.EmitStrokes` +
   `SequentialKanaRouter`。受信側を「日本語 - かな入力」モードに切替えれば、
   KIDE が ANSI HID Boot Keyboard として送る Usage ID をそのまま kana として
   解釈してくれる。受信側のローマ字 IME を経由しないので、Phase 3 で課題に
   なった iPad のローマ字変換ラグを完全に回避できる。
3. **同時打鍵 chord**: `ChordKey` (33 キーの bit mask) + `SimultaneousKeyBuffer`
   (Swift 版の Kotlin port) + `ChordKanaRouter`。NICOLA を `Space + letter`
   chord で実用域の体感まで持って行けた。
4. **前置 / 後置 シフト**: `SequentialKanaRouter` の buffer + 最長一致が、
   月配列 2-263 の `d` / `k` 前置シフトと `l` / `/` 後置濁点に **追加コード無し**
   で乗ることを確認。

#### 実機検証で動く router 一覧 (iPad 上で確認済)

| Router | 出力 | 受信側設定 | 例 |
|---|---|---|---|
| QWERTY (identity) | ASCII passthrough | 何でも | — |
| Dvorak | ASCII | 何でも | physical Dvorak 風 |
| Colemak (US) | ASCII | ローマ字入力 | `ks` → か |
| AZIK (US) | ASCII ローマ字 | ローマ字入力 | `kz` → `kann` → かん |
| AZIK (かな出力) | JIS かな | **かな入力** | `kz` → か + ん → かん |
| 月配列2-263 (US) | ASCII ローマ字 | ローマ字入力 | `q` → `so` → そ |
| **月配列2-263 (かな出力)** | **JIS かな** | **かな入力** | `q` → そ, `q+l` → そ+゛ → ぞ |
| **NICOLA (かな出力)** | **JIS かな** | **かな入力** | T → か, Space+A → を, RAlt+S → じ |

#### ハードコード廃止の状態

- `SimpleKeyRemap.Colemak` (旧) → 削除。JSON 由来
- `engine/AzikTable.kt` (旧、約 190 規則ハードコード) → 削除。JSON 由来
- 残ったハードコード: Identity (透過) と Dvorak (JSON 等価物が `web/public/keymaps/`
  に無いので保留)

### Phase 4 実機検証ノート

#### iPad で「JIS かな入力モード」は実用域、ローマ字モードはラグ大 (Phase 3 知見の再評価)

Phase 3 で「iPad のシステム IME は連続入力に対して遅延が大きい」と結論したが、
これは **ローマ字入力モード** に限った話だった。Phase 4 で **JIS かな入力モード**
を使うと、iPad は kana を直接受け取って表示するだけになり、ローマ字→kana の
変換処理が不要なため、**ペルソナ的にはこちらが本命の経路**。

- AZIK ASCII (ローマ字 IME 経由) → 「ほんのちょっと遅延」
- AZIK / 月配列 / NICOLA かな出力 (JIS かな入力経由) → **実用域**

これにより KIDE の中核仮説 (「USB-C キーボード + iPad で自由な配列を載せる
尊師スタイル」) の **iPad ペルソナ向け解** が初めて成立した。

#### Phase 4 で潰したバグ (実機検証由来)

| 症状 | 原因 | 修正 |
|---|---|---|
| `ro` / `vo` → お になる | `KanaToJisKeyTable` に ろ と ヴ が無く、router が フォールバック emit | ろ → backslash 追加、ヴ を DAKUON_BASE 追加、未対応 kana は silent flush |
| AZIK kana で `kz → かん` が空テーブル化 | `KanaToRomajiTable.convert` が 2 char kana を 直接 lookup のみで処理して 「かん」 を取れず | 早期 return 廃止、常にループで分解 |
| BS / Enter / 矢印 が Android にすり抜ける | `ChordKanaRouter` が `hidToKey` の key しか consume しない | 非 chord キーは buffer reset + 元 stroke passthrough |
| 高速 chord 連打で 2 つ目以降が無反応 | 2 キー chord 出力後、シフト保持中に 新 letter が来ても 3 キー目として追加されるだけで評価されない | `chordOutputted && !isShiftKey(key)` 時に「同じシフト + 新 letter」で新 chord として再評価 |
| 月配列 `q → そ` が 1 stroke 遅延 | `q` が `ql` の prefix と見なされて defer | explicit (`inputMappings` 直接書き) は `hasLongerPrefix` をスキップ |

#### 入力モデルの整理 (Phase 4 で確立)

- **sequential**: 物理キーをそのまま buffer に積み、最長一致でテーブル lookup。
  AZIK / 月配列 はこちら。AZIK ASCII 出力 (`AzikRouter`) は eager + BS rollback、
  JIS かな出力 (`SequentialKanaRouter`) は buffer + 確定 emit。
- **chord**: 物理キー位置の bit を組み合わせて lookup。NICOLA はこちら。
  `SimultaneousKeyBuffer` が state machine (accumulating / passthrough /
  shiftMode) を持ち、inter-key timing + idle gating でロールオーバーを吸収。

両モードとも JSON 定義に乗っているフィールド (`inputMappings` / `suffixRules` /
`hidToKey` / `lookupTable` 等) からそのまま組み立てられる。

#### SandS / specialActions 対応 ✅

`KeyActionParser` (`engine/KeyActionParser.kt`) で `shiftKey.singleTapAction`
と `specialActions` の文字列 (例: `"convert"`, `"deleteBack"`, `"moveLeft"`) を
[KeyAction] に変換するようにした。これにより:

- **SandS の core**: chord 配列 (NICOLA / 薙刀式) でシフトキー単独タップが
  意味を持つようになる。NICOLA の leftThumb (= Space) 単独タップ → Space 送出
  (= IME 変換) として動く。薙刀式 も同じく space tap → IME 変換。
- **specialActions**: 薙刀式 の `T → moveLeft`, `U → deleteBack`, `M+V → confirm`
  などが宣言通りに動く。
- 受信側 IME を直接操作する系 (`confirmHiragana` 等) や KIDE 内部の router
  切替 (`switchToEnglish` 等) は現状 no-op。後で対応する余地は残してある。

これで 薙刀式 の前提のうち「parser 系」 は片付いた。残るは **3 キー chord
upgrade** だけ。

#### HID descriptor 拡張 + JIS 配列対応 ✅

Boot Keyboard 標準の Usage Max は 0x65 (101) で International / LANG キーが
送出範囲外だった。`HidConstants.BOOT_KEYBOARD_REPORT_DESCRIPTOR` で
Usage Max を 0xDD (221) まで拡張し、International1 (0x87 = ろ) / LANG1
(0x90 = ひらがな toggle) / LANG2 (0x91 = 英数 toggle) 等を送れるように。

実機検証で確定したこと:
- iPad ANSI 物理キーボード判定のままでは extended range の Usage は受け付け
  られない (silent ignore)
- **iPad 側で 「日本語 - JIS」 配列を明示的に選択 + 再ペアリング** で初めて
  extended range の Usage が JIS かな layout として解釈される
- これで `ろ` (= AZIK `ro` / NICOLA `leftThumb+C` / 月配列 `dm` 等) が
  打てるようになる
- 副産物: LANG2 (0x91) で iPad の IME を 英数 ←→ 日本語 にトグルできる
  (薙刀式 `switchToEnglish` 用 の HID 経路として `KeyActionParser` で対応済)
- **JIS 配列モードでは ANSI モードと右側記号エリアの mapping が異なる**:
  `=`(0x2E)=へ, `[`(0x2F)=濁点, `]`(0x30)=半濁点, `\`(0x31)=む
  (ANSI モードは `=`=半濁点, `]`=む, `\`=へ で同じキーが別 kana になる)
  KIDE は **JIS 配列モード前提** に KanaToJisKeyTable を構築している。
  ANSI モードのまま使うと半濁音 (ぽ ぱ ぴ ぷ ぺ) が全部壊れる。
- Apple 独自の Shift+key 経路で `Shift+E = ぃ` などの small kana 追加経路が
  あることを発見。`Shift+[ = 「`, `Shift+] = 」` も。これらも KanaToJisKeyTable
  に取り込んで `ぃ` 含む chord (薙刀式 でぃ / てぃ 等) も動くようになった。

セットアップ要件:
- iPad: 設定 → 一般 → キーボード → ハードウェアキーボード → 配列 で
  「日本語 - JIS」 を選択 (iPadOS 16.1+ 必須)
- iPad の Bluetooth → KIDE のペアリングを一度削除して再ペアリング
  (HID descriptor 変更後、receiver 側 cache を更新する必要あり)
- SDP 名 を `KIDE (JIS)` にすることで、Bluetooth デバイス一覧での視認性向上

Auto-detect (= ANSI 物理を自動で JIS 認識) は不可:
- iPadOS の auto-detect は Apple 純正キーボードの VID/PID 依存
- BT HID Profile の HIDCountryCode を Android が AOSP 内部で 0 にハードコード
  (`BluetoothHidDeviceAppSdpSettings` の public API は country code を露出
  していない)
- KIDE 側で auto-detect させる手段は無く、ユーザの手動設定に依存

#### 3 キー chord upgrade ✅

`SimultaneousKeyBuffer` に「2 キー chord 出力後に 3 キー目が追加されたら、
出力 stroke を BS で巻き戻して 3 キー chord として再 emit」 ロジックを追加。
薙刀式 が 159 chord 中 51 件 (32%) を 3 キー chord で持つので必須。

実装:
- `onOutput` の signature を `(strokes, replaceCount)` に拡張。`replaceCount`
  は直前 chord 出力を巻き戻す stroke 数 (通常 0、3 キー upgrade 時に非 0)。
- `lastChordEmittedStrokeCount` を内部で持ち、次の chord 評価で BS 数として
  使う。`resetChordState` でリセット。
- `handleKeyDownAccumulating` に **「新キー追加で 3 キー lookup があれば
  upgrade」** 分岐を追加。chord 出力後の高速 rolling (NICOLA 風) との競合は、
  3 キー upgrade 優先 + lookup 無ければ rolling fallback で解決。
- `ChordKanaRouter.onOutput` は `replaceCount` 個ぶん BS の `SingleStroke` を
  pendingActions に積んでから `EmitStrokes` を積む。

#### 薙刀式 をロード可能に ✅

`assets/keymaps/naginata_us.json` を web 配列ハブから同梱。chord 159 件
(1 キー 26 / 2 キー 82 / **3 キー 51**) + specialActions (T→moveLeft / U→deleteBack /
F+G→switchToEnglish / M+V→confirm 等) を含む。`ChordKanaRouter.fromKeymap`
は既存のロジックでそのまま組み立てる。

### Phase 4 残タスク

- **薙刀式 ラスボス戦の本検証**: 実機 (iPad「日本語 - JIS」 配列 +
  「日本語 - かな入力」 IME モード) で 159 chord を一通り試す。
  3 キー chord (外来音 でぃ / てぃ / ぐぁ / どぅ 等) も含めて確認。
  小書き `ぃ` は JIS かな layout 上 標準アクセス手段が無いので、
  「でぃ」 系の chord は KIDE 側で silent flush。
- **chord simultaneous window の正規対応**: 現状 診断用 3x 倍率で hardcode。
  per-pair timing への移行か、UI スライダーで動的調整可能に。
- **`englishLookupTable` 対応** (薙刀式 の F+G で 英語モードに切替えた後の
  英字入力 layout)。`switchToEnglish` の LANG2 送出は既に実装済 (iPad の
  IME 切替は機能) なので、英語モード時の chord lookup を別 table に切替える
  機構を追加すれば 薙刀式 の英語入力が完成する。
- **新下駄 / 飛鳥 等の追加 chord 配列**: JSON が出来次第 assets に放り込むだけで
  既存 ChordKanaRouter で動くはず (新下駄は 2 キー chord 中心の見込み、
  3 キー upgrade 不要)。
- **出力モード切替 UI**: 現状は router 一覧に `(かな出力)` サフィックス付きで
  両モードを並べる暫定 UI。Phase 5 で「配列選択 + 出力モードトグル」 の 2 軸 UI に。
- **switchToEnglish + englishLookupTable**: 薙刀式 の英語モード切替の core。
  KIDE 内部で「現在の router を別 router に切替える」 機構が必要。
- **`KanaToJisKeyTable` の Windows / Chromebook 向け穴埋め** (実機検証次第)。
- **受信側 OS 別 セットアップガイド**: iPad / Mac / Windows / Chromebook で
  「日本語 - かな入力」モードを有効化する手順、Right Alt の話、推奨キーボード等を
  `docs/kide-setup-*.md` 等に整備。

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
