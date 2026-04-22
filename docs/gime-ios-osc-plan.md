# GIME iOS — VRChat OSC 連携 計画

## 背景

Android 版 GIME で実装・実機検証済みの **VRChat OSC chatbox 連携**
（Phase A7、`docs/gime-vrchat-osc-plan.md` 参照）を iOS GiME にも
移植する計画。

iOS 側に実装することで:
- **iPad + DualSense + Pixel 10 (VRChat Mobile)** という構成で **完全な
  自宅完結テスト環境**が手に入る
  - iPad (4GB) は VRChat 自体は動かないが、iOS GiME は動く
  - Pixel 10 (12GB) は VRChat Mobile が動く
  - DualSense は iPad にペア → 入力衝突なし
- iOS GiME を使う既存ユーザーが、iPhone/iPad から VRChat (PC/Quest/
  Pixel 等) に向けて OSC 送信できる
- App Store 公開時の差別化ポイント

```
[DualSense] ──BT──→ [iPad + iOS GiME (OSC 拡張)] ──UDP/OSC──→ [VRChat 端末]
                                                                  ▲
                                                          (Quest, PC, Pixel 10
                                                           VRChat Mobile 等)
```

## 既存 iOS GiME の状況

`Sources/GIME/`:
- `GamepadInputManager.swift`: 入力パイプライン、コールバック
  `onDirectInsert(text, replaceCount)` で出力先に通知
- `GamepadResolver.swift`: かなテーブル等
- `GamepadVisualizerView.swift`: SwiftUI ビジュアライザ
- `PinyinEngine.swift`, `KoreanComposer.swift`: CJK 対応
- `App.swift`: メインエントリ
- Android 版と**同じコールバック設計**（`onDirectInsert` パターン）なので
  OSC 出力差し替えも同じ手法で実現可能

## Phase 構成

Android 版と同じ段階分け（Phase A7-1 〜 A7-9 と対応）。
工数は Android 版で UX とアルゴリズムが確定しているため大幅短縮。

### Phase B7-1: OSC 送受信基盤（Swift 移植）

ゴール: Swift で OSC 1.0 のエンコード/デコードと UDP 送受信。

- `Sources/GIME/OSC/OscPacket.swift`
  - Android 版 `OscPacket.kt` を Swift に移植
  - サポート型: `s` (String, UTF-8), `i` (Int32), `f` (Float32), `T`/`F`
  - `Data` + `withUnsafeBytes` でバイト操作
  - 4 byte アラインメント、null 終端
- `Sources/GIME/OSC/OscSender.swift`
  - **Network framework** の `NWConnection` を使用（iOS 12+）
  - UDP 送信、送信先 runtime 変更可能
  - メインスレッド非ブロッキング (`async`/`await`)
- `Sources/GIME/OSC/OscReceiver.swift`
  - `NWListener` で UDP 受信（デバッグ用）
- ユニットテスト
  - `Tests/GIMETests/OscPacketTests.swift`
  - encode/decode ラウンドトリップ、Android 版と同じテストケース

```swift
// API イメージ
let sender = OscSender(host: "192.168.1.100", port: 9000)
try await sender.send("/chatbox/input", "こんにちは", true, false)
```

### Phase B7-2: VRChat モード設定 UI

ゴール: ユーザーが OSC を明示的に有効化・送信先設定できる。

- 設定画面（既存の `App.swift` のシート or 新規 `VrChatSettingsView.swift`）
  - VRChat OSC モード トグル（デフォルト OFF）
  - 送信先 IP / Port 入力
  - テスト送信ボタン
  - デバッグ受信ログ表示
- 設定永続化: `UserDefaults` で簡潔に
- 外部 IP 指定時の警告表示
- **`Info.plist` に `NSLocalNetworkUsageDescription` 追加**
  - 「VRChat OSC chatbox にメッセージを送信するためにローカル
    ネットワークアクセスを使用します」
  - 初回 LAN 通信時に iOS が許可ダイアログを表示

### Phase B7-3: 出力ルーティング切替

ゴール: VRChat モード時は IME 出力を OSC 経由でも送信。

