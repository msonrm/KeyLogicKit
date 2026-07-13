# リポジトリ構成マップ

> CLAUDE.md のアーキテクチャ節から移設（2026-07-06）。ファイル追加・移動時はこのツリーも更新すること（ベストエフォート）。

```
Sources/KeyLogicKit/               # ライブラリターゲット（OSS 公開用）
├── Editor/
│   ├── EditorStyle.swift              # エディタ表示スタイル（フォント・行間・文末揃え）
│   ├── IMETextView.swift              # UITextView サブクラス（キー入力横取り + アクション実行）
│   └── IMETextViewRepresentable.swift # SwiftUI ラッパー（InputManager + KeyRouter 注入）
├── IME/
│   ├── InputManager.swift             # 変換管理（AzooKey 辞書変換 + Zenzai DI 対応）
│   ├── KeyAction.swift                # IME アクション enum（全入力方式共通）
│   ├── KeymapDefinition.swift         # キーマップ定義データ構造（v1 メタデータ付き）
│   ├── KeymapCodable.swift            # KeymapDefinition の JSON エンコード/デコード
│   ├── KeymapStore.swift              # キーマップ JSON ファイルの読み書き
│   ├── KeymapManager.swift            # キーマップ選択・永続化（@Observable）
│   ├── KeyRouter.swift                # 汎用キールーター（データ駆動）
│   ├── KeyEvent.swift                 # プラットフォーム非依存キーイベント（HIDKeyCode, KeyModifierFlags）
│   ├── DynamicShortcut.swift          # 動的ショートカット（日時挿入等のリアルタイム展開）
│   ├── DefaultKeymaps.swift           # 組み込みキーマップ定義（ローマ字US/JIS 等）
│   ├── ChordKey.swift                 # 同時打鍵キー識別子（QWERTY 30+親指 3 キー、hand/finger/keyRow 属性付き）
│   ├── SimultaneousKeyBuffer.swift    # 同時打鍵バッファ（pressesEnded ベース、タイマー不要）
│   ├── SentenceBoundary.swift         # 日本語文境界検出（文・句・カッコ、UIKit 非依存）
│   └── SmartSelectionState.swift      # スマート選択状態管理（段階的拡大・縮小）
├── UI/
│   ├── CandidatePopup.swift           # 変換候補ポップアップ（macOS IME 風、動的幅調整）
│   └── PredictionPopup.swift          # 予測候補ポップアップ（composing 中にカーソル直下に表示）
└── Resources/
    └── Keymaps/                       # 組み込みキーマップ JSON（Bundle.module でアクセス）
        ├── azik_us.json
        ├── azik_jis.json
        ├── nicola_us.json
        ├── nicola_jis.json
        ├── romaji_colemak_us.json
        ├── romaji_colemak_jis.json
        ├── tsuki2-263_us.json
        └── tsuki2-263_jis.json

Sources/KanaEditor/                    # アプリターゲット（プライベート）
├── App.swift                          # @main
├── ContentView.swift                  # メイン画面（デバッグパネル付き）
└── UI/
    ├── AboutView.swift                # アプリ情報シート（バージョン・著作権・OSSライセンス）
    ├── ConversionStatePanel.swift     # 変換状態パネル（変換テキスト・候補表示、キーログは無効化済み）
    ├── EditorToolbar.swift            # ツールバー（入力モードバッジ・状態バッジ・パネル切替）
    ├── KeymapSettingsView.swift       # キーマップ管理シート（選択・インポート・削除）
    ├── SettingsAndInfoPanelView.swift # 設定+配列情報パネル（サイドパネル設定タブ）
    └── KeyboardPanel/
        ├── KeyboardPanelView.swift    # キーボードパネル（タブ切替: 文字一覧/設定、統計タブは無効化済み）
        ├── KeyboardView.swift         # キーボード配列の可視化（ヒートマップ、レイヤー表示、前置キーインジケータ）
        ├── KeyboardVisualizerState.swift # キーボード可視化の状態管理（レイヤー・前置シフト自動追従、打鍵記録・統計は無効化済み）
        ├── GojuonChartView.swift      # 文字一覧（かな→キー逆引き表示）
        ├── KanaToKeyResolver.swift    # かな→キー逆引きリゾルバ
        ├── KeystrokeRecord.swift      # 打鍵記録データ構造
        ├── LayoutFeaturesView.swift   # 配列特徴表示
        └── TypingStatsView.swift      # 打鍵統計（指別・段別・左右バランス・交互打鍵率）

Sources/GIME/                              # ゲームパッド日本語入力アプリ（実験的、韓国語・英語・中国語対応）
├── App.swift                              # @main（IMETextView + GamepadVisualizer + Zenzai トグル + 共有シート）
├── GamepadResolver.swift                  # かなテーブル・英語T9テーブル・注音テーブル・韓国語子音テーブル・アクション enum
├── GamepadInputManager.swift              # GCController → GamepadSnapshot パイプライン（5モード対応）
├── KoreanComposer.swift                   # ハングル音節合成エンジン（2ボル式、겹받침対応）
├── PinyinEngine.swift                     # CJK 候補検索エンジン（簡体: CC-CEDICT + OpenSubtitles、繁体: libchewing）
├── GamepadVisualizerView.swift            # SwiftUI ビジュアライザ（動的レイヤー切替、モード別表示、英語/注音十字配置）
├── ZenzaiModelManager.swift               # Zenzai モデルの自動ダウンロード・管理（@Observable）
└── SendTextIntent.swift                   # App Intent（テキスト取得、ショートカットアプリ連携）
# 注: VRChat OSC 連携（OSC/・VrChatSettingsView）は 2026-07 撤去。tag gime-vrchat-impl-archive 参照

android/                                   # GIME Android 移植版（Kotlin + Jetpack Compose）
├── app/src/main/java/
│   ├── com/gime/android/                       # アプリ本体
│   │   ├── MainActivity.kt                     # Activity + KeyEvent/MotionEvent 横取り、
│   │   │                                       # JapaneseConverter を lifecycleScope で非同期初期化
│   │   ├── engine/
│   │   │   ├── GamepadResolver.kt              # かなテーブル・英語T9・注音・韓国語テーブル
│   │   │   ├── KoreanComposer.kt               # ハングル音節合成エンジン（겹받침対応）
│   │   │   ├── PinyinEngine.kt                 # CJK 候補検索（JSON 辞書、variant 自動切替）
│   │   │   └── JapaneseConverter.kt            # KazumaProject エンジンのファサード。
│   │   │                                       # convertBunsetsu() で文節分割した候補を返す
│   │   ├── input/
│   │   │   ├── GamepadSnapshot.kt              # KeyEvent/MotionEvent → 状態
│   │   │   └── GamepadInputManager.kt          # 入力パイプライン、文節編集状態、韓国語 합성
│   │   ├── ime/                                # システム IME 化 (Phase A6)
│   │   │   ├── GimeInputMethodService.kt       # InputMethodService サブクラス。
│   │   │   │                                   # LifecycleOwner / ViewModelStoreOwner /
│   │   │   │                                   # SavedStateRegistryOwner 自前実装、
│   │   │   │                                   # window.decorView に owner 設定で
│   │   │   │                                   # ComposeView ホスティング可能に。
│   │   │   │                                   # InputConnection 出力
│   │   │   └── GimeInputView.kt                # ComposeView をホストする FrameLayout
│   │   │   # 注: osc/・translate/・bubble/（VRChat 連携）は 2026-07 撤去。
│   │   │   #     tag gime-vrchat-impl-archive 参照
│   │   ├── learn/
│   │   │   └── GimeDatabase.kt                 # Room DB（learn + user_word）と DatabaseProvider
│   │   └── ui/
│   │       ├── GimeApp.kt                      # Compose UI（Scaffold + TopAppBar +
│   │       │                                   # エディタ + ビジュアライザ）
│   │       ├── GimeTheme.kt                    # Material You テーマ（Android 12+ で
│   │       │                                   # dynamicColorScheme、ダーク/ライト追従）
│   │       └── DictionaryScreen.kt             # ユーザー辞書エディタ + 学習履歴リセット
│   └── com/kazumaproject/                      # ★ vendored: KazumaProject/JapaneseKeyboard (MIT)
│       ├── markdownhelperkeyboard/converter/   # 変換エンジン本体（LOUDS + N-gram）
│       │   ├── engine/KanaKanjiEngine.kt       # メイン API。getCandidatesWithoutPrediction 等
│       │   ├── engine/EnglishEngine.kt         # 英語変換（サブ）
│       │   ├── louds/, bitset/, graph/,        # LOUDS trie, SuccinctBitVector, ラティス
│       │   ├── path_algorithm/                 # FindPath + NgramRuleScorer
│       │   ├── dictionary/, connection_id/     # 辞書・連接コストの読込
│       │   └── candidate/                      # Candidate 等データ型
│       ├── markdownhelperkeyboard/repository/  # LearnRepository / UserDictionaryRepository
│       │                                       # Room 実装（Entity + DAO 同居、DB は com/gime/android/learn/）
│       ├── markdownhelperkeyboard/ime_service/extensions/  # 数字変換等の補助拡張
│       ├── markdownhelperkeyboard/user_dictionary/PosMapper.kt
│       ├── core/domain/extensions/             # String/Char 拡張
│       └── data/, domain/                      # 絵文字・シンボル分類
├── app/src/main/assets/                    # 辞書 ~15MB（vendor 同梱）
│   ├── system/ (tango/yomi/token.dat.zip)      # メインシステム辞書
│   ├── single_kanji/, emoji/, emoticon/,       # 候補源の各種辞書
│   │   symbol/, reading_correction/, kotowaza/, english/
│   ├── connectionId.dat.zip                    # 1316×1316 連接コスト
│   ├── pos_table.dat, id.def                   # 品詞テーブル
│   └── pinyin_abbrev.json, zhuyin_abbrev.json  # 中国語用（res/raw にも配置）
├── app/build.gradle.kts                   # AGP 8.7.3, minSdk 28, targetSdk 35, Timber 5.0.1
├── gradle/wrapper/gradle-wrapper.properties  # Gradle 8.11.1
└── settings.gradle.kts

scripts/jp-dict-gen/                       # Phase A2.2 で使った辞書生成ツール（standalone JVM、
                                           # Phase A2.3 以降 KazumaProject vendor に切替えたため
                                           # 現在は参照されないが、履歴上は残っていない）

.github/workflows/android-build.yml        # 手動ビルド（workflow_dispatch）で APK 成果物を生成

hechima-wasm/                              # hechima スタックの変換エンジン部（powered by Mozc）
├── hechima_wasm.cc                        # 変換ラッパー（かな UTF-8 → 文節/候補 JSON。converter 層のみ使用）
├── link.sh                                # em++ リンクスクリプト（MOZC_SRC/MOZC_BUILD で駆動。-DNDEBUG 必須）
├── hechima_wasm_test.js                   # node ヘッドレス変換テスト（緑 = 「PASS — 変換成立」）
├── patches/data_manager.patch             # 埋め込み .inc (48MB) を焼かず CreateFromFile 化する自前パッチ
└── README.md                              # ビルドレシピ正典（NDEBUG の罠含む）

.github/workflows/hechima-wasm.yml         # 手動（workflow_dispatch）: fcitx5-mozc clone → パッチ → wasm ビルド → テスト → Release 添付

docs/
├── keylogickit-api.md                 # KeyLogicKit Public API リファレンス
├── keymap-format.md                   # キーマップ定義フォーマット仕様書 v1
├── keymap-v1.schema.json              # JSON Schema（バリデーション用）
├── gamepad-mapping.md                 # ゲームパッドひらがな入力マッピング仕様書
├── gime-android-ime-plan.md           # GIME Android IME 化 計画 + IME × Compose 作法
├── gime-vrchat-osc-plan.md            # GIME × VRChat OSC 連携 計画 (Android)
├── gime-vrchat-osc.md                 # VRChat OSC 連携 ユーザー向けセットアップガイド
├── gime-android-privacy-policy.md     # GIME Android プライバシーポリシー
├── gime-ios-osc-plan.md               # iOS GiME OSC 化計画 (Android 版を Swift 移植)
├── gime-brahmic-expansion-memo.md     # GIME Brahmic + Abjad 拡張 設計メモ（Devanagari Android PoC 実装済み）
└── privacy-policy.md                  # KanaEditor プライバシーポリシー
```
