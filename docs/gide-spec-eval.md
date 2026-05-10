# GiDE Spec 実現可能性評価

`GiDE-spec.md`（リポジトリルート）の MVP スペックに対する事前評価メモ。
評価日: 2026-05-10。

このメモは Phase 0 着手前の方針確定を目的とする。決定事項は spec への
反映ではなくここに残し、実装着手時に参照する。

## 総合判定

**実現可能。Phase 1-2 は素直に通る見込み。最大の論点は Phase 3 のローマ字
送出と、Phase 0 着手前の BT 同時 2 役の物理的成立。**

`BluetoothHidDevice` (API 28+) を使った HID Device 役と、GIME の
`GamepadInputManager` の `onDirectInsert(text, replaceCount)` を出口にした
パイプライン流用は、現行 `android/com/gime/android/input/GamepadInputManager.kt`
の構造と完全に整合する。技術選定に致命的な穴はない。

## スペックの強い点

- **GIME 流用境界の明確さ**: `onDirectInsert` 1 点を差し替えるだけで出口を
  切り替えられる設計は、GIME 側の現行 API そのままに乗る。
- **モード絞り込み**: 韓国語 / 中国語 / Devanagari は receiver IME と二重
  合成になるため切り捨てが妥当。ローマ字戦略は日本語と英数のみで成立。
- **US 配列固定 + IME 自動切替なし**: OS 別分岐コードを排除する MVP の
  現実解として優秀。
- **Phase 分けが gating として機能**: 各フェーズが「進む / 撤退」判断点に
  なっている。

## スペックで未カバーの懸念

### A. BT 同時 2 役の物理的成立（最優先）

Android スマホが「ゲームパッド受信（HID Host）」と「HID Device 送信」を
同時に行う構成。現行 GIME Android では BT ゲームパッド単独でも 250ms
debounce やトリガーヒステリシスが必要なほどジッターがあり、HID Device
役を増やすとスタックの帯域・接続数に当たる可能性。

→ **Phase 0.5 spike として独立検証**（合意済み）。詳細は下記 Phase 構成。

### B. `replaceCount > 0` と receiver IME composition の単位不整合

GIME は eager output + rollback で動く。GiDE では rollback を BS 送出で
表現するが、**rollback 単位がレシーバ側 IME の BS 単位と一致するか** が
鍵になる。

実機ベースの仮説検証（iPad の Apple Japanese IME 想定）:

| GIME emit | iPad composition | BS 1 回で消える単位 |
|---|---|---|
| `shi` 3 打 → かな `し` 1 文字 | `し` 1 文字 | `し` 1 文字 ✓ |
| `nn` 2 打 → かな `ん` 1 文字 | `ん` 1 文字 | `ん` 1 文字 ✓ |
| `kya` 3 打 → かな `きゃ` | `き` + 小`ゃ` の 2 文字 | 小`ゃ` のみ ✗ |
| `tta` 3 打 → かな `った` | `っ` + `た` の 2 文字 | `た` のみ ✗ |

**結論**: BS 数を「ローマ字長」ではなく「emit したかな長」で計算すれば
ほぼ整合する。ただし拗音・促音は 1 emit が 2 ひらがなになるので、
`KeystrokeEmitter` 内で「直近 emit ごとのかな長」をスタックに保持し、
`replaceCount=N` を **最後 N emit のかな長合計** ぶんの BS に展開する
必要がある（`replaceCount` × 1 では足りない）。

### C. iPad ライブ変換の自動確定

iPad は composition が一定長を超えるか句読点に遭遇すると、勝手に漢字に
変換して確定済み区間に押し出す。確定済み区間に BS を送ると変動長で
消える（`考えて` を 1 BS で消すと `考え` になる等）ので、ロールバック
の前提が崩れる。

GiDE 側からは確定タイミングを検知できないため、**「ライブ変換が確定を
走らせた後のロールバックは諦める」を仕様として明示** する方針。

### D. `BluetoothHidDevice` のホスト互換性

仕様で言及済み。追加で意識すること:
- Android 12+ の `BLUETOOTH_CONNECT` ランタイム権限と SDP 公開タイミング
- iPad は HID descriptor に比較的厳格（標準 8-byte keyboard report で OK）
- Pixel と Samsung で挙動差の報告あり

### E. 「ん」問題

`nn` 固定で送る方針は妥当。Apple / Google の主要 IME で `nn` → `ん`
確定は安定して動く想定だが、Phase 3 の実機検証で要再確認。

## 決定事項

### 1. リポジトリ展開先

**当 monorepo (`logical-layout-labo`) に `android-gide/` を追加** する。

仕様書では「新規リポジトリ単独」としていたが、Phase 0-2 のセットアップ
コストと feasibility 不確実性を踏まえ、まず monorepo 内に置いて
go/no-go を低コストで判断する。Phase 2 完了時点（HID 互換性 + BT
同時 2 役 + 英数経路の 3 点が揃った時点）で `git filter-repo` 等で
独立リポへ分離する判断を再度行う。

