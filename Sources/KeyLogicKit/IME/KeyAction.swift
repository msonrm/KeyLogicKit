import UIKit

/// IME が実行するアクション（入力方式に依存しない統一表現）
///
/// キーイベントを受け取った後、KeyRouter がこの enum に変換する。
/// IMETextView は KeyAction を受け取って実行するだけで、
/// 入力方式やキーボードレイアウトの詳細を知る必要がない。
public enum KeyAction: Sendable {

    // MARK: - 文字入力

    /// 逐次入力の文字（h2zMap / ローマ字変換で処理）
    case printable(Character)

    // MARK: - 変換操作

    /// 変換リクエスト / 次の候補（Space）
    case convert

    /// 前の候補（Shift+Space）
    case convertPrev

    /// 確定（Enter / Tab）
    case confirm

    /// キャンセル（Escape）— selecting 時は composing に戻る
    case cancel

    /// 1文字削除（Backspace）
    case deleteBack

    // MARK: - カーソル・文節操作

    /// 左矢印 — selecting 時は消費のみ（macOS 標準準拠）
    case moveLeft

    /// 右矢印 — selecting 時は確定
    case moveRight

    /// 上矢印 — selecting 時は前の候補
    case moveUp

    /// 下矢印 — selecting 時は次の候補、composing 時は変換開始
    case moveDown

    /// 文節区切りを左に縮小（Shift+← / Ctrl+I）
    case editSegmentLeft

    /// 文節区切りを右に拡大（Shift+→ / Ctrl+O）
    case editSegmentRight

    /// 候補ウィンドウ内のオフセットで直接選択（1-9 キー）
    case selectCandidate(Int)

    // MARK: - 変換形式指定確定

    /// ひらがな確定（Ctrl+J）
    case confirmHiragana

    /// カタカナ確定（Ctrl+K）
    case confirmKatakana

    /// 半角カタカナ確定（Ctrl+L）— macOS 標準（ことえり）準拠
    case confirmHalfWidthKatakana

    /// 全角英数確定（Ctrl+;）
    case confirmFullWidthRoman

    /// 半角英数確定（Ctrl+:）— macOS 標準（ことえり）準拠
    case confirmHalfWidthRoman

    // MARK: - 同時打鍵バッファ投入（chord 方式のみ）

    /// 文字キーを同時打鍵バッファに投入
    case chordInput(ChordKey)

    /// シフトキーを同時打鍵バッファに投入（センターシフト / 親指シフト）
    case chordShiftDown(ChordKey)

    // MARK: - 同時打鍵特殊アクション

    /// 文字列を挿入して即確定（句読点等。composing 中は先に確定してから挿入）
    case insertAndConfirm(String)

    /// chord 英数モードへ切替（F+G 等）
    case chordModeOff

    /// chord モードへ復帰（H+J 等）
    case chordModeOn

    // MARK: - 英数直接入力（chord 方式の英数モード）

    /// 英数モードの印字可能文字を直接挿入
    case directInsert(String)

    // MARK: - パススルー

    /// super.pressesBegan に委譲（IME で処理しない）
    case pass
}
