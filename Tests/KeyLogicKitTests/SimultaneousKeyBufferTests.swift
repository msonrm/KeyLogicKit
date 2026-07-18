import XCTest
import KeyLogicKit

/// SimultaneousKeyBuffer（同時打鍵バッファ）の4状態FSMのユニットテスト
///
/// タイミング意味論（`CFAbsoluteTimeGetCurrent` 実時間）:
/// - chord（`simultaneousWindow` 内の2キー目）は連続 keyDown で再現（sleep 不要・数μs で window 内）
/// - ロールオーバー（inter-key timing 超過）のみ実スリープで再現する
/// - chord 系は `simultaneousWindow` を 1.0 秒と大きく取り、連続 keyDown が確実に window 内へ収まるようにする
@MainActor
final class SimultaneousKeyBufferTests: XCTestCase {

    /// onOutput の記録用（`KeyAction` は非 Equatable なので Output は自前 Equatable）
    private struct Output: Equatable {
        let text: String
        let replaceCount: Int
    }

    /// テスト用にコールバックを配線したバッファを作る
    private func makeBuffer(
        window: TimeInterval = 1.0,
        lookup: @escaping (UInt64) -> String?,
        special: @escaping (UInt64) -> KeyAction? = { _ in nil },
        shiftKeys: [ChordKey: KeyAction?] = [:],
        outputs: @escaping (Output) -> Void,
        specials: @escaping (KeyAction) -> Void = { _ in },
        shiftSingles: @escaping (KeyAction) -> Void = { _ in }
    ) -> SimultaneousKeyBuffer {
        let buffer = SimultaneousKeyBuffer()
        buffer.simultaneousWindow = window
        buffer.lookupFunction = lookup
        buffer.specialActionFunction = special
        buffer.shiftKeyConfigs = shiftKeys
        buffer.onOutput = { text, count in outputs(Output(text: text, replaceCount: count)) }
        buffer.onSpecialAction = { specials($0) }
        buffer.onShiftSingle = { shiftSingles($0) }
        return buffer
    }

    // MARK: - 単打

    func testSingleTap() {
        var outputs: [Output] = []
        let buffer = makeBuffer(
            lookup: { $0 == ChordKey.A.bit ? "あ" : nil },
            outputs: { outputs.append($0) }
        )
        buffer.keyDown(.A)
        buffer.keyUp(.A)  // 全キーリリース → finalize で単打出力
        XCTAssertEqual(outputs, [Output(text: "あ", replaceCount: 0)])
    }

    // MARK: - 2キー chord

    func testTwoKeyChord() {
        var outputs: [Output] = []
        let ab = ChordKey.A.bit | ChordKey.B.bit
        let buffer = makeBuffer(
            lookup: { bits in
                if bits == ChordKey.A.bit { return "あ" }
                if bits == ChordKey.B.bit { return "い" }
                if bits == ab { return "ぶ" }
                return nil
            },
            outputs: { outputs.append($0) }
        )
        // window 内に2キー目 → 2キー目の keyDown で即 chord 出力（差し替えなし）
        buffer.keyDown(.A)
        buffer.keyDown(.B)
        buffer.keyUp(.B)
        buffer.keyUp(.A)
        XCTAssertEqual(outputs, [Output(text: "ぶ", replaceCount: 0)])
    }

    // MARK: - 3キー chord（差し替え）

    func testThreeKeyChordReplace() {
        var outputs: [Output] = []
        let ab = ChordKey.A.bit | ChordKey.B.bit
        let abc = ab | ChordKey.C.bit
        let buffer = makeBuffer(
            lookup: { bits in
                if bits == ab { return "に" }
                if bits == abc { return "ぬ" }
                return nil
            },
            outputs: { outputs.append($0) }
        )
        buffer.keyDown(.A)
        buffer.keyDown(.B)   // A+B = "に" を出力
        buffer.keyDown(.C)   // A+B+C = "ぬ" に差し替え（replaceCount=1）
        buffer.keyUp(.C)
        buffer.keyUp(.B)
        buffer.keyUp(.A)
        XCTAssertEqual(outputs, [
            Output(text: "に", replaceCount: 0),
            Output(text: "ぬ", replaceCount: 1),
        ])
    }