- `GamepadInputManager` の `onDirectInsert` コールバックを差し替え
  もしくは追加でフックして OSC 出力
- Android 版と同じ **dual output** パターン
  - 既存の TextField 出力は維持（ローカル表示）
  - VRChat モード ON 時、追加で OSC chatbox に送信
- composing/finalize/delete の状態追跡を IME 側で実装

### Phase B7-4: chatbox UX

ゴール: VRChat 上での見え方を自然にする。

- Android 版と同じセマンティクス
- typing indicator (`/chatbox/typing true/false`)
- 下書き送信 (`/chatbox/input ... false false`)
- 確定送信 (`/chatbox/input ... true true`)
- 累積モデル（複数文節を 1 メッセージで、空状態で LS = 確定）
- **debounce 100ms**（T9 rollback 抑制、Swift `Task.sleep` で実装）
- 144 文字制限の自動トリム

### Phase B7-5: ビジュアライザに「VRChat OSC」バッジ

`GamepadVisualizerView.swift` に SwiftUI でバッジ表示。

### Phase B7-6: プライバシーポリシー & App Store 対応

- 既存 `docs/gime-privacy-policy.md` を更新（または `docs/gime-ios-osc-privacy.md` 新設）
  - OSC セクション追加（opt-in、送信先指定、第三者送信なし）
- `Info.plist`:
  - `NSLocalNetworkUsageDescription` 必須
- App Store Connect:
  - 「データの安全性」で「ユーザーが指定した宛先へのデータ送信」を申告
  - 機能説明に「VRChat OSC 連携（オプション）」追加

### Phase B7-7: ドキュメント

- `docs/gime-ios-osc.md` 新設（iOS 向けセットアップガイド）
  - Android 版 `docs/gime-vrchat-osc.md` をベースに iOS 用にアレンジ
  - iPad + DualSense + Pixel 10 という推奨構成も明記

## iOS 固有の考慮事項

### `NSLocalNetworkUsageDescription`

