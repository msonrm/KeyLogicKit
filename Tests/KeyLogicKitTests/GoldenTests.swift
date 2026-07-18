import XCTest
import KeyLogicKit

/// ゴールデンテスト・ランナー（Swift/KeyLogicKit 実装）
///
/// `Tests/golden/cases/*.json` を読み、KeyRouter → InputManager / SimultaneousKeyBuffer の
/// 実パイプラインに入力して期待かな出力を検証する。形式仕様: `Tests/golden/README.md`
///
/// タイミング意味論:
/// - SimultaneousKeyBuffer は実時間（CFAbsoluteTimeGetCurrent）で inter-key timing と
///   idle ゲーティングを判定するため、`wait` ステップは実スリープで再現する。
/// - ケースごとに新しいバッファを作るので、ケース間のストリーク持ち越しはない。
///
/// ゴールデンのスコープはかな解決まで（かな漢字変換は含まない）。そのため
/// `.convert`（composing 中）は requestConversion ではなく confirmAll として扱う
/// （web ランナーの InputEngine と同じ意味論）。
@MainActor
final class GoldenTests: XCTestCase {

    // MARK: - フィクスチャ型

    private struct GoldenFixture: Decodable {
        let keymap: String
        let description: String?
        let cases: [GoldenCase]
    }

    private struct GoldenCase: Decodable {
        let name: String
        let description: String?
        let skip: [String]?
        let steps: [GoldenStep]
        let expect: GoldenExpect
    }

    /// このランナーのプラットフォーム ID（fixture の skip と照合）
    private static let platform = "swift"

    private struct GoldenStep: Decodable {
        let press: String?
        let down: String?
        let up: String?
        let chord: [String]?
        let wait: Double?
        let char: String?
        let modifiers: [String]?
    }

    private struct GoldenExpect: Decodable {
        let text: String?
        let confirmed: String?
        let composing: String?
    }

    // MARK: - コーパスの場所

    /// Tests/golden/cases（#filePath の 1 階層上が Tests/）
    ///
    /// コーパスは Swift の `Tests/` 配下に置く。ルートに `tests/`（小文字）を併存させると
    /// macOS の大文字小文字非区別ファイルシステムで `Tests/` と衝突するため。
    private static let casesDirectory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // Tests/KeyLogicKitTests
        url.deleteLastPathComponent() // Tests
        return url.appendingPathComponent("golden/cases")
    }()

    /// InputManager は辞書ロードが重いのでプロセス内で共有する
    private static var sharedManager: InputManager?

    private func manager() -> InputManager {
        if let m = Self.sharedManager { return m }
        let m = InputManager()
        Self.sharedManager = m
        return m
    }

    // MARK: - テスト本体

    func testGoldenCorpus() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.casesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "コーパスが見つからない: \(Self.casesDirectory.path)")

        for file in files {
            let data = try Data(contentsOf: file)
            let fixture = try JSONDecoder().decode(GoldenFixture.self, from: data)
            guard let definition = loadDefinition(fixture.keymap) else {
                XCTFail("キーマップをロードできない: \(fixture.keymap)")
                continue
            }

            for testCase in fixture.cases {
                if testCase.skip?.contains(Self.platform) == true { continue }
                let label = "\(file.lastPathComponent) / \(testCase.name)"
                let harness = GoldenHarness(definition: definition, inputManager: manager())
                try runSteps(harness, testCase.steps)

                let composing = harness.inputManager.rawKanaText
                if let text = testCase.expect.text {
                    XCTAssertEqual(harness.confirmedText + composing, text, label)
                }
                if let confirmed = testCase.expect.confirmed {
                    XCTAssertEqual(harness.confirmedText, confirmed, label)
                }
                if let expectComposing = testCase.expect.composing {
                    XCTAssertEqual(composing, expectComposing, label)
                }
            }
        }
    }

    // MARK: - ステップ実行

    private func runSteps(_ harness: GoldenHarness, _ steps: [GoldenStep]) throws {
        for step in steps {
            if let ms = step.wait {
                Thread.sleep(forTimeInterval: ms / 1000.0)
            } else if let name = step.press {
                let event = try Self.buildEvent(name, char: step.char, modifiers: step.modifiers)
                harness.keyDown(event)
                harness.keyUp(event)
            } else if let keys = step.chord {
                let events = try keys.map { try Self.buildEvent($0, char: nil, modifiers: nil) }
                for event in events { harness.keyDown(event) }
                for event in events.reversed() { harness.keyUp(event) }
            } else if let name = step.down {
                harness.keyDown(try Self.buildEvent(name, char: step.char, modifiers: step.modifiers))
            } else if let name = step.up {
                harness.keyUp(try Self.buildEvent(name, char: step.char, modifiers: step.modifiers))
            } else {
                XCTFail("不明なステップ")
            }
        }
    }

    // MARK: - KeyEvent 構築

    /// キー名 → KeyEvent.characters（US 配列・非シフト）
    private static let nameToChar: [String: String] = [
        "semicolon": ";",
        "comma": ",",
        "period": ".",
        "slash": "/",
        "hyphen": "-",
        "equal": "=",
        "quote": "'",
        "backquote": "`",
        "bracketLeft": "[",
        "bracketRight": "]",
        "backslash": "\\",
        "space": " ",
    ]

    private static func buildEvent(_ name: String, char: String?, modifiers: [String]?) throws -> KeyEvent {
        // ModeKeyTriggerCoding がキー名 → HIDKeyCode の変換を持っている
        guard let trigger = ModeKeyTriggerCoding.parse(name) else {
            throw GoldenError.unknownKey(name)
        }

        var flags: KeyModifierFlags = []
        for mod in modifiers ?? [] {
            switch mod {
            case "shift": flags.insert(.shift)
            case "ctrl": flags.insert(.control)
            case "alt": flags.insert(.alternate)
            case "meta": flags.insert(.command)
            default: throw GoldenError.unknownModifier(mod)
            }
        }

        let characters: String
        if let char {
            characters = char
        } else if name.count == 1 {
            characters = name
        } else {
            characters = Self.nameToChar[name] ?? ""
        }

        return KeyEvent(keyCode: trigger.keyCode, characters: characters, modifierFlags: flags)
    }

    private enum GoldenError: Error {
        case unknownKey(String)
        case unknownModifier(String)
    }

    private func loadDefinition(_ ref: String) -> KeymapDefinition? {
        switch ref {
        case "builtin:romaji_us": return DefaultKeymaps.romajiUS
        case "builtin:romaji_jis": return DefaultKeymaps.romajiJIS
        default: return DefaultKeymaps.loadBundleKeymap(ref)
        }
    }
}

