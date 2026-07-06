# リファクタリング計画

2026-07-06 のコードレビュー（Swift 約17,000行 / Android 3プロジェクト約15,000行 / web 約9,000行）に基づく段階的計画。
各フェーズは独立して着手可能だが、**Phase 1（テスト基盤）を Phase 2・3 の前提**とする。安全網なしの構造変更は行わない。

## 決定事項ログ

- **2026-07-06**: gide では中国語を扱わない → `android-gide` の `PinyinEngine.kt` スタブは Phase 2 で削除し、機能フラグで中国語モードを無効化する。
- **2026-07-06**: 実施順を変更。Phase 4-1（CLAUDE.md 再構成）をドキュメント・メモリ整備として最優先で先行実施（同日完了）。以降は Phase 1 → 2 → 3 → 残りの 4。
- **2026-07-06**: **KanaEditor の縦書き対応を将来目標として設定**。使用技術は TextKit 2 に固定しない（UITextView 継続 / TextKit 2 直接利用 / CoreText カスタムビューを Phase 5 の spike で選定）。Phase 3 の分割はこの目標に沿って「描画層を差し替え可能にする境界」を作ることを優先する。

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
   - **進捗 (2026-07-06)**: コーパス v1 完成（形式仕様 = `Tests/golden/README.md`、romaji/AZIK/月配列/NICOLA の 4 キーマップ・26 ケース）。期待値はキーマップ JSON から手で導出（実装の出力コピーではない）。web ランナー実装済み（`web/src/engine/__tests__/golden.test.ts`、vitest、CI = web-test.yml）。Swift / Kotlin ランナーは未着手。
2. **Swift**: `KeyLogicKit.Package.swift` に testTarget 追加。対象順: `InputManager.drainSequentialBuffer`（greedy longest-match）、`SimultaneousKeyBuffer`（4状態FSM+ロールバック）、`KeymapCodable` roundtrip、`SentenceBoundary`。CI は macOS ランナーで `swift test`。
3. **web**: vitest 導入。対象順: `sequential-buffer.ts` / `simultaneous-buffer.ts` / `korean-composer.ts` / `keymap-expander.ts`。
4. **Android**: JUnit で `KoreanComposer` / `DevanagariComposer`、kide の `ChordKanaRouter` / `SequentialKanaRouter` / `AzikRouter`。

## Phase 2: Android 共通モジュール化

3プロジェクト間のコピペが既に黙って分岐している（`GamepadInputManager.kt` は android↔gide で120行乖離、`PinyinEngine.kt` は gide 側だけスタブ）。

1. 共有 Gradle モジュール `gamepad-core` を新設: `GamepadInputManager` / `GamepadResolver` / `GamepadSnapshot` / `KoreanComposer` / `DevanagariComposer`。出力先（IME InputConnection / HID / OSC）は interface で注入。
2. 共有モジュール `hid-core`: `HidKeyboardService` / `KeystrokeEmitter` / `UsHidUsageTable` / `HidConstants` / `HidKeyboardManager` + BT 権限ヘルパー（`computePermissionStatus` 等）。
3. 分岐の棚卸し: android↔gide の `GamepadInputManager` 120行差分を精査し、「意図した差分（設定で切替）」と「片側だけのバグ修正（移植漏れ）」に分類してから統合する。
4. `PinyinEngine` スタブ問題の決着: **gide は中国語非対応と決定（2026-07-06）**。スタブを削除し、機能フラグで中国語モードを無効化する。

## Phase 3: 巨大関数・God ファイル分割

Phase 1 のテストを付けてから着手。Swift/Kotlin で同名構造なので、両方同時に直すと Phase 2 の共通化にも寄与する。