GIME Android（`android/`）と並置することで、流用元コードへの参照や
コピー追従が容易になるという副次効果もある。

### 2. Phase 構成（spec への上書き）

- **Phase 0**: 環境準備（spec 通り）。`android-gide/` 配下に Compose
  アプリ雛形、GIME からのコピー方針確定。
- **Phase 0.5（追加）**: BT 同時 2 役 spike。**実装済み**（`android-gide/`
  の `MainActivity.kt` + `hid/HidKeyboardManager.kt` + `hid/HidConstants.kt`）。
  「ゲームパッド受信中に HID Device 役で 'a' を 1 回送出する」だけを
  検証する。**ここで NG なら GiDE 全体を撤退判断する gate** とする。
  - 必要に応じてゲームパッドの USB OTG 接続を回避策として検討。
  - 検証対象機: 開発者の手元の Android 機（少なくとも 1 機）+ iPad 1 台。
  - **実機検証手順**:
    1. Android 端末に Phase 0.5 spike APK を入れて起動。
    2. 「権限を要求」で `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN` を許可。
    3. 「BT 設定を開く」から iPad と通常の Bluetooth ペアリングを完了
       させておく。iPad 側は「設定 → Bluetooth」で "GiDE Spike" として
       見えればペアリング可能（spike が registerApp 後に SDP 公開する）。
    4. アプリに戻り「Init HID Device」→ Status カードで `registerApp:
       true` を確認。
    5. Paired devices 一覧から iPad を `Select` → 「Connect to selected
       host」→ Status の `connection: CONNECTED` を待つ。
    6. iPad 側でメモアプリ等を開いてテキストフィールドにフォーカス。
    7. 「Send 'a'」を押下。iPad のテキスト欄に `a` が 1 文字入れば送信
       経路 OK。
    8. **同時並行**: ゲームパッドのボタン / スティックを操作。Gamepad
       カードの `last gamepad event` が更新され続けることと、Send 'a'
       が引き続き iPad に届くことを確認。**両方が成立すれば BT 同時
       2 役の物理的成立 = Phase 0.5 gate 通過**。
    9. 失敗パターン: ゲームパッドだけ反応しない / Send 'a' が届かない /
       接続が頻繁に切れる場合は、(a) USB OTG 接続のゲームパッドへの
       切替、(b) 別 Android 機での再検証、(c) iPad iOS バージョン依存の
       追跡 のいずれかを判断する。
- **Phase 1**: HID 送出最小プロトタイプ（spec 通り、ただし Phase 0.5 で
  HID 部分は確認済みの状態で着手）。
- **Phase 2**: 英数モード統合（spec 通り）。
- **Phase 3**: 日本語モード統合（spec 通り、ただし下記の送出戦略で
  実装）。
- **Phase 4**: UX 仕上げ（spec 通り）。

### 3. Phase 3 のローマ字送出戦略

**初期実装は仕様の案 A（eager output）を採用** する。GIME の体験を
維持できる前提を活かし、ローマ字を 1 かな分まとめて送る。

`KeystrokeEmitter` 側で次の状態を保持する:

```
emitHistory: ArrayDeque<EmitRecord>
  EmitRecord = (kanaLength: Int, romajiLength: Int)
```

`onDirectInsert(text, replaceCount)` のハンドリング:

1. `replaceCount > 0` の場合:
   - `emitHistory` の末尾 `replaceCount` 件の `kanaLength` を合計
   - その回数だけ Backspace を送出（拗音・促音で 2 ひらがなになる
     ケースを正しく吸収）
   - `emitHistory` から末尾 `replaceCount` 件を pop
2. `text` を 1 ひらがなずつ走査してローマ字に変換、HID 送出
3. 各ひらがなぶんを `emitHistory` に push

ライブ変換の自動確定後は composition 単位が崩れるので、ロールバックを
諦める旨をビジュアライザに表示することを Phase 4 で検討。

案 B（バッファリング + 確定送出）への切替判断は Phase 3 の iPad 実機
検証で文字化けが許容できないと判断したときに行う。

### 4. 「ん」「促音」「拗音」のローマ字テーブル

spec 通り（`nn` / 子音重ね / `sha kya` 等）。実装時に Apple Japanese
IME の解釈を実機で 1 件ずつ確認する。

## 次のアクション（このメモ後）

1. このメモ（`docs/gide-spec-eval.md`）をコミット → push → draft PR 作成。
2. 後続セッションで **Phase 0.5 spike** から着手するかを再判断。

## 余談: 派生案件アイデア（仮称 KIDE）

GiDE が出口側に作る「Android = HID Device 役で送信」の機構は、入口を
差し替えるだけで化ける。**「USB OTG キーボード → 配列変換 → HID
Device 役で送出」**にすると、Android 端末が **「ポータブルな配列
アダプタ（インストール不要、ホスト OS 非依存）」** になる。

