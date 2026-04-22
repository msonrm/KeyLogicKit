# GIME Android — VRChat OSC 連携 計画

## 背景

GIME は CJK + 英語 をゲームパッドだけで打てる Android IME。
VRChat (とくに Quest 単独 VR) では「ヘッドセット外さず日本語/韓国語/
中国語を打ちたい」というニーズに対する既存解が貧弱で、ここに
GIME を OSC 連携で接続すれば「VR 没入したまま CJK でチャット」
という体験が実現できる。

詳細経緯と UX 設計の議論は会話ログ参照。

## ターゲットユーザー

| 優先度 | 層 | 価値 |
|---|---|---|
| 最高 | Quest 単独 VR + 日/韓/中ユーザー | 既存代替手段ほぼ皆無 |
| 高 | PC VRChat HMD 装着派 | HMD 外す回数が劇的に減る |
| 中 | マルチリンガル混在環境ユーザー | 1 ツールで JP/KR/ZH/EN 切替 |
| 中 | ゲームパッド愛好家 (英語含む) | 入力をパッドに統一できる |

## 技術構成

```
[BT Gamepad] ─→ [Phone/Tablet (Android + GIME)] ─UDP/OSC─→ [Quest/PC + VRChat]
                                                                   ▲
[Quest Touch Controllers] ─OpenXR─────────────────────────────────┘
```

- スマホ + GIME は **VRChat とは別デバイス** に物理的に分離
- 同一 LAN で UDP 到達できればよい
- 入力衝突なし、アバター動作と並行して文字入力可能
- VRChat Mobile (同一端末で全部) はターゲット外

## Phase 構成

### Phase A7-1: OSC 送信基盤 [必須]

ゴール: UDP で OSC パケットを送信できる最小実装。

- `com.gime.android.osc.OscSender` を新設
  - DatagramSocket / DatagramPacket をラップ
  - 送信先 IP:port を保持
  - 非同期送信 (Dispatchers.IO + serviceScope)
- `com.gime.android.osc.OscPacket` を新設（外部依存なし）
  - OSC 1.0 spec の最小サブセットを自前実装（~100行程度）
  - サポート型: `s` (string), `i` (int32), `f` (float32), `T`/`F` (true/false bool)
  - 4 byte アラインメント / null 終端 / type tag string をエンコード
- 単体テスト（JVM テスト）: パケットバイナリ列の検証

**API イメージ:**
```kotlin
class OscSender(host: String, port: Int) {
    suspend fun send(address: String, vararg args: Any)
    fun close()
}

OscSender("127.0.0.1", 9000).send("/chatbox/input", "こんにちは", true, false)
```

### Phase A7-2: VRChat モード設定 UI [必須]

ゴール: ユーザーが OSC を明示的に有効化・送信先設定できる。

- `MainActivity` に「VRChat 連携」セクション追加
  - トグル: VRChat OSC モード (デフォルト OFF)
  - テキストフィールド: 送信先 IP (デフォルト `127.0.0.1`)
  - テキストフィールド: 送信先 Port (デフォルト `9000`)
  - インジケータ: 現在の送信先・接続状態
- 設定永続化: `SharedPreferences` または `DataStore`
- IME 側ビジュアライザにも **VRChat モード ON 時はバッジ表示**
- 送信先が `127.0.0.1` 以外（外部IP）のときは **警告アイコン** を表示

### Phase A7-3: 出力ルーティング切替 [必須]

ゴール: VRChat モード時は IME 出力を InputConnection ではなく OSC へ向ける。

- `GimeInputMethodService.wireCallbacks()` を拡張
- VRChat モード時の挙動:
  - `onDirectInsert(text, replaceCount)` → OSC chatbox に下書き送信
    （`/chatbox/input "..." false false`）
  - `onFinalizeComposing()` → 確定送信
    （`/chatbox/input "..." true true`）
- 出力先設定は `GimeInputMethodService` が `OscSender` インスタンスを保持
- 既存の InputConnection 出力は VRChat モード OFF 時のみ動作（排他）
- composing バッファをそのまま OSC に投げると `replaceCount` 系のデルタ更新は
  意味をなさないので、IME 側で「今 composing 中の全文」を組み立てて送る
  （これは Phase A6-5 の `imeComposingText` 追跡を流用）

### Phase A7-4: chatbox UX [必須]