1. `handleSnapshot`（Swift 457行 / Kotlin 約500行）: エッジ検出の共通前処理と、モード別 `handleXxxInput` への薄い dispatch に分離。プレビュー計算は `previewChar(for:)` として切り出し。
2. `IMETextView.swift`（2,046行）: `executeAction` / `executeChordAction` に重複するモード切替パターン（confirmAll→commitText→reset→switch が各7箇所）を `confirmAndCommitIfComposing()` ヘルパーに集約。
   **縦書き対応の布石として、分割時に以下を行う（Phase 5 の前提）**:
   - **`TextSurface` プロトコルの定義**: InputManager がテキスト面に要求する操作（commitText / setComposing 表示 / deleteBackward / キャレット矩形取得 / スクロール要求）を明示的な契約として切り出す。UITextView 実装はその第1実装という位置づけにする。
   - **幾何計算の集約**: 候補・予測ポップアップの位置計算（現状カーソル直下＝横書き前提）を 1 箇所にまとめ、行進行方向をパラメータ化できる形にしておく。
   - なお `SentenceBoundary` / `SmartSelectionState` / IME 層は文字インデックスベースで方向非依存のため変更不要（縦書き時も無傷で使い回す）。
3. `android-kide/MainActivity.kt`（2,039行・54関数+25 Composable）、`android/ui/GimeApp.kt`（1,300行）、`android-gide/MainActivity.kt`（973行）: Composable を UI ファイル群へ分割、HID/入力状態を ViewModel へ。
4. web `useGamepadInput.ts`（480行の単一 useEffect + 約30 ref）: 言語別状態機械を純関数として `engine/` に抽出（→ vitest 対象にもなる）。`punctuationTimerId` の cleanup 漏れも同時に修正。

## Phase 4: リポジトリ衛生

1. **CLAUDE.md 再構成** — **実施済み（2026-07-06）**: 58KB → 約17KB。GIME iOS/Android の巨大段落を `docs/gime-ios-notes.md` / `docs/gime-android-notes.md`、注記付きツリーを `docs/architecture.md`、GiDE/KIDE 実装詳細を `docs/kide-implementation-notes.md` へ移設。古かった index.json 手動編集手順を自動生成前提に修正し、キーマップ二重管理ルールとデバッグログ規約を追記。
2. **ルート直下の整理**: WIP キーマップ JSON（naginata/onishi/orz）は `keymaps-wip/` へ。naginata はルートと web/public/keymaps でバイト一致の重複。
3. **`generate-keymap-index.mjs` の addedAt 修正**: git 初回コミット日に依存するため shallow clone 環境で不正確な日付が生成され、コミット済み index.json と実行環境で差分が出る。日付は keymap JSON 側に明記するか、index.json を生成物として .gitignore する。
4. 小粒の修正（順不同）:
   - `KeymapCodable.swift:208` `keyToName[key]!` → CaseIterable からの自動生成またはフォールバック
   - `useCameraInput.ts:273` MediaPipe wasm の `@latest` → package.json と同じバージョンに固定
   - `BubbleService.kt` 等の `catch (_: Throwable) {}` → 最低限 `Log.w`
   - デッドコード削除: `IMETextViewRepresentable.onScrollRequest`（deprecated・未使用）、web `input-engine.ts` の `applyCharTransform`

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

## 優先度の考え方

- Phase 1 が最もレバレッジが高い: 3プラットフォーム移植の「同期が人力」という構造リスクを機械検証に変える。
- Phase 2 は次の機能追加（iOS→Android 移植など）のたびにコストを払っている箇所。共通化の工数は1回、回収は毎回。
- Phase 3 は Phase 1・2 と絡めてやると安い（テストを書くために切り出す、共通化のために揃える）。さらに Phase 5（縦書き）の成立条件である `TextSurface` 境界を作るフェーズでもあるため、IMETextView の分割は「関数を短くする」ではなく「描画層を差し替え可能にする」を基準に行う。
- Phase 4 は隙間時間でよいが、CLAUDE.md 再構成だけは Claude Code 駆動開発の効率に直結するため早めを推奨。
- Phase 5 は独立プロジェクト規模。ただし spike（5-1）だけは Phase 3 の設計判断に影響するため、前倒しで実施してもよい。