    // MARK: - ロールオーバー（inter-key timing 超過）

    func testRolloverSplitsIntoSingles() {
        var outputs: [Output] = []
        let ab = ChordKey.A.bit | ChordKey.B.bit
        let buffer = makeBuffer(
            window: 0.2,
            lookup: { bits in
                if bits == ChordKey.A.bit { return "あ" }
                if bits == ChordKey.B.bit { return "い" }
                if bits == ab { return "ぶ" }
                return nil
            },
            outputs: { outputs.append($0) }
        )
        // A を押し、window(0.2) を超えてから B を押す → chord 不成立、各キー単打
        buffer.keyDown(.A)
        Thread.sleep(forTimeInterval: 0.35)
        buffer.keyDown(.B)   // ロールオーバー検出: 先行キー A を単打出力
        buffer.keyUp(.B)
        buffer.keyUp(.A)     // finalize: B を単打出力
        XCTAssertEqual(outputs, [
            Output(text: "あ", replaceCount: 0),
            Output(text: "い", replaceCount: 0),
        ])
    }

    // MARK: - idle ゲーティング（タイピングストリーク → passthrough）

    func testIdleGatingPassthrough() {
        var outputs: [Output] = []
        let bc = ChordKey.B.bit | ChordKey.C.bit
        let buffer = makeBuffer(
            lookup: { bits in
                if bits == ChordKey.A.bit { return "あ" }
                if bits == ChordKey.B.bit { return "い" }
                if bits == ChordKey.C.bit { return "う" }
                if bits == bc { return "ぶ" }   // B+C は chord だが passthrough 中は評価されない
                return nil
            },
            outputs: { outputs.append($0) }
        )
        // 単打 A を確定（lastFinalizedTime を設定）
        buffer.keyDown(.A)
        buffer.keyUp(.A)   // → "あ"、resetAll で lastFinalizedTime=now
        // 直後（window*2 以内）に B, C → ストリーク中なので chord 評価せず即単打
        buffer.keyDown(.B)   // isInTypingStreak=true → passthrough で単打 "い"
        buffer.keyDown(.C)   // passthrough → 単打 "う"（B+C chord にはならない）
        buffer.keyUp(.C)
        buffer.keyUp(.B)
        XCTAssertEqual(outputs, [
            Output(text: "あ", replaceCount: 0),
            Output(text: "い", replaceCount: 0),
            Output(text: "う", replaceCount: 0),
        ])
    }

    // MARK: - 特殊アクション単打

    func testSpecialActionSingleTap() {
        var specials: [KeyAction] = []
        let buffer = makeBuffer(
            lookup: { _ in nil },
            special: { $0 == ChordKey.U.bit ? .deleteBack : nil },
            outputs: { _ in },
            specials: { specials.append($0) }
        )
        buffer.keyDown(.U)
        buffer.keyUp(.U)   // finalize → 単打で特殊アクション発火
        XCTAssertEqual(specials.count, 1)
        guard case .deleteBack = specials.first else {
            XCTFail("deleteBack が発火するべき")
            return
        }
    }

    // MARK: - センターシフト（シフト+キーの同時打鍵）

    func testCenterShiftChord() {
        var outputs: [Output] = []
        let shiftA = ChordKey.space.bit | ChordKey.A.bit
        let buffer = makeBuffer(
            lookup: { $0 == shiftA ? "シフトA" : nil },
            shiftKeys: [.space: .convert],   // space はシフトキー（単打で convert）
            outputs: { outputs.append($0) }
        )
        buffer.keyDown(.space)   // シフトキー
        buffer.keyDown(.A)       // space+A = シフト面 "シフトA" を即出力
        buffer.keyUp(.A)
        buffer.keyUp(.space)
        XCTAssertEqual(outputs, [Output(text: "シフトA", replaceCount: 0)])
    }

    // MARK: - シフトキー単打（フォールバックアクション）

