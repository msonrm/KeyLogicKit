# KeyLogicKit

iPadOS 向け自前 IME エンジンライブラリ。外付けキーボードでシステム IME に依存せず日本語入力を実現する。

ローマ字・AZIK・月配列・NICOLA・薙刀式など、逐次入力と同時打鍵の両方をデータ駆動でサポートする。

## 特徴

- **データ駆動のキーマップ**: JSON ファイルで入力方式を定義。コード変更なしで配列を追加・カスタマイズ可能
- **逐次入力 + 同時打鍵**: ローマ字系（sequential）と NICOLA/薙刀式系（chord）を統一的に扱う
- **かな漢字変換**: [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) による辞書ベース変換。Zenzai（ニューラル変換）も DI で有効化可能
- **UITextView サブクラス**: `pressesBegan` でキー入力を横取りし、`setMarkedText` で未確定文字列を表示
- **SwiftUI 対応**: `IMETextViewRepresentable` で SwiftUI から利用可能

## 要件

- iPadOS 18.0+
- Swift 6.1+

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/msonrm/KeyLogicKit", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "KeyLogicKit", package: "KeyLogicKit")
        ]
    ),
]
```

## 基本的な使い方

### 最小構成

```swift
import SwiftUI
import KeyLogicKit

struct EditorView: View {
    @State private var inputManager = InputManager()
    @State private var keyRouter = KeyRouter(definition: DefaultKeymaps.romajiUS)

    var body: some View {
        IMETextViewRepresentable(
            inputManager: inputManager,
            keyRouter: keyRouter
        )
    }
}
```

### キーマップの切替

`KeymapManager` で組み込み・カスタムキーマップを統一管理できる。

```swift
@State private var keymapManager = KeymapManager()

// 選択中のキーマップを適用
func applyKeymap() {
    guard let definition = keymapManager.loadSelectedDefinition() else { return }
    keyRouter = KeyRouter(definition: definition)
    inputManager.updateInputMappings(definition.inputMappings)
    switch definition.behavior {
    case .sequential:
        inputManager.inputMethod = .sequential
    case .chord:
        inputManager.inputMethod = .chord(name: definition.name)
    }
}
```

### アプリ固有のキーマップを追加する

`KeymapManagerConfiguration` で、アプリ独自のキーマップを組み込みとして登録できる。

```swift
// アプリの Bundle から JSON キーマップを読み込み
let data = try Data(contentsOf: Bundle.main.url(forResource: "my_layout", withExtension: "json")!)
let myLayout = try KeymapStore.decode(from: data)

// 設定付きで初期化
let config = KeymapManagerConfiguration(
    additionalKeymaps: [("builtin:my_layout", myLayout)],
    defaultKeymapID: "builtin:my_layout"
)
@State var keymapManager = KeymapManager(configuration: config)
```

デフォルトの `KeymapManager()` は KeyLogicKit 組み込みキーマップ（ローマ字・AZIK・月配列・NICOLA）を全て含む。

## 組み込みキーマップ

| ID | 名前 | 方式 | 配列 |
|---|---|---|---|
| `builtin:romaji_us` | ローマ字(US) | 逐次 | US |
| `builtin:azik_us` | AZIK(US) | 逐次 | US |
| `builtin:tsuki2-263_us` | 月配列2-263(US) | 逐次 | US |
| `builtin:nicola_us` | NICOLA(US) | 同時打鍵 | US |
| `builtin:nicola_jis` | NICOLA(JIS) | 同時打鍵 | JIS |

## キーマップ JSON フォーマット

キーマップは [JSON フォーマット仕様 v1](docs/keymap-format.md) で定義する。[JSON Schema](docs/keymap-v1.schema.json) によるバリデーションも可能。

逐次入力の例（最小構成）:

```json
{
  "formatVersion": "1.0",
  "name": "My Layout",
  "keyboardLayout": "us",
  "behavior": {
    "type": "sequential",
    "characterMap": { ",": "、", ".": "。" }
  },
  "inputMappings": {
    "ka": "か", "ki": "き", "ku": "く"
  }
}
```

`inputBase: "romaji"` を指定すると標準ローマ字テーブルをベースに差分だけ定義できる（AZIK 等）。

## アーキテクチャ

```
KeyLogicKit
├── Editor/
│   ├── IMETextView              # UITextView サブクラス（キー入力横取り）
│   └── IMETextViewRepresentable # SwiftUI ラッパー
├── IME/
│   ├── InputManager             # 変換管理（@Observable）
│   ├── KeyRouter                # キーイベント → KeyAction 変換
│   ├── KeyAction                # IME アクション enum
│   ├── KeymapDefinition         # キーマップ定義データ構造
│   ├── KeymapManager            # キーマップ選択・永続化
│   ├── KeymapStore              # JSON エンコード/デコード・ファイル I/O
│   ├── DefaultKeymaps           # 組み込みキーマップ定義
│   ├── ChordKey                 # 同時打鍵キー識別子
│   └── SimultaneousKeyBuffer    # 同時打鍵バッファ
└── Resources/Keymaps/           # 組み込みキーマップ JSON
```

### キー入力フロー

1. `IMETextView.pressesBegan` でハードウェアキーイベントを横取り
2. `KeyRouter.route()` が `KeymapDefinition` に基づいて `KeyAction` に変換
3. `IMETextView.executeAction()` が `InputManager` を通じて変換処理を実行
4. `InputManager` が AzooKeyKanaKanjiConverter でかな漢字変換

## Zenzai（ニューラル変換）の有効化

デフォルトは辞書ベース変換のみ。Zenzai を有効化するには:

```swift
let inputManager = InputManager()
inputManager.zenzaiWeightURL = Bundle.main.url(
    forResource: "ggml-model-Q5_K_M", withExtension: "gguf"
)
```

アプリの `Package.swift` で `traits: ["ZenzaiCPU"]` を指定すること。

## ライセンス

MIT License
