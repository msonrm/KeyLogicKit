# GiME — App Store Submission Notes

## App Review Notes

> **What is this app?**
> GiME is a text input tool that uses a game controller (MFi / Xbox / PlayStation / Switch Pro Controller) as the sole input device. Users enter text in 5 languages (Japanese, English, Korean, Simplified Chinese, Traditional Chinese) using gamepad buttons and sticks, plus an experimental Devanagari layout for Sanskrit / Hindi / Marathi / Nepali. The entered text can be passed to other apps via App Intents / Shortcuts.
>
> **Testing without a game controller:**
> If a game controller is not available, the app also accepts input from a hardware keyboard (Romaji US layout) as a fallback. Connect a hardware keyboard to the iPad and type normally.
>
> **Privacy and data handling:**
> This app does NOT log, record, or transmit any input data to the developer or any third party. All button inputs are consumed in real-time for text conversion and immediately discarded. Dictionary lookups and text conversion happen entirely on-device. The app contains no analytics SDKs, tracking, or telemetry. An optional VRChat OSC feature (disabled by default) sends typed text over UDP only to a user-specified IP and port on the local network when the user explicitly enables it; see the privacy policy for details. See PrivacyInfo.xcprivacy: NSPrivacyCollectedDataTypes is empty, NSPrivacyTracking is false.
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

■ Devanagari 入力（実験的）
Sanskrit / Hindi / Marathi / Nepali 等を直接打鍵できる実験的モード。varnamala（子音表）の時計回り配置と halant（्）明示方式で、ITRANS / Google Hindi IME と同じ感覚で conjunct を構成できます。

■ ショートカット連携
入力したテキストをショートカットアプリ経由で翻訳、SNS 投稿など他のアプリに渡せます。

■ プライバシー
入力データを開発者や第三者へ送信することは一切ありません。すべての処理はデバイス上で完結します。VRChat 向けの OSC 連携はデフォルト OFF で、ユーザーが有効化した場合のみ、指定した IP・ポートへ UDP で送信します。

## App Store Description (English)

Text input with just a game controller.

GiME lets you type on your iPad using a game controller (MFi, Xbox, PlayStation, Switch Pro Controller, and more).

■ 5 Languages
Japanese (with kana-kanji conversion), English, Korean, Simplified Chinese, and Traditional Chinese. Switch instantly with the Start button.

■ Intuitive Controls
Left hand selects consonants, right hand selects vowels — like flick input, redesigned for a gamepad. A real-time visualizer shows which button maps to which character.

■ Devanagari Input (Experimental)
An experimental layout for typing Sanskrit, Hindi, Marathi, Nepali, and other Devanagari scripts directly on a gamepad. Uses a clockwise varnamala arrangement and explicit halant (्) — the same mental model as ITRANS and Google Hindi IME.

■ Shortcuts Integration
Pass your text to other apps via the Shortcuts app — translate, post to social media, and more.

■ Privacy
No input data is ever sent to the developer or third parties. All processing happens on-device. An optional VRChat OSC feature is disabled by default and, when enabled, sends typed text only to the user-specified IP and port on the local network.