    func testShiftKeySingleTapFallback() {
        var shiftSingles: [KeyAction] = []
        let buffer = makeBuffer(
            lookup: { _ in nil },
            shiftKeys: [.space: .convert],
            outputs: { _ in },
            shiftSingles: { shiftSingles.append($0) }
        )
        buffer.keyDown(.space)
        buffer.keyUp(.space)   // シフトキー単打 → フォールバック convert
        XCTAssertEqual(shiftSingles.count, 1)
        guard case .convert = shiftSingles.first else {
            XCTFail("convert が発火するべき")
            return
        }
    }

    // MARK: - 相互シフト（judgment == .mutual）

    /// A=あ, B=い, C=う, A+B=ば, A+C=ぼ, A+B+C=みゃ のテーブル
    private func mutualLookup(_ bits: UInt64) -> String? {
        let a = ChordKey.A.bit, b = ChordKey.B.bit, c = ChordKey.C.bit
        switch bits {
        case a: return "あ"
        case b: return "い"
        case c: return "う"
        case a | b: return "ば"
        case a | c: return "ぼ"
        case a | b | c: return "みゃ"
        default: return nil
        }
    }

    func testMutualChordIgnoresTiming() {
        var outputs: [Output] = []
        let buffer = makeBuffer(
            window: 0.001,   // window 方式ならロールオーバーになる極小窓
            lookup: { self.mutualLookup($0) },
            outputs: { outputs.append($0) }
        )
        buffer.judgment = .mutual
        buffer.keyDown(.A)
        Thread.sleep(forTimeInterval: 0.02)   // 窓を大きく超えて2キー目
        buffer.keyDown(.B)
        buffer.keyUp(.B)
        buffer.keyUp(.A)
        // 時間に関係なく chord: ば のみ（単打 あ/い は出ない）
        XCTAssertEqual(outputs, [Output(text: "ば", replaceCount: 0)])
    }

    func testMutualContinuousChord() {
        var outputs: [Output] = []
        let buffer = makeBuffer(
            lookup: { self.mutualLookup($0) },
            outputs: { outputs.append($0) }
        )
        buffer.judgment = .mutual
        // A 押しっぱなしで B → C（連続シフトの一般化）
        buffer.keyDown(.A)
        buffer.keyDown(.B)   // A+B = ば
        buffer.keyUp(.B)     // 部分リリース → 出力コミット、A は armed のまま
        buffer.keyDown(.C)   // A+C = ぼ（追記。差し替えではない）
        buffer.keyUp(.C)
        buffer.keyUp(.A)     // A は消費済み → 単打 あ は出ない
        XCTAssertEqual(outputs, [
            Output(text: "ば", replaceCount: 0),
            Output(text: "ぼ", replaceCount: 0),
        ])
    }

    func testMutualThreeKeyReplaceThenAppend() {
        var outputs: [Output] = []
        let buffer = makeBuffer(
            lookup: { self.mutualLookup($0) },
            outputs: { outputs.append($0) }
        )
        buffer.judgment = .mutual
        buffer.keyDown(.A)
        buffer.keyDown(.B)   // ば
        buffer.keyDown(.C)   // A+B+C = みゃ（ば を差し替え）
        buffer.keyUp(.C)     // コミット
        buffer.keyDown(.C)   // 再打鍵 → A+B+C = みゃ を追記
        buffer.keyUp(.C)
        buffer.keyUp(.B)
        buffer.keyUp(.A)
        XCTAssertEqual(outputs, [
            Output(text: "ば", replaceCount: 0),
            Output(text: "みゃ", replaceCount: 1),   // ば(1文字)を差し替え
            Output(text: "みゃ", replaceCount: 0),   // 追記
        ])
    }

