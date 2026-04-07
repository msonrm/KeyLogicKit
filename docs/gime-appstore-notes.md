# GiME — App Store Submission Notes

## App Review Notes

> **What is this app?**
> GiME is a text input tool that uses a game controller (MFi / Xbox / PlayStation / Switch Pro Controller) as the sole input device. Users enter text in 5 languages (Japanese, English, Korean, Simplified Chinese, Traditional Chinese) using gamepad buttons and sticks. The entered text can be passed to other apps via App Intents / Shortcuts.
>
> **Testing without a game controller:**
> If a game controller is not available, the app also accepts input from a hardware keyboard (Romaji US layout) as a fallback. Connect a hardware keyboard to the iPad and type normally.
>
> **Privacy and data handling:**
> This app does NOT log, record, or transmit any input data. All button inputs are consumed in real-time for text conversion and immediately discarded. The app makes no network requests — all dictionary lookups and text conversion happen entirely on-device. The app contains no analytics SDKs, tracking, or telemetry. See PrivacyInfo.xcprivacy: NSPrivacyCollectedDataTypes is empty, NSPrivacyTracking is false.
>
> **Why not a Keyboard Extension?**
> GiME is a standalone text editor, not a system keyboard replacement. It processes game controller input via GCController framework, which is not available in Keyboard Extension processes. The entered text is shared with other apps through App Intents (Shortcuts), not through the system keyboard pipeline.
>
> **Demo video:** [URL]

## App Store 説明文（日本語）

ゲームコントローラーだけでテキスト入力。

GiME は、iPad に接続したゲームコントローラー（MFi / Xbox / PlayStation / Switch Pro Controller 等）でテキストを入力するツールです。

■ 5言語対応
日本語（かな漢字変換）・英語・韓国語・中国語簡体字・中国語繁體字。Start ボタンで瞬時に切り替え。

■ 直感的な操作
左手で子音、右手で母音。フリック入力の感覚をゲームパッドに最適化しました。リアルタイムのビジュアライザで、どのボタンが何の文字に対応しているか一目でわかります。

■ テキスト操作モード
Back ボタンで切り替え。文単位のナビゲーション・スマート選択・文の並べ替えをコントローラーだけで。

■ ショートカット連携
入力したテキストをショートカットアプリ経由で翻訳、SNS 投稿など他のアプリに渡せます。

■ プライバシー
入力データの記録・送信は一切行いません。すべての処理はデバイス上で完結します。

## App Store Description (English)

Text input with just a game controller.

GiME lets you type on your iPad using a game controller (MFi, Xbox, PlayStation, Switch Pro Controller, and more).

■ 5 Languages
Japanese (with kana-kanji conversion), English, Korean, Simplified Chinese, and Traditional Chinese. Switch instantly with the Start button.

■ Intuitive Controls
Left hand selects consonants, right hand selects vowels — like flick input, redesigned for a gamepad. A real-time visualizer shows which button maps to which character.

■ Text Operation Mode
Toggle with the Back button. Navigate by sentence, smart-select text, and rearrange sentences — all with the controller.

■ Shortcuts Integration
Pass your text to other apps via the Shortcuts app — translate, post to social media, and more.

■ Privacy
No input data is ever logged or transmitted. All processing happens entirely on your device.
