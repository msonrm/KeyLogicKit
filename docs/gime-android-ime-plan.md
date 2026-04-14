# GIME Android IME 化 計画

TODO.md の Phase A5「システム IME 化」を具体化した計画書。
任意のアプリ（メモ・ブラウザ・SNS など）でゲームパッドから日本語/韓国語/中国語入力を行えるようにするのが目標。

## 前提と現状整理

現状の GIME Android は **Activity ベース** で、ゲームパッド入力を横取りしてローカルの `TextFieldValue` に書き込む閉じた構成。

```
Gamepad HID
   └── MainActivity (ComponentActivity)
         ├── onKeyDown / onKeyUp        (ボタン・D-pad)
         └── onGenericMotionEvent       (アナログスティック / トリガー軸)
              └── GamepadSnapshot
                    └── GamepadInputManager
                          ├── onDirectInsert(text, replaceCount)
                          ├── onDeleteBackward()
                          ├── onCursorMove(offset)
                          ├── onConfirmOrNewline()
                          └── onGetLastCharacter()
                                └── GimeApp (Compose) → TextFieldValue
```

engine/ 層は pure Kotlin で Android 非依存、`GamepadInputManager` はコールバックで出力先を
差し替え可能な設計になっている（TODO.md 643 行目の方針どおり）。IME 化は
**出力先を `InputConnection` に差し替える**のが本質。

## Android IME アーキテクチャ上の制約

Android の `InputMethodService` は iOS の `UITextInput` とは大きく異なる。

| 項目 | Activity モード（現状） | IME サービス |
|---|---|---|
| `onKeyDown(keyCode, KeyEvent)` | Activity で受ける | `InputMethodService` で受けられる（IME 専用の `dispatchKeyEventPreIme` ルート） |
| `onGenericMotionEvent(MotionEvent)` | Activity で受ける | **`InputMethodService` で受けられる**（`dispatchGenericMotionEventPreIme` ルート）※当初見落としていた |
| テキスト書込先 | 自前の `TextFieldValue` | `currentInputConnection`（対象アプリの EditText） |
| Composing 下線 | 自前描画 | `setComposingText` で OS が描画 |
| テキスト読取 | ローカル文字列 | `getTextBeforeCursor(n, 0)` （非同期・失敗時 null） |

### joystick 受信の正解ルート（実機検証で確定）

計画当初は「MotionEvent が IME に届くかは要検証・最悪 D-pad 縮退」としていたが、
実機（DualSense）で以下が判明した:

- **`View.onGenericMotionEvent`（InputView 側）**: View focus が必要だが、
  IME ウィンドウは `FLAG_NOT_FOCUSABLE` のため focus を取れず発火しない
- **`FLAG_NOT_FOCUSABLE` クリアで focus 奪取**: joystick MotionEvent は届くが、
  対象 EditText の `InputConnection` が切れてボタン入力が効かなくなる副作用あり
- **`InputMethodService.onGenericMotionEvent` 直接 override**: `onKeyDown` と
  同じ IME 専用ルートで届く。focus 奪取なし、両立可能 ← **これが正解**

## 段階計画

### Phase A6-1: IME 骨格を立てる

ゴール: IME として認識され、有効化できる。まだ何も入力しない。

- `AndroidManifest.xml` に `<service>` を追加
  - `android.permission.BIND_INPUT_METHOD`
  - `android.view.InputMethod` メタデータ
  - intent-filter: `android.view.InputMethod`
- `res/xml/method.xml` を追加（IME サブタイプ定義、日本語 locale）
- `com.gime.android.ime.GimeInputMethodService`（新規）
  - `onCreateInputView()` → 空の `ComposeView` を返す（後続で中身を詰める）
  - `onStartInput`, `onFinishInput` でログのみ
- `MainActivity` に「GIME を IME として有効化」ボタンを追加
  - `Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)` を起動
  - 切替ピッカー呼び出し（`InputMethodManager.showInputMethodPicker()`）

### Phase A6-2: ハードウェアキー受信

