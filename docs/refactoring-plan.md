# リファクタリング計画

2026-07-06 のコードレビュー（Swift 約17,000行 / Android 3プロジェクト約15,000行 / web 約9,000行）に基づく段階的計画。
各フェーズは独立して着手可能だが、**Phase 1（テスト基盤）を Phase 2・3 の前提**とする。安全網なしの構造変更は行わない。

## 決定事項ログ

- **2026-07-06**: gide では中国語を扱わない → `android-gide` の `PinyinEngine.kt` スタブは Phase 2 で削除し、機能フラグで中国語モードを無効化する。（→ 実際には後述の 2026-07-06 エントリのとおり **gide ごと削除**して解消。機能フラグ案は不採用）
- **2026-07-06**: 実施順を変更。Phase 4-1（CLAUDE.md 再構成）をドキュメント・メモリ整備として最優先で先行実施（同日完了）。以降は Phase 1 → 2 → 3 → 残りの 4。
- **2026-07-06**: **KanaEditor の縦書き対応を将来目標として設定**。使用技術は TextKit 2 に固定しない（UITextView 継続 / TextKit 2 直接利用 / CoreText カスタムビューを Phase 5 の spike で選定）。Phase 3 の分割はこの目標に沿って「描画層を差し替え可能にする境界」を作ることを優先する。
- **2026-07-06**: **Phase 2 を軽量版に変更 + gide 削除を決定**。調査の結果、①`android/`(GIME) は公開リポジトリへディレクトリごとミラーされるため sibling 共有 Gradle モジュールと相性が悪い、②共通化の橋渡し役だった gide は MVP 打ち切りで凍結、の 2 点で共有モジュール抽出の ROI が低いと判断。方針を「共有 Gradle モジュール新設」から「gide 削除 + 移植漏れバグの救出 + 現行 2 アプリ(GIME/KIDE)は独立維持」へ変更。gide 側にのみあった RS↓ チャタリング debounce(`rsDownDebounceMs`) を GIME へ移植し、`android-gide/` と `gide-android-build.yml` を削除。GiDE の設計文書（`GiDE-spec.md`/`docs/gide-spec-eval.md`）はアーカイブとして残置。

## Phase 0: 即効修正（2026-07-06 実施済み）

- キーマップ JSON の Swift/web 間乖離を解消（nicola の親指キー `international4`/`international5`、colemak の `license`）
- `scripts/check_keymap_sync.py` + `.github/workflows/keymap-check.yml` で乖離とスキーマ違反を CI 検出
- スキーマを実態に追従（`_comment*` キーの許可、sequential の `characterMap` 任意化）
- デバッグログ整理（web: `compiler.removeConsole`、Swift: `PinyinEngine` を `debugLog` コールバック化）

## Phase 1: テスト基盤（最優先・他フェーズの前提）

現状テストは全体で `OscPacketTest.kt` 1本のみ。3プラットフォームに手動移植された純ロジック（最も壊れやすく最もテストしやすい部分）から着手する。