// MARK: - ハーネス

/// IMETextView の executeAction 配線を UIKit 抜きで再現する最小ハーネス
@MainActor
private final class GoldenHarness {
    let inputManager: InputManager
    let keyRouter: KeyRouter
    let definition: KeymapDefinition
    let chordBuffer: SimultaneousKeyBuffer?
    var confirmedText = ""

    init(definition: KeymapDefinition, inputManager: InputManager) {
        self.definition = definition
        self.inputManager = inputManager
        self.keyRouter = KeyRouter(definition: definition)

        // ケース間の状態を掃除してからキーマップを適用
        _ = inputManager.cancelConversion()
        let expanded = ExpandedKeymap(definition: definition)
        inputManager.updateKeymap(expanded)

        if let chordData = expanded.chordData {
            let buffer = SimultaneousKeyBuffer()
            buffer.judgment = chordData.judgment
            buffer.simultaneousWindow = chordData.simultaneousWindow
            buffer.lookupFunction = { chordData.lookupTable[$0] }
            buffer.specialActionFunction = { chordData.specialActions[$0] }
            buffer.shiftKeyConfigs = chordData.shiftKeyConfigs
            self.chordBuffer = buffer
        } else {
            self.chordBuffer = nil
        }

        chordBuffer?.onOutput = { [weak self] text, replaceCount in
            guard let self else { return }
            if replaceCount > 0 {
                self.inputManager.replaceDirectKana(count: replaceCount, with: text)
            } else if !text.isEmpty {
                self.inputManager.appendDirectKana(text)
            }
        }
        chordBuffer?.onShiftSingle = { [weak self] action in
            self?.execute(action)
        }
        chordBuffer?.onSpecialAction = { [weak self] action in
            self?.execute(action)
        }
    }

    // MARK: イベント処理

    func keyDown(_ event: KeyEvent) {
        let action = keyRouter.route(
            event,
            isComposing: !inputManager.isEmpty,
            state: inputManager.state,
            isDirectEnglishMode: false
        )
        execute(action)
    }

    func keyUp(_ event: KeyEvent) {
        if case .chord(let config) = definition.behavior,
           let chordKey = config.hidToKey[event.keyCode] {
            chordBuffer?.keyUp(chordKey)
        }
    }

    private func execute(_ action: KeyAction) {
        switch action {
        case .printable(let c):
            guard case .sequential(let characterMap) = definition.behavior else { return }
            addPrintableToComposing(c, characterMap: characterMap)

        case .chordInput(let key):
            inputManager.recordChordKey(key)
            chordBuffer?.keyDown(key)

        case .chordShiftDown(let key):
            chordBuffer?.keyDown(key)

        case .convert:
            // ゴールデンのスコープはかな解決まで: 変換の代わりに確定する
            if !inputManager.isEmpty {
                confirmedText += inputManager.confirmAll()
            } else {
                confirmedText += inputManager.spaceCharacter(shifted: false)
            }

        case .confirm:
            confirmedText += inputManager.confirmAll()

        case .cancel:
            _ = inputManager.cancelConversion()

        case .deleteBack:
            if !inputManager.isEmpty {
                _ = inputManager.deleteBackward()
            } else if !confirmedText.isEmpty {
                confirmedText.removeLast()
            }

        case .insertSpace(let shifted):
            confirmedText += inputManager.spaceCharacter(shifted: shifted)

        case .insertAndConfirm(let text):
            inputManager.appendDirectKana(text)
            confirmedText += inputManager.confirmAll()

        case .directInsert(let text):
            confirmedText += text

        default:
            break
        }
    }

    /// IMETextView.addPrintableToComposing の再現（keyRemap → characterMap → カスタムテーブル）
    private func addPrintableToComposing(_ c: Character, characterMap: [Character: Character]) {
        let logical: Character
        if let remap = definition.keyRemap, let remapped = remap[String(c)]?.first {
            logical = remapped
        } else {
            logical = c
        }

        if let mapped = characterMap[logical] {
            inputManager.appendDirectKana(String(mapped))
        } else if inputManager.activeKeymap?.inputMappings != nil {
            inputManager.handleSequentialInput(String(logical))
        } else {
            inputManager.appendDirectKana(String(logical))
        }
    }
}