ゴール: ゲームパッドのボタン・D-pad 入力が IME 側に届く。

- `GimeInputMethodService.onKeyDown/onKeyUp` を override
  - `GamepadSnapshot.isGamepad(event.device)` で判定
  - 既存の `GamepadSnapshot.updateFromKeyEvent()` を再利用
  - 非ゲームパッドイベントは `super` に委譲（通常の IME 動作を阻害しない）
- ゲームパッドを接続していないときや、ゲームパッドの意図が明らかに IME 向けでないとき
  （例: A/B でゲーム操作しているとき）に**入力を横取りしない**判定ルールを設ける
  - 暫定: 対象アプリに EditorInfo が渡っており `inputType != TYPE_NULL` のときのみ横取り

### Phase A6-3: アナログスティック・トリガー受信（要検証）

ゴール: 左右スティックとアナログトリガーの入力が IME に届く。

- `onCreateInputView()` で返すビューを `focusableInTouchMode = true` に設定
- そのビューの `setOnGenericMotionListener` で `MotionEvent` を受ける
  - `GamepadSnapshot.fromMotionEvent()` を再利用
- 実機検証項目:
  - 対象エディタにフォーカスがある状態で InputView が motion を受けられるか
  - Bluetooth 経由で接続中のゲームパッドで軸イベントの取りこぼしがないか
  - 不可だった場合のフォールバック案:
    - InputView にフォーカスを一時的に奪わせる方式（ただし IME 選択ポップアップ等の挙動変化に注意）
    - D-pad（KEYCODE_DPAD_*）のみで操作できるサブセットに縮退
    - `SYSTEM_ALERT_WINDOW` オーバーレイ経由（最終手段、権限要求が重い）

### Phase A6-4: InputConnection への出力差し替え

ゴール: ゲームパッド入力が対象アプリのテキスト欄に反映される。

- 新設 `ImeTextSink`（仮）を IME サービス側に置き、`GamepadInputManager` の
  コールバックを束ねる。`GimeApp`（Activity）側も同じインタフェースを実装するよう移行
- コールバック → InputConnection 対応
  - `onDirectInsert(text, replaceCount)`
    - `replaceCount > 0` なら `deleteSurroundingText(replaceCount, 0)`
    - `commitText(text, 1)`（暫定、composing は Phase A6-5 で導入）
  - `onDeleteBackward()` → `deleteSurroundingText(1, 0)`
  - `onCursorMove(offset)` →
    - 単純版: `sendKeyEvent(DPAD_LEFT/RIGHT)`
    - 厳密版: `getExtractedText` でカーソル位置取得 → `setSelection`
  - `onConfirmOrNewline()` →
    - EditorInfo の `imeOptions` を見て、`IME_ACTION_*` があれば `performEditorAction`
    - 無ければ `commitText("\n", 1)`
  - `onGetLastCharacter()` → `getTextBeforeCursor(1, 0)?.lastOrNull()`

### Phase A6-5: 変換中の composing text 対応

ゴール: 変換中のひらがなバッファや候補表示を `setComposingText` で透明な下線表示に。

現状 `GamepadInputManager` は「すでに入れた文字を `replaceCount` で置換する」
eager output 方式になっている。InputConnection でもそのまま動作するが、
以下の対応で IME らしい体験になる:

- `GamepadInputManager` に composing 境界コールバックを追加
  - `onBeginComposing(text)` / `onUpdateComposing(text)` / `onFinishComposing(commit: Boolean)`
- 現在 `emitKana` / `emitCommitted` / `startConversion` の分岐はすべて `onDirectInsert(replaceCount)`
  に集約されているので、ここを「composing or commit」に仕分け直す
- IME 側では:
  - `onUpdateComposing(text)` → `setComposingText(text, 1)`
  - `onFinishComposing(commit=true)` → `finishComposingText()`
  - `onFinishComposing(commit=false)` → `commitText("", 1)` + `finishComposingText()`
- Activity 側の `GimeApp` も同じインタフェースで再実装（動作互換性を保つ）