ゴール: VRChat 上で **タイピング中の見え方** を自然にする。

- composing 開始時: `/chatbox/typing true` → 自アバター頭上の「...」表示
- composing 更新時: `/chatbox/input "ここまで打った文字" false false`
  → 他プレイヤーから下書きが見える
- 確定時: `/chatbox/input "確定文字列" true true` → 通知音 + 確定表示
- composing 終了時: `/chatbox/typing false`
- **144 文字制限** の処理:
  - 制限を超えそうになったら IME ビジュアライザに警告表示
  - 自動切断はしない（ユーザーが分割して打つ）
- **debounce / rate limit**:
  - composing 更新は 100ms 以上の間隔を空けてバースト送信を回避
  - VRChat 側の OSC 受信レート上限に配慮

### Phase A7-5: アバター入力のゼロ送信 [オプション]

ゴール: VRChat モード中、誤ってゲームパッド入力で **アバターが動かない** ようにする。

- 設定: 「typing 中アバター固定」トグル（デフォルト OFF）
- VRChat モード ON 中、定期的に以下を送信:
  - `/input/Vertical 0`
  - `/input/Horizontal 0`
  - `/input/LookHorizontal 0`
  - `/input/LookVertical 0`
- 注意: 同じゲームパッドが Quest にもペアされている前提のときのみ意味あり
- 2 デバイス分離構成では不要なので **オプションで OFF**

### Phase A7-6: IsTyping アバターパラメータ [オプション]

ゴール: 対応アバターでタイピングポーズ等を発火。

- 設定: 「IsTyping パラメータ送信」トグル（デフォルト OFF）
- composing 開始: `/avatar/parameters/IsTyping true`
- composing 終了: `/avatar/parameters/IsTyping false`
- パラメータ名はカスタマイズ可能にする（アバター仕様によって違うため）
- ドキュメントに **VRC SDK での IsTyping パラメータ実装方法** を記載
  （bool param + animator state + animation clip）

### Phase A7-7: Viseme リップシンク [オプション・キラー機能]

ゴール: タイピングする母音に応じて口パク。

- 設定: 「母音 Viseme 連動」トグル（デフォルト OFF）
- フェイスボタン押下時、対応する Viseme 値を送信:
  - X (い段) → `/avatar/parameters/Viseme 12`
  - Y (う段) → `Viseme 14`
  - A (あ段) → `Viseme 10`
  - B (え段) → `Viseme 11`
  - その他 (お段) → `Viseme 13`
- スムーズ補間オプション:
  - 即時 ON / 100ms hold / 50ms fade-out → デフォルト
  - スムーズな fade in/out 用に直近の値も追跡
- 韓国語の母音 (ㅏㅓㅗㅜㅡㅣㅐㅔ) も同様にマッピング
- 中国語は声調があるので Viseme は単音節母音のみ対応
- 注意: VRChat の音声 lipsync と競合する可能性 → ユーザーがマイクミュート推奨

### Phase A7-8: プライバシーポリシー & Play Store 対応 [必須]

ゴール: 審査を通すための情報整備。

- `docs/gime-privacy-policy.md` に OSC セクション追加:
  - 送信内容（ユーザーが入力した文字列のみ）
  - 送信先（ユーザーが設定した IP:port のみ）
  - 送信タイミング（VRChat モード ON + ユーザーがゲームパッドで入力時のみ）
  - 第三者へのデータ送信なし
  - ローカルネットワーク外への送信は明示的設定を要求
- AndroidManifest に `INTERNET` permission 追加
  - `<uses-permission android:name="android.permission.INTERNET" />`
- Play Console データ安全性セクション更新:
  - 「個人情報を送信」の対象として OSC 機能を申告
- アプリ説明文に「VRChat OSC 連携（オプトイン機能）」を明記

### Phase A7-9: ドキュメント & セットアップガイド [必須]

ゴール: ユーザーが迷わずセットアップできる。

- `docs/gime-vrchat-osc.md` を新設:
  - VRChat 側の OSC 有効化手順
  - 推奨トポロジー（2 デバイス分離）の図解
  - GIME 側の設定手順
  - トラブルシュート（「文字が出ない」「動かない」等）
- README にも VRChat 連携機能の存在を記載
- 任意: VRC SDK 用「IsTyping 対応サンプルアバター」リポジトリ