1. **共有ゴールデンテスト・コーパス**（最重要アイデア）
   - `Tests/golden/` に「キーマップ + キーイベント列 → 期待かな出力」の JSON フィクスチャを置き、Swift / Kotlin / TypeScript の3実装が同じコーパスを読んで検証する。
   - 移植パリティ（"Port of *.swift L439-751" コメント依存の手動同期）を機械検証に置き換える。
   - **完了 (2026-07-06、PR #630/#631)**: コーパス v1（形式仕様 = `Tests/golden/README.md`、romaji/AZIK/月配列/NICOLA の 4 キーマップ・26 ケース、`skip` によるプラットフォーム除外対応）+ 3 ランナー稼働（web = vitest / Swift = iOS Simulator / Kotlin = kide の JUnit）。CI は web-test / swift-test / kide-test / keymap-check の 4 本。初回運用で chord テーブル `_comment` デコーダバグ（かわせみが iOS でデコード不能）と kide assets の乖離を検出・修正済み。Phase 1-2〜1-4 の残り（InputManager 等の追加ユニットテスト、GIME 側 KoreanComposer/DevanagariComposer のテスト）は Phase 2/3 の作業と併走で拡充する。
2. **Swift**: `KeyLogicKit.Package.swift` に testTarget 追加。対象順: `InputManager.drainSequentialBuffer`（greedy longest-match）、`SimultaneousKeyBuffer`（4状態FSM+ロールバック）、`KeymapCodable` roundtrip、`SentenceBoundary`。CI は macOS ランナーで `swift test`。
   **進捗（2026-07-07, PR #649）**: `SentenceBoundary`（文/句/カッコ境界検出、9ケース）と `KeymapCodable` roundtrip（バンドル4キーマップの encode 冪等性 + 主要フィールド保存）を追加。まず決定論的でタイミング・辞書ロード非依存の純ロジックから着手した。後者が **inputBase 展開キーマップの encode 非対称バグを検出**し、同 PR で修正（encode の分岐条件を init の展開判定と対称化。ゴールデンテストの chord `_comment` 検出に続く「テストが既存バグを炙り出した」2例目）。残り: `SimultaneousKeyBuffer`（4状態FSM+ロールバック、実時間依存のためタイミング制御が必要）、`InputManager.drainSequentialBuffer`（greedy longest-match、辞書ロードを伴う）。
3. **web**: vitest 導入。対象順: `sequential-buffer.ts` / `simultaneous-buffer.ts` / `korean-composer.ts` / `keymap-expander.ts`。
4. **Android**: JUnit で `KoreanComposer` / `DevanagariComposer`、kide の `ChordKanaRouter` / `SequentialKanaRouter` / `AzikRouter`。

## Phase 2: Android 共通化（軽量版で完了・2026-07-06）

当初計画は共有 Gradle モジュール（`gamepad-core` / `hid-core`）の抽出だったが、上記決定ログのとおり **ROI が低いと判断し軽量版に変更**した。理由: (a) `android/`(GIME) は公開 `msonrm/GIME` へディレクトリごと丸コピーでミラーされるため、`android/` の外に共有モジュールを置くと公開リポジトリでビルドが壊れる。(b) 共通化の橋渡し役だった gide が MVP 打ち切りで凍結しており、現行 2 アプリ（GIME=gamepad+IME / KIDE=keyboard+HID）は直接共有コードがほぼない。

**背景（当初の問題認識）**: 3プロジェクト間のコピペが黙って分岐していた（`GamepadInputManager.kt` は android↔gide で正規化後 99 行の実差分、`PinyinEngine.kt` は gide 側だけスタブ、hid/* は gide↔kide で大きく乖離）。

**実施内容**:
1. `GamepadInputManager` の android↔gide 差分棚卸し。**双方向に意図的差分**があると判明:
   - GIME 側のみ: LT+LS click = Ctrl+Enter 送信機能（Slack/Discord 送信用）
   - gide 側のみ: RS↓ チャタリング debounce(`rsDownDebounceMs`)、HID 出力用フック(`onConvert`/`onFinalizeComposing`)
   このうち **RS↓ debounce は GIME も同じ暴走リスク（`rStickDownTapCount` 急増→句読点サイクル誤爆）を抱える移植漏れバグ**と判定し、GIME へ救出（`android/.../input/GamepadInputManager.kt`。GIME は LS click には既に `lsDebounceMs` を持つのに RS↓ には無かった）。他は出力先の違いによる意図的差分のため統合対象外。
2. **`android-gide/`（GiDE）を削除**（`gide-android-build.yml` も削除）。共通化の橋渡し役だったが凍結済みで、救出すべき固有実装は上記 debounce のみだった（PinyinEngine/JapaneseConverter はスタブ、`hid/` は KIDE に進化版が存在）。GiDE の設計文書はアーカイブ残置。
3. `PinyinEngine` スタブ問題は gide ごと削除で解消。GIME は中国語対応を維持。

**見送り**: 共有 Gradle モジュール抽出は上記 (a)(b) により見送り。将来 GIME↔KIDE に実質的な共有面が育った時点で、`android/` 内モジュール化やミラー workflow 拡張とセットで再検討する。byte 一致していた `GamepadSnapshot`/`GamepadResolver`/`KoreanComposer`/`DevanagariComposer`（android↔gide）は gide 削除で単一化した。

## Phase 3: 巨大関数・God ファイル分割

Phase 1 のテストを付けてから着手。Swift/Kotlin で同名構造なので、両方同時に直すと Phase 2 の共通化にも寄与する。

1. `handleSnapshot`（Swift 457行 / Kotlin 約500行）: エッジ検出の共通前処理と、モード別 `handleXxxInput` への薄い dispatch に分離。プレビュー計算は `previewChar(for:)` として切り出し。
2. `IMETextView.swift`（2,046行）: `executeAction` / `executeChordAction` に重複するモード切替パターン（confirmAll→commitText→reset→switch が各7箇所）を `confirmAndCommitIfComposing()` ヘルパーに集約。
   **ヘルパー集約は完了（2026-07-06）**: `if isComposing { confirmAll→commitText→logEvent }` の重複を **9 箇所**（当初想定の 7 箇所より多かった: executeChordAction 3・executeAction 2・handleFullControlIMEKey/pressesBegan/syncChordBufferTables 4）確認し、確定文字列を返す `confirmAndCommitIfComposing(_:) -> String?` に集約（呼び出し側は返り値でサイト固有 logEvent を出す）。IMETextView net −5 行。UIKit 依存で Linux ローカルコンパイル不可のため swift-test CI（iOS Simulator）で compile 検証。**残り（TextSurface 境界・幾何集約）は Phase 5-1 spike 後**。
   **縦書き対応の布石として、分割時に以下を行う（Phase 5 の前提）**:
   - **`TextSurface` プロトコルの定義**: InputManager がテキスト面に要求する操作（commitText / setComposing 表示 / deleteBackward / キャレット矩形取得 / スクロール要求）を明示的な契約として切り出す。UITextView 実装はその第1実装という位置づけにする。
   - **幾何計算の集約**: 候補・予測ポップアップの位置計算（現状カーソル直下＝横書き前提）を 1 箇所にまとめ、行進行方向をパラメータ化できる形にしておく。
   - なお `SentenceBoundary` / `SmartSelectionState` / IME 層は文字インデックスベースで方向非依存のため変更不要（縦書き時も無傷で使い回す）。
3. `android-kide/MainActivity.kt`（2,039行・54関数+25 Composable）、`android/ui/GimeApp.kt`（1,300行）: Composable を UI ファイル群へ分割、HID/入力状態を ViewModel へ。
   **kide 第1スライス完了（2026-07-07）**: 可視化タブのクラスタ（VisualizerTab + 配下 10 Composable + `ChartSection`/`KanaData`/`KeyboardMockRows` ヘルパー、連続 674 行）を `VisualizerScreen.kt` へ機械的分離（挙動不変）。`VisualizerTab` は KideScreen から呼ぶため internal、共有分類ヘルパー `categorize` は internal 化して MainActivity に残置。MainActivity 2,039→1,357 行。**環境で Android ローカルビルド不可（aapt2 が exec 不可）のため kide-test CI で compile 検証**。
   **kide 第2スライス完了（2026-07-07）**: 配列タブ・設定タブとその配下カード群（LayoutTab / SettingsTab + 12 カード + `RouterCategory`/`categorize`/`connectionStateLabel`、連続 582 行）を `KideScreens.kt` へ機械的分離。KideScreen から呼ぶ `LayoutTab`/`SettingsTab`/`BindingPlaceholder` を internal 化、他カードは private のまま。`categorize`(internal)/`RouterCategory`(public) は VisualizerScreen.kt からも参照、`MainActivity.PermissionStatus`/`KeyboardDeviceInfo` は public ネスト型で越境可。**MainActivity 1,357→774 行**（原 2,039 の 38%）。残り: HID/入力状態の ViewModel 化、GimeApp（GIME は PR-CI 無しで環境検証不可）。
4. web `useGamepadInput.ts`（653行の単一 useEffect + 約30 ref）: 言語別状態機械を純関数として `engine/` に抽出（→ vitest 対象にもなる）。`punctuationTimerId` の cleanup 漏れも同時に修正。
   **完了（2026-07-06）**: 日/英/韓の文字入力ロジックを `engine/gamepad-input-machine.ts` の純関数（`stepJapanese`/`stepEnglish`/`stepKorean`）へ機械的移植し、フレーム間状態を単一の `MachineState` に集約（副作用はフックに残置、英語 UI 状態は状態機械から毎フレーム同期）。vitest characterization テスト 16 ケース追加。`punctuationTimerId` の cleanup 漏れ（`cancelAnimationFrame` のみだった）を修正。hook は 653→410 行。tsc/eslint/全 42 テスト green。

## Phase 4: リポジトリ衛生

1. **CLAUDE.md 再構成** — **実施済み（2026-07-06）**: 58KB → 約17KB。GIME iOS/Android の巨大段落を `docs/gime-ios-notes.md` / `docs/gime-android-notes.md`、注記付きツリーを `docs/architecture.md`、GiDE/KIDE 実装詳細を `docs/kide-implementation-notes.md` へ移設。古かった index.json 手動編集手順を自動生成前提に修正し、キーマップ二重管理ルールとデバッグログ規約を追記。
2. **ルート直下の整理**: WIP キーマップ JSON（naginata/onishi/orz）は `keymaps-wip/` へ。naginata はルートと web/public/keymaps でバイト一致の重複。
3. **`generate-keymap-index.mjs` の addedAt 修正**: git 初回コミット日に依存するため shallow clone 環境で不正確な日付が生成され、コミット済み index.json と実行環境で差分が出る。日付は keymap JSON 側に明記するか、index.json を生成物として .gitignore する。
4. 小粒の修正（順不同）:
   - `KeymapCodable.swift:208` `keyToName[key]!` → CaseIterable からの自動生成またはフォールバック
   - ~~`useCameraInput.ts:273` MediaPipe wasm の `@latest` → package.json と同じバージョンに固定~~ **完了（2026-07-07）**: `@0.10.34` に固定（node_modules 解決版と一致）
   - `BubbleService.kt` 等の `catch (_: Throwable) {}` → 最低限 `Log.w`
   - デッドコード削除: `IMETextViewRepresentable.onScrollRequest`（deprecated・未使用）、~~web `input-engine.ts` の `applyCharTransform`~~ **完了（2026-07-07、`applyCharTransform` 削除）**
   - **web 未使用変数・import の一掃 完了（2026-07-07）**: eslint `no-unused-vars` 18 件（10 ファイル）を除去。デッドの const/関数（`HID_TO_KANATA`/`popcount` 等）も削除。未使用 param `resolveThumbDirection(isLeft)` は呼出元込みで除去。tsc/eslint(no-unused-vars 0)/vitest 42 green、新規エラー混入なし。残る eslint error 16 件は `react-hooks/refs`（意図的 latest-ref）等の既存パターンで対象外。

## Phase 5: 縦書き対応への道筋（将来・Phase 1 と 3 完了が前提）

目標: KanaEditor で縦書き入力・表示を可能にする。使用技術は未定（TextKit 2 に固定しない）。

前提知識: UITextView に縦書きモードはなく、iOS の TextKit 2 も縦書きレイアウトは実用上未整備。
縦書きは描画層の置き換えを伴う可能性が高いが、IME 層（KeyRouter / InputManager / SimultaneousKeyBuffer /
SentenceBoundary）は UIKit 非依存・方向非依存のため無傷で使い回せる。影響範囲は `Editor/`（テキスト面）と
`UI/`（ポップアップ幾何）に閉じる — それを保証するのが Phase 3 の `TextSurface` 境界。

1. **技術 spike（1〜2週間、使い捨てコード前提）**: 3 案を小さな PoC で比較する。
   - (a) UITextView 継続 + 回転トリック等の回避策 — おそらく非現実的だが棄却理由を記録する
   - (b) TextKit 2 直接利用（NSTextLayoutManager を自前ビューでホスト）— iOS での縦書きレイアウト可否を実機確認
   - (c) CoreText カスタムビュー（`kCTFrameProgressionRightToLeft`）— 縦書きエディタの実績ある王道
   - 判断基準: 縦書きグリフ（約物・長音符の回転）/ 選択とキャレット制御 / パフォーマンス / アクセシビリティ / 実装・保守コスト
2. **`TextSurface` の第2実装を「横書きのまま」作る**: 選定した技術でカスタムテキストビューを実装し、
   設定フラグで UITextView 実装と切替可能にする。ゴールデンテスト（Phase 1）+ 実機で挙動一致を確認。
   マイルストーンを「縦書き」と「ビュー置き換え」に分離することでリスクを半減する。
   副産物: `super.pressesBegan` の marked text 強制 commit 対策や `textStorage` 手動下線などの
   UITextView 固有ハックが不要になる。
3. **縦書きモードの実装**: 行進行方向の切替、候補・予測ポップアップの縦書き対応（行の左側に表示等）、
   約物・長音符の縦書きグリフ確認。初期スコープ外を明記: ルビ、縦中横、禁則処理の高度化。

## Phase 6: GIME Android 変換エンジンの provenance 監査・差し替え/更新可能化（将来）

GIME Android は vendored の **KazumaProject/JapaneseKeyboard** 変換エンジン（LOUDS + N-gram、`com/kazumaproject/` に同梱、辞書 assets ~15MB）を使う。コードは MIT だが **辞書データの系譜（mozc / UT 辞書由来か等）がリポジトリ内に未文書化**で、LICENSE/ACKNOWLEDGEMENTS も未同梱。公開/商用配布の前に provenance を確定し、必要なら差し替え/更新できる状態にする。

### 現状アセスメント（2026-07-07）
- **変換エンジンはファサード `engine/JapaneseConverter.kt` の裏に隔離**されている。公開型は GIME 自前（`Candidate(surface, reading, cost)` / `BunsetsuResult`）で、KazumaProject 内部（`KanaKanjiEngine` / LOUDS / GraphBuilder / FindPath 等）は非公開。
- 入力コア `GamepadInputManager` は `converter.convertBunsetsu()` を呼び `JapaneseConverter.Candidate` を持つのみ（`com.kazumaproject` 非依存）。→ **エンジン差し替えの最小形＝`JapaneseConverter` の再実装**（消費側は無改変）。
- iOS GIME は AzooKey/Zenzai（KeyLogicKit の `InputManager`）を同じ入力抽象の裏で使用済み ＝ プラットフォーム間で既にエンジンが違う＝差し替え可能性の実証。

### 摩擦点（一枚差し替えで済まない理由）
1. **学習/ユーザー辞書が KazumaProject 製で漏れている**: `LearnRepository` / `UserDictionaryRepository` / `LearnDao` / `UserWord`（Room）を GIME 本体5ファイル（`ui/DictionaryScreen` / `MainActivity` / `ui/GimeApp` / `ime/GimeInputMethodService` / `learn/GimeDatabase`）が直接参照し、`JapaneseConverter` にも注入（学習加重に寄与）。エンジンごと学習/辞書を替えるならここも波及する。
2. **`convertBunsetsu` の契約**: GIME の文節編集 UX（左スティックで文節移動・文節別候補 cycle）は「文節分割 + 文節別候補リスト」に依存。差し替え先は flat な n-best ではなく文節分割を提供する必要がある。

### 進め方（案・優先順）
1. **provenance 監査** ✅ **完了（2026-07-07, PR #644）**: 辞書 assets の出どころ・ライセンスを特定し LICENSE/ACKNOWLEDGEMENTS を同梱。keymap 二重管理と同様に CI で欠落検出しても良い。
   - **確定内容**: 変換モジュール = KazumaProject/JapaneseKeyboard（MIT）を上流 commit `4995505`（2026-04-03）から vendor。辞書 = google/mozc の system 辞書（BSD-3-Clause + NAIST License + Public Domain、SA 継承なし）。Mozc UT（CC BY-SA）は**不同梱**（ファサードが無効化 + assets に無し）。
   - **成果物**: `docs/gime-android-converter-vendor.md`（素性 + 上流追従手順）、`android/scripts/sync-kazuma-converter.sh`（`KAZUMA_REF` 指定の再同期）、`GIME.ACKNOWLEDGEMENTS.md`（mozc ライセンス全文同梱）。
   - **残課題（任意）**: CI での欠落検出（keymap 二重管理と同様のガード）は未実装。
2. **`KanaConverter` interface 抽出**: `JapaneseConverter` の公開 API（`convert` / `convertBunsetsu` / `initializeAsync` / `isReady`）を interface 化し実装を差し替え可能に（現行 KazumaProject 実装が第1実装）。摩擦点2の契約を明文化する。
3. **差し替え/更新の選択肢**（動機に応じて）:
   - **辞書データだけ差し替え**（エンジン維持、mozc-UT 等 出どころ明確な辞書へ）— 摩擦点1/2を回避する最小対応。純粋に provenance が動機ならこれが費用対効果最良
   - KazumaProject 本体のアップストリーム追従（新版を vendor 更新）
   - Mozc を JNI で採用（BSD・出どころ明確。文節 API マッピング + JNI 統合の工数）
   - サーバー / オンデバイス LLM 変換（オフライン性・レイテンシの再設計を伴う大改修）
4. **学習/辞書の脱 KazumaProject**（必要なら）: 上記5ファイルの依存を GIME 自前の永続化層 or interface へ置換。
5. **iOS 側との関係**: iOS は AzooKey/Zenzai なので直接の共通化対象外。ただし `KanaConverter` の契約（文節分割 + 候補）を両 OS で概念統一しておくと、将来のゴールデンテスト共有（Phase 1 拡張）が効く。

### 検証
Android ローカルビルド不可のため kide 同様 dispatch ビルド + 実機。interface 抽出はコンパイル検証で足りるが、変換品質の回帰は**ゴールデンコーパス（Phase 1）の変換出力への拡張** or 実機比較で担保する。

## 優先度の考え方

- Phase 1 が最もレバレッジが高い: 3プラットフォーム移植の「同期が人力」という構造リスクを機械検証に変える。
- Phase 2 は次の機能追加（iOS→Android 移植など）のたびにコストを払っている箇所。共通化の工数は1回、回収は毎回。
- Phase 3 は Phase 1・2 と絡めてやると安い（テストを書くために切り出す、共通化のために揃える）。さらに Phase 5（縦書き）の成立条件である `TextSurface` 境界を作るフェーズでもあるため、IMETextView の分割は「関数を短くする」ではなく「描画層を差し替え可能にする」を基準に行う。
- Phase 4 は隙間時間でよいが、CLAUDE.md 再構成だけは Claude Code 駆動開発の効率に直結するため早めを推奨。
- Phase 5 は独立プロジェクト規模。ただし spike（5-1）だけは Phase 3 の設計判断に影響するため、前倒しで実施してもよい。
- Phase 6（変換エンジン）は緊急ではないが、**provenance 監査（6-1）と `KanaConverter` interface 抽出（6-2）は安く先に進められる**（低リスク・compile 検証可）。実際のエンジン差し替えはその後、動機（出どころ確定なら辞書のみ差し替えが最小）に応じて判断する。エンジン本体はファサードで隔離済みなので、境界を interface 化しておけば差し替え時の波及が読める。