### 位置付け: かえうちの競合 / 上位互換

[かえうち](https://kaeuchi.jp/) はキーボードと PC の間に挟む専用ハード
ウェアで、薙刀式・月配列・親指シフト等の代替日本語配列をホスト OS に
依存せず実現する製品。数千〜万円の専用機で、コンフィグはツール経由で
焼き込む形式。

KIDE 案は同じ問題を Android 端末で解く。比較すると:

| 観点 | かえうち | KIDE 案 |
|---|---|---|
| ハードウェア | 専用機（追加購入） | 手持ちの Android 端末 |
| ホスト互換性 | USB HID（Mac/Win/Linux/iPad） | BT HID（同左 + Quest/visionOS） |
| レイテンシ | マイコン直結、ほぼゼロ | USB OTG → Android → BT HID（実測要） |
| 配列切替 | ハード上のキー or 専用ツール | 手元画面の GUI で即切替 |
| 配列オーサリング | 専用フォーマット | `web/public/keymaps/` の JSON 資産をそのまま流用 |
| ビジュアライザ | なし | 配列図 + レイヤー追従 + 前置シフト表示 |
| 配列共有 | 個人配布 | 配列ハブ Web サイトと連動した PR ベース運用 |
| 持ち出し性 | USB ケーブル必須 | BT で完全ワイヤレス |

レイテンシは負ける（特に薙刀式級の同時打鍵で体感差が出る可能性）が、
**配列ハブ + ビジュアライザ + GUI 配列切替** の体験で差別化できる。
「試打用」「配列開発用」「出張先での即席代替配列」用途では上位互換に
立てる可能性が高い。

### 既存資産との適合度

- `web/public/keymaps/*.json`: プラットフォーム非依存の配列定義群が
  すでに揃っている。追加もハブで回っている。
- `KeyLogicKit/IME/SimultaneousKeyBuffer.swift`: `pressesEnded` ベース
  かつタイマー不要。薙刀式 / NICOLA / 親指シフト等の同時打鍵を実機で
  動かしている実績あり。
- `KeymapDefinition` v1 + `KeymapCodable`: JSON で外部化済み。Android
  側で再パースするだけで全配列を引き継げる。
- `Sources/KanaEditor/UI/KeyboardPanel/KeyboardView.swift`: 配列図
  ビジュアライザ、レイヤー切替、前置シフト追従、ヒートマップを実装済。
  Compose 移植の参考実装。

### 必要になる投資

1. **KeyLogicKit の Kotlin port**: `KeyRouter` + `KeymapDefinition` +
   `KeymapCodable` + `ChordKey` + `SimultaneousKeyBuffer` の 5 ファイル
   相当。値型 + データ駆動設計なので機械的に移植可能。`InputManager`
   （AzooKey 連携、変換エンジン側）は不要 — 出口がローマ字 IME では
   なく HID キーストロークなので、変換層は GIME/GiDE 側にだけ残せばよい。
2. **USB OTG 入力**: Android `InputDevice` で USB HID キーボードを受信。
   BT キーボード入力より jitter が少なく、同時打鍵判定が安定するはず。
3. **配列図ビジュアライザの Compose 移植**: 既存 SwiftUI 版が参照に
   できるが、地味に工数がかかる。MVP では簡易表示で逃げる選択肢もあり。

### Phase 0.5 spike との関係

GiDE Phase 0.5 で検証する「BT 同時 2 役（HID Host 受信 + HID Device
送信）」は、KIDE では「**USB OTG 受信 + BT HID Device 送信**」に置き
換わる。**USB + BT のほうがリソース競合が少ないので GiDE よりむしろ
通りやすい可能性が高い** — GiDE 単体で BT 2 役が NG だった場合でも
KIDE は生き残るシナリオがある。Phase 0.5 spike を組むときに「ついでに
USB OTG + BT HID も最小確認しておく」と将来戦略の幅が広がる。

### 仕様書との整合

`GiDE-spec.md` には以下が明記されている:

> 汎用的な入力中継ツールへの拡張、カスタムキー配列対応、物理キーボード
> 入力ソース、他プラットフォーム移植などは GiDE の範囲外とする。これら
> は MVP の体感を踏まえて別プロジェクトとして判断する。

KIDE は完全にこの「別プロジェクト」枠。GiDE Phase 4 完了後、HID 送出
機構の安定性が体感で確認できた時点で着手判断を行う。GiDE の MVP には
混ぜない。

---

参考:
- `GiDE-spec.md`（リポジトリルート）: 元の MVP スペック
- `docs/gime-android-ime-plan.md`: GIME Android の IME 化作法（HID 化と
  対比して理解しやすい）
- `android/com/gime/android/input/GamepadInputManager.kt`: 流用元の入力
  パイプライン
- かえうち: https://kaeuchi.jp/ （KIDE 案のベンチマーク対象）