iOS 14+ では LAN への通信に明示的なユーザー許可が必要:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>VRChat の chatbox に文字メッセージを送信するため、同一 Wi-Fi 内の
他デバイスへの通信を使用します。送信先はあなたが設定した IP アドレスのみです。</string>
```

初回送信時に iOS のシステムダイアログで許可を求められる。
ユーザーが拒否すると OSC 機能は使えない（再有効化は iOS 設定 → アプリ
で実施可能）。

### Network framework

- iOS 12+ で利用可能、推奨
- 古い `CFSocket` / `BSD Socket` ではなく `NWConnection` を使う
- バックグラウンドでの通信は別途扱い必要（IME 化計画でも触れない、
  通常使用は前面想定）

### IME (Custom Keyboard) としての通信

- iOS のカスタムキーボードは **`RequestsOpenAccess = YES`** が無いと
  ネットワーク通信不可
- ユーザーは設定でフルアクセスを許可する必要あり（心理的ハードル高め）
- App Store 審査でフルアクセスの正当性を説明する必要あり
- 既存の iOS GiME は IME ではなく単独アプリなので、このセッション
  範囲内では問題なし。将来 iOS IME 化するときに別途検討

### 既存 iOS GiME のエコシステム

- 単独アプリ（IME ではない）として動作
- アプリ内で打って `SendTextIntent`（App Intent / ショートカット連携）
  で他アプリに送る、という流れ
- OSC 連携を加えるとさらに強力に「アプリ内入力 → OSC で外部へ」が可能

## テスト戦略

Android 版 Phase A7 で確立した戦略を踏襲:

| Level | 内容 | 環境 |
|---|---|---|
| L1 | OSC encode/decode ユニットテスト | XCTest, CI 自動 |
| L2 | iPad 単独 loopback (送信+受信) | iPad アプリ内 |
| L3 | iPad → 別端末 (Protokol 等) | iPad + Mac/Pixel 10 |
| L4 | iPad → Pixel 10 VRChat Mobile | iPad + Pixel 10 (✅ 自宅完結) |

L4 が **Android 版で実現できなかった本番動作確認**を、iOS 版実装後に
自宅で達成可能になる。これがこの計画の最大価値。

## 工数見積もり

Android 版で UX・アルゴリズムが固まっているため、純粋に Swift 移植:

| Phase | 想定 |
|---|---|
| B7-1 OSC 基盤 | 0.5 日（テスト含む）|
| B7-2 設定 UI | 0.5 日 |
| B7-3 出力ルーティング | 0.3 日 |
| B7-4 chatbox UX | 0.3 日 |
| B7-5 バッジ | 0.1 日 |
| B7-6 プライバシー対応 | 0.2 日 |
| B7-7 ドキュメント | 0.2 日 |
| 実機検証 (L1〜L4) | 0.5 日 |
| **合計** | **約 2.5 日** |

Android 版の 1〜2 週間に比べて大幅短縮。Android 版で集めた知見を
そのまま使えるため。

## 不変条件

Android 版と同じ:
- engine 層 (Gamepad*, KoreanComposer, PinyinEngine) は触らない
- `GamepadInputManager` のコールバック差し替えだけで OSC 連携を実現
- デフォルト全 OFF、ユーザーが明示的に有効化するまで通信しない
- 送信先は localhost / ユーザー指定 IP のみ、第三者サーバーへの送信なし

## 関連ドキュメント

- `docs/gime-vrchat-osc-plan.md` — Android 版計画書（同じ仕様）
- `docs/gime-vrchat-osc.md` — VRChat OSC ユーザーガイド（Android 視点、
  iOS 用には別途 `docs/gime-ios-osc.md` 新設）
- `docs/gime-android-privacy-policy.md` — Android 版プライバシーポリシー
- `docs/gime-privacy-policy.md` — iOS 既存プライバシーポリシー（要更新）
- Android 版実装:
  - `android/app/src/main/java/com/gime/android/osc/` — OSC パケット・
    送受信・chatbox ラッパー（Swift 移植のリファレンス）
  - `android/app/src/main/java/com/gime/android/ime/GimeInputMethodService.kt`
    — dual output 配線（コールバック差し替えの参考）

## TODO

本計画はリファレンスとして残す。主要項目は実装済み。

- [x] B7-1: OSC 送受信基盤 (Swift) — `Sources/GIME/OSC/` に実装
- [x] B7-2: VRChat モード設定 UI (SwiftUI) — `Sources/GIME/UI/VrChatSettingsView.swift`
- [x] B7-3: 出力ルーティング切替 — `App.swift` の `refreshVrChatOutput()` / `sendVrChatDraftIfNeeded()`
- [x] B7-4: chatbox UX (debounce / 累積モデル) — 実装済み
- [x] B7-5: ビジュアライザに OSC バッジ — `GamepadVisualizerView.swift`
- [x] B7-6: プライバシーポリシー / Info.plist 対応 — `NSLocalNetworkUsageDescription` 追加
- [x] B7-7: ドキュメント / セットアップガイド — `docs/gime-vrchat-osc.md`
- [x] iPad + Android VRChat Mobile での L4 実機検証 — **動作確認済み**（iPad GIME →
      Android USB テザリング → VRChat Mobile へのチャットテキスト送信成功）

## 後続の拡張（Android 版と共通）

基本計画の完了後に追加した運用オプション（Android 版とセットで実装）:

- **`commitOnlyMode`** (PR #498): VRChat Mobile が下書き受信で chatbox 入力 UI を
  自動展開してしまう問題の回避策。ON で composing 中の `/chatbox/input` を抑制し、
  LS 確定時のみ `sendMessage=true` で送信
- **`typingIndicatorEnabled`** (PR #498): `/chatbox/typing` 送信の独立トグル。
  `commitOnlyMode` とは独立
- **`customTypingEnabled`** (PR #499 iOS / PR #500 Android): 入力中アクション。
  composing 開始/終了エッジで任意の avatar parameter を `int` / `float` / `bool`
  で送信できる汎用機構。無言勢の「typing 中に棒立ち」問題への対応策として、
  "考え中ポーズ" 等のアニメーションを叩くのに使う。VRCEmote=7 プリセット同梱。
  詳細仕様は `docs/gime-vrchat-osc-plan.md` の "拡張: 入力中アクション" セクション