## 不変条件

- **engine/ 層は pure Kotlin・Android 非依存** を維持
  - OSC 関連は `osc/` パッケージに分離
- **`GamepadInputManager` は出力先を知らない** 設計を維持
  - OSC 連携は `GimeInputMethodService` 内のコールバック差し替えで実現
- **デフォルトは全機能 OFF**
  - ユーザーが明示的に有効化するまで通信しない
  - INTERNET permission を要求するが実際にソケットを開かない

## 段階的リリース戦略

| Step | 範囲 | リリース判断 |
|---|---|---|
| MVP | A7-1 〜 A7-4, A7-8 | chatbox に文字が飛ぶ最小構成。即リリース |
| Plus | + A7-5, A7-9 | 入力衝突対策とドキュメント完備 |
| Full | + A7-6, A7-7 | アバター連動 / Viseme で独自性発揮 |

各 Step ごとにバージョン番号を上げて TestFlight / Internal testing で
反応を見る。Viseme は VRChat ガチ勢の評価が肝なので、コミュニティ
（VRC 日本人 Discord 等）への提示が重要。

## リスクと対応

| リスク | 可能性 | 対応 |
|---|---|---|
| Play Store 審査拒否 | 低 | プライバシー透明性を徹底、デフォルト OFF |
| OSC パケット受信されない | 中 | LAN 設定、ファイアウォール、IP 入力ミス → ドキュメントとUI バリデーション |
| Viseme が他のアバターと競合 | 中 | オプション機能、ユーザーが必要時のみ ON |
| 144 文字制限超過 | 高 | UI 警告、ユーザーが分割 |
| OSC 受信側の負荷 (大量送信) | 中 | debounce / rate limit |
| 2 デバイス構成のセットアップ難易度 | 高 | ステップバイステップ ガイド作成 |

## 参考資料

- VRChat OSC 公式: https://docs.vrchat.com/docs/osc-overview
- OSC chatbox 仕様: https://docs.vrchat.com/docs/osc-as-input-controller
- Avatar parameters: https://docs.vrchat.com/docs/osc-avatar-parameters
- OSC 1.0 spec: https://opensoundcontrol.stanford.edu/spec-1_0.html

## 関連 TODO

- [x] A7-1: OSC 送信基盤 (OscSender + OscPacket) — 実装済み（`com/gime/android/osc/`）
- [x] A7-2: VRChat モード設定 UI — `ui/VrChatScreen.kt`
- [x] A7-3: 出力ルーティング切替 — IME + バブル dual output
- [x] A7-4: chatbox UX (typing indicator + preview + commit) — 実装済み
- [x] A7-5: アバター入力ゼロ送信 (オプション) — `commitOnlyMode` として実装
- [x] A7-6: IsTyping アバターパラメータ (オプション) — **汎用化して `customTypingEnabled` として実装**（IsTyping 固定ではなく任意の address + int/float/bool を送れる形に発展。PR #500）
- [ ] A7-7: Viseme リップシンク (オプション) — **未実装・方向転換**（VRChat 側の Viseme param は OSC 書き込み不可、TTS 仮想マイク経路が前提になる。詳細は会話履歴・`docs/gime-vrchat-osc.md` の "入力中アバターを「考え中ポーズ」にしたい" セクション参照）
- [x] A7-8: プライバシーポリシー & Play Store 対応
- [x] A7-9: ドキュメント & セットアップガイド — `docs/gime-vrchat-osc.md`

### 拡張: 入力中アクション (customTyping)

A7-6 の IsTyping 特化設計を汎用化し、composing 開始/終了エッジで
任意の avatar parameter を叩ける仕組みに発展させた:

- `VrChatOscSettings.customTyping{Enabled,Address,ValueType,StartValue,EndValue}`
  を `SharedPreferences` で永続化
- `VrChatOscOutput.typingStartMessage` / `typingEndMessage`（`Pair<String, Any>?`）
  を `typingActive` の edge 遷移で送信
- `sendTypingIndicator` / `commitOnlyMode` とは独立して動作
- IME (`GimeInputMethodService`) とバブル (`BubbleService`) の両方で有効
- UI: `ui/VrChatScreen.kt` に「入力中アクション」セクション + VRCEmote=7 プリセット

iOS 版は PR #498 / #499 で先行実装、Android 版は PR #500。
