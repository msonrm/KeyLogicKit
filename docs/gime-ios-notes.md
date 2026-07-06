# GIME (iOS) 実装ノート

> CLAUDE.md のプロジェクト概要から移設（2026-07-06）。GIME iOS の機能を追加・変更したらこのファイルを更新すること。

> **【2026-07 撤去】VRChat OSC 連携は削除**し、GIME を純 IME 化した（`Sources/GIME/OSC/`・`UI/VrChatSettingsView.swift` を撤去、`App.swift`・`GamepadVisualizerView.swift` から OSC 配線を除去）。実装は git tag `gime-vrchat-impl-archive`（commit b8379cb）に保存。設計知見は `docs/gime-ios-osc-plan.md`（アーカイブ）を参照。

ゲームパッド日本語入力アプリ（実験的、韓国語・英語・中国語簡体字・中国語繁體字・Devanagari 対応）。KeyLogicKit に依存。GCController でゲームパッド入力を受け取り、KeyRouter をバイパスして InputManager に直接かなを注入する。韓国語は KoreanComposer で2ボル式ハングル合成、英語は T9 レイアウトで IME バイパス。中国語簡体字は PinyinEngine で abbreviated pinyin（简拼）→候補リスト検索、CandidatePopup で選択。中国語繁體字は注音テーブルで abbreviated zhuyin（注音首）→ PinyinEngine で候補検索、繁體字で表示。

- **韓国語 자모 모드**: LT 長押し=Jamo Lock（持続）/ 2連続短押し=Smart Jamo（一時、空白・句読点・削除・カーソル・LS・モード切替で自動解除）。자모 모드中は D-pad / LB / フェイスボタンが互換 Jamo（U+3131..U+3163）の単体出力に切替わり、右スティック → が直前 jamo の連打、↑ が直前子音の 평→격→경 サイクル。

- **LS クリック debounce 250ms** (`lsDebounceInterval`): DualSense 等の機械式スティックボタンの BT 経由チャタリング対策。立ち下がりエッジから 250ms 以内の再発火を無視（Android 版と同じ方針）。

- **Devanagari モード** (Android Phase A9 の iOS 移植、`Sources/GIME/DevanagariComposer.swift` + `GamepadResolver.swift` の Devanagari テーブル群 + `GamepadInputManager.swift` の `handleDevanagariInput()`): `.devanagari` enum case として 6 番目のモードを追加。Sanskrit / Hindi / Marathi / Nepali 等を gamepad 直接打鍵。

- **varnamala 時計回り** 方式（क→च→ट→त→प, क→ख→ग→घ, a→i→u→e を時計回りに配置）。

- **LS 前置シフトラッチ**（左親指で LS と D-pad を同時操作できない物理制約への対応。LS 方向 flick → latch、左手側出力（D-pad 子音 / LB 鼻音）発火で latch 自動消費＝NEUTRAL 復帰、同方向 flick でトグル OFF、別方向で上書き。毎回 `LS方向flick → D-pad押下` の同じリズムでブラインド向き）。

- **L3 one-shot 非 varga サブレイヤー**（य र ल व / श ष स ह）。

- **合成モデル**: ITRANS / Google Hindi IME と同じく conjunct は halant (RT) を明示的に打つ（自動 conjunct はしない）。

- **修飾子**: RT tap=halant ्、RT+LS 方向=カーソル移動、**RT+LS click=改行**（`devaRtUsedForCursor=true` で RT release 時の halant 自動挿入を抑止）、LT+RT=visarga ः、RB 単押し=ओ、LT+RB=nukta ़、LT+A=ऋ、RS ↑=anusvara ं↔chandrabindu ँ、RS →=長母音 post-shift、RS ↓=␣/।/॥ サイクル、RS ←=composer backspace。辞書・追加リソース不要（Unicode 合成のみ）。

- **ビジュアライザは Android 版と統一構造**（`Sources/GIME/GamepadVisualizerView.swift`）: 上段 = `[LT][LB]` / `[RB][RT]`、中段 = `[LS◯] [D-pad] [Face] [RS◯]`、LS/RS は 3×3 グリッドに方向別ラベルを直接表示（カーソル: 細い `↑↓←→` / 特殊アクション: 太い `⇧⇩⇦⇨` / Devanagari LS: varga 代表子音 क/च/ट/त、latch 中はハイライト）。中央プレビューは廃止し、中央セルは LS click 動作（✓/↵/Devanagari の varga 代表子音）を表示。`VizMetrics` struct で iPad (regular) / iPhone (compact) のサイズセットを切替（compact: D-pad 38pt / Face 38pt / Stick 外径 44pt）。

- **VRChat OSC 連携** (Phase B7, `Sources/GIME/OSC/`): 設定で有効化すると、現在のエディタテキスト＋ composing（ひらがな／pinyin／zhuyin）を `/chatbox/input` に debounce 100ms で送信。LS 単押し（idle 時）で `/chatbox/input ... true true` の確定送信 + エディタクリア。デフォルト OFF、明示的有効化までソケット非 open。`Info.plist` に `NSLocalNetworkUsageDescription` を追加し、初回送信時に iOS が Local Network 許可ダイアログを出す。

- **OSC 運用トグル** (`VrChatOscSettings`): `commitOnlyMode`（/chatbox/input 下書き抑制、VRChat Mobile で chatbox UI が開くのを回避）/ `typingIndicatorEnabled`（/chatbox/typing 送信の独立トグル）/ `customTypingEnabled`（composing 開始/終了エッジで任意の avatar parameter に `int` / `float` / `bool` を送る。"考え中ポーズ" 等に活用、VRCEmote=7 プリセット同梱）。