    func testMutualFallthroughDisarm() {
        var outputs: [Output] = []
        let buffer = makeBuffer(
            lookup: { bits in
                let a = ChordKey.A.bit, b = ChordKey.B.bit, c = ChordKey.C.bit
                switch bits {
                case a: return "あ"
                case b: return "い"
                case c: return "う"
                case a | b: return "ば"   // A+B のみ定義（A+C は未定義）
                default: return nil
                }
            },
            outputs: { outputs.append($0) }
        )
        buffer.judgment = .mutual
        buffer.keyDown(.A)
        buffer.keyDown(.C)   // A+C 未定義 → fall-through: あ を単打解決、A は disarm
        buffer.keyUp(.C)
        buffer.keyDown(.B)   // A は押下中だが disarm 済み → A+B=ば は成立しない
        buffer.keyUp(.B)
        buffer.keyUp(.A)     // 解決済みの A から単打は出ない
        XCTAssertEqual(outputs, [
            Output(text: "あ", replaceCount: 0),   // fall-through で解決
            Output(text: "う", replaceCount: 0),   // C の単打（B down 時に解決）
            Output(text: "い", replaceCount: 0),   // B の単打（finalize）
        ])
    }

    func testMutualShiftKeyConsumedNoSingleAction() {
        var outputs: [Output] = []
        var shiftSingles: [KeyAction] = []
        let shiftA = ChordKey.space.bit | ChordKey.A.bit
        let buffer = makeBuffer(
            lookup: { bits in
                if bits == shiftA { return "の" }
                return self.mutualLookup(bits)
            },
            shiftKeys: [.space: .convert],
            outputs: { outputs.append($0) },
            shiftSingles: { shiftSingles.append($0) }
        )
        buffer.judgment = .mutual
        buffer.keyDown(.space)
        buffer.keyDown(.A)     // space+A = の
        buffer.keyUp(.space)   // シフトキーを先に離しても
        buffer.keyUp(.A)
        XCTAssertEqual(outputs, [Output(text: "の", replaceCount: 0)])
        XCTAssertTrue(shiftSingles.isEmpty, "消費済みシフトキーの単打アクションは発火しない")
    }

    func testMutualPendingSpecialFiresOnPartialRelease() {
        var outputs: [Output] = []
        var specials: [KeyAction] = []
        let ab = ChordKey.A.bit | ChordKey.B.bit
        let buffer = makeBuffer(
            lookup: { bits in
                if bits == ChordKey.A.bit { return "あ" }
                if bits == ChordKey.B.bit { return "い" }
                return nil
            },
            special: { $0 == ab ? .confirm : nil },
            outputs: { outputs.append($0) },
            specials: { specials.append($0) }
        )
        buffer.judgment = .mutual
        buffer.keyDown(.A)
        buffer.keyDown(.B)   // A+B = specialAction（3キー目の可能性があるため保留）
        buffer.keyUp(.B)     // 部分リリース → 保留アクション発火
        XCTAssertEqual(specials.count, 1)
        buffer.keyUp(.A)     // 消費済み → 単打なし
        XCTAssertTrue(outputs.isEmpty)
        XCTAssertEqual(specials.count, 1)
    }

    /// 部分リリースで発火した specialAction のコールバックが reset() を再入的に呼んでも
    /// （IMETextView の switchToEnglish 等が該当）、後続打鍵の単打が抑制されないこと。
    /// 修正前は発火後に stale な chordOutputted=true が残り、次の 1 打鍵が消失していた。
    func testMutualReentrantResetDoesNotSwallowNextTap() {
        var outputs: [Output] = []
        var specialCount = 0
        let fg = ChordKey.F.bit | ChordKey.G.bit
        var buffer: SimultaneousKeyBuffer!
        buffer = makeBuffer(
            lookup: { self.mutualLookup($0) },
            special: { $0 == fg ? .switchToEnglish : nil },
            outputs: { outputs.append($0) },
            specials: { _ in
                specialCount += 1
                buffer.reset()   // executeAction(.switchToEnglish) の chordBuffer.reset() を再現
            }
        )
        buffer.judgment = .mutual
        buffer.keyDown(.F)
        buffer.keyDown(.G)   // F+G → specialAction 保留
        buffer.keyUp(.F)     // 部分リリース → 発火（コールバックが reset を再入）
        buffer.keyDown(.A)   // G リリース前の次打鍵（ロールオーバー）
        buffer.keyUp(.G)
        buffer.keyUp(.A)     // A の単打が抑制されないこと
        XCTAssertEqual(specialCount, 1)
        XCTAssertEqual(outputs, [Output(text: "あ", replaceCount: 0)])
    }
}