この段階で「変換中の文節」に下線・ハイライトが自動で付くようになり、
候補パネルと対象アプリの表示が二重にならない。

### Phase A6-6: 候補パネル・ビジュアライザを InputView に移植

ゴール: IME 有効化中に候補リストとゲームパッドビジュアライザが画面下部に表示される。

- `onCreateInputView()` で Compose 製ビジュアライザ + 候補パネルを返す
  - 既存の `GimeApp.kt` を分解し、エディタ TextField を除いた
    「ビジュアライザ + 候補 + モードインジケータ」部分を `ImeInputView` として再利用
- `ComposeView` を `InputMethodService` 上でホストする際は以下の設定が必要:
  - `ViewTreeLifecycleOwner.set(view, this)` 相当の self-hosted 実装
  - `ViewTreeViewModelStoreOwner.set(...)` 相当
  - `ViewTreeSavedStateRegistryOwner.set(...)` 相当
  - ComposeView は Activity 外ではデフォルトでは動かないので、`setViewCompositionStrategy` で
    `DisposeOnDetachedFromWindow` を使う
- 候補ビューの分離は任意。`onCreateCandidatesView()` を使うと IME フレームの上に別パネルとして出る

### Phase A6-7: 実機 QA・BT 再接続・切替導線

- Bluetooth で接続しているゲームパッドが切断→再接続したときに
  IME サービス側の「接続中」判定を動的に更新
- `onStartInput` のたびに `checkConnectedGamepads` を走らせる
- 対象エディタが `inputType = TYPE_NULL` のときは黙って super に委譲（ゲームを阻害しない）
- IME 有効化フロー（設定 → 言語と入力 → 仮想キーボード → GIME 追加 → 切替）を README に書く

## 成果物とマイルストーン

| マイルストーン | 成果 |
|---|---|
| M1 = A6-1 完了 | 設定画面で GIME が IME 一覧に出現、選択可能 |
| M2 = A6-2/3 完了 | 任意のテキスト欄で D-pad/スティック/トリガー 入力が IME に届く（まだ出力なし） |
| M3 = A6-4 完了 | ゲームパッドで各言語の生かなが対象アプリに入る |
| M4 = A6-5 完了 | 変換中の文節が composing 下線表示になる |
| M5 = A6-6 完了 | ビジュアライザ・候補が IME 内に表示される |
| M6 = A6-7 完了 | 実機 QA 通過、公開可能 |

## 設計上の不変条件（絶対に崩さない）

1. **engine/ 層は pure Kotlin・Android 非依存**のまま維持
   （`GamepadResolver` / `KoreanComposer` / `PinyinEngine` / `JapaneseConverter`）
2. **`GamepadInputManager` は出力先を知らない**。コールバックだけで IME/Activity を切り替え
3. **Activity モードは残す**（変換テスト・ユーザー辞書編集・学習リセット用）
4. **ユーザー辞書・学習 DB は共有**（`DatabaseProvider.get(context)` のシングルトン）

## リスクと対応方針

| リスク | 可能性 | 対応 |
|---|---|---|
| InputView が MotionEvent を受けられない | 中 | Phase A6-3 前倒しで実機検証。不可なら D-pad のみの縮退モードを提供 |
| ComposeView を IME 上でホストできない | 低〜中 | Compose なしで XML view に書き直すプランを B 案として用意 |
| getTextBeforeCursor の非同期失敗 | 中 | `onGetLastCharacter` を内部キャッシュで補完（自前バッファの末尾を返す） |
| ゲームを邪魔する誤認識 | 高 | `inputType` チェックと明示的な on/off トグルで抑止 |
| BT パッドのイベント取りこぼし | 中 | 既存のヒステリシス・within-family 排他ロジックをそのまま移植して吸収 |

## 参照

- [TODO.md](../TODO.md) Phase A5「システム IME 化」
- [Android Developers: Create an input method](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method)
- [InputConnection reference](https://developer.android.com/reference/android/view/inputmethod/InputConnection)
