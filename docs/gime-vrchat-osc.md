# GIME × VRChat OSC セットアップガイド

ゲームパッドで GIME を使って、ヘッドセット外さずに VRChat の chatbox に
日本語/韓国語/中国語/英語を入力する方法。

## 全体像

```
[BT ゲームパッド] ──BT──→ [スマホ + GIME] ──UDP/OSC──→ [Quest / PC + VRChat]
                                                              ▲
[Quest Touch Controllers] ─OpenXR─────────────────────────────┘
```

- GIME は **スマホやタブレット** 側で動く Android IME
- VRChat 本体（Quest / PC / Mobile）とは LAN 越しに OSC で繋がる
- 入力デバイスを物理的に分けることで、アバター操作と文字入力が衝突しない

## 必要なもの

| 役割 | 候補 |
|---|---|
| **入力端末** | GIME を入れた Android スマホ or タブレット |
| **入力デバイス** | Bluetooth ゲームパッド (DualSense / Xbox / 8BitDo 等) |
| **VRChat 端末** | Quest 単独 / PC VRChat / VRChat Mobile (4GB+ RAM 推奨) |
| **ネットワーク** | 同一 Wi-Fi (ゲスト Wi-Fi の Client Isolation は不可) |

## セットアップ手順

### 1. VRChat 側の OSC 有効化

Quest / PC VRChat:

1. ランチパッドメニューを開く
2. Options → OSC → "Enabled" を ON
3. （PC 版なら Send Port = 9000、Receive Port = 9001 がデフォルト）

VRChat Mobile:

1. メニュー → 設定 → OSC
2. 受信ポート（通常 9000）を確認・有効化
3. ※ iPad Gen10 等 4GB 未満の端末はメモリ不足でワールドに入れない場合あり

### 2. 端末の IP アドレス確認

VRChat を動かしている端末（Quest / PC / iPad）の IP を確認:

- **Quest**: 設定 → Wi-Fi → 接続中ネットワーク → 詳細
- **PC (Win)**: コマンドプロンプトで `ipconfig` → Wi-Fi の IPv4
- **PC (macOS)**: システム設定 → ネットワーク → Wi-Fi → 詳細
- **iPad**: 設定 → Wi-Fi → 接続中ネットワーク横の i マーク

例: `192.168.1.123`

### 3. GIME 側の設定

1. GIME アプリを起動
2. ヘッダーの「VRChat」ボタン
3. 「VRChat OSC モード」を **ON**
4. 送信先 IP に手順 2 で確認した IP を入力
5. ポートは `9000`（VRChat デフォルト）

### 4. GIME を IME として有効化

1. GIME アプリのヘッダーから「IME設定」→ システム設定で GIME を ON
2. 「IME切替」→ GIME を選択

### 5. ゲームパッドペアリング

スマホの Bluetooth 設定で、ゲームパッドをペアリング。
ペアリング先は **VRChat の端末ではなく、GIME のスマホ** に注意。

## 使い方

### 基本フロー

1. 任意のテキスト欄にフォーカス（GIME アプリの編集欄が便利、または
   メモアプリ等）
2. ゲームパッドで日本語入力（既存の GIME と同じ操作）
3. 入力中、VRChat 側のアバター頭上に **「...」typing indicator** + **下書きテキスト**
   が表示される
4. 入力途中で何度 LS（左スティッククリック）を押しても、下書きが
   chatbox に蓄積される（複数文節の確定が可能）
5. 入力欄が空になっている状態で **もう一度 LS を押すと送信**
   - chatbox に確定メッセージとして表示（通知音付き）
6. typing indicator は自動で OFF

### 例

```
1. ゲームパッドで「きょうは」と入力 → 変換「今日は」
   → VRChat 上の自分の頭上に「今日は」（下書き、… マーク付き）
2. LS 押下で確定 → 累積に「今日は」追加
3. 「げんき」と入力 → 変換「元気」
   → VRChat 上「今日は元気」（下書き）
4. 「？」を入力 → 累積「今日は元気？」
5. 何も composing 中でない状態で LS 押下
   → /chatbox/input "今日は元気？" true true
   → VRChat 上に通知音つきで確定送信、誰でも見える
```

## トラブルシュート

### chatbox に何も出ない

1. **GIME 設定で「自受信へ送信 (loopback)」ボタン** を押す → ログに出れば
   GIME の OSC 送信機能は動作している
2. **iPad などに OSC モニタアプリ（Protokol 等）** を入れて、GIME の
   送信先をその端末の IP にして送信 → 受信できるかネットワーク到達性確認
3. 受信できているのに VRChat に出ない場合:
   - VRChat 側 OSC 設定が ON か再確認
   - VRChat のワールドが OSC を許可しているか（一部ワールドで制限あり）
   - VRChat が同一 Wi-Fi に繋がっているか
4. 同じ Wi-Fi なのに届かない場合:
   - ルーターの "Client Isolation" / "AP Isolation" 設定を確認
   - ゲスト Wi-Fi は通信遮断されることが多い

### 日本語が変な文字列で送られる

- T9 英語モードの rollback が一瞬流れる場合あり（debounce 100ms で
  対策済みだが完全には消えない）
- LS で確定すれば最終的な変換結果が確定送信される

### Quest 単独で GIME を直接動かしたい

技術的には Quest に sideload できるが、入力競合（同じゲームパッドが
VRChat の avatar 操作と GIME の文字入力で取り合う）が発生するため
推奨しない。**スマホ + ゲームパッド分離構成** が安定。

## 動作確認済みの構成

| 端末 A (GIME 側) | 端末 B (VRChat 側) | 状態 |
|---|---|---|
| Pixel 10 + DualSense | (Protokol 受信のみ、VRChat 未起動) | ✅ パケット到達確認 |
| Pixel 10 + DualSense | iPad VRChat Mobile | iPad メモリ不足で未検証 |
| Pixel 10 + DualSense | PC VRChat (Steam) | 未検証 |
| Pixel 10 + DualSense | Quest 3 / Quest 2 単独 | 未検証 |

実機動作報告募集中（GitHub Issues 等で）。

## 仕様詳細

- 送信プロトコル: OSC 1.0 (UDP)
- 送信アドレス:
  - `/chatbox/typing <bool>` — typing indicator の on/off
  - `/chatbox/input <string> <bool sendImmediately> <bool playSound>` —
    chatbox メッセージ
- 文字数制限: 144 文字（VRChat 仕様、超過分は自動でトリム）
- debounce: 下書き送信は 100ms 間引き

## プライバシー

OSC 送信先はユーザーが設定した IP:port のみ。第三者サーバーへのデータ
送信は一切ありません。詳細は [プライバシーポリシー](gime-android-privacy-policy.md)
参照。
