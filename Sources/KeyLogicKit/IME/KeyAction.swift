import Foundation

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

    // MARK: - 入力モード切替

    /// 英数直接入力モードへ切替（composing 中は確定してから切替）
    case switchToEnglish

    /// 日本語入力モードへ復帰
    case switchToJapanese

    /// 日本語↔英数モードをトグル（CAPS LOCK 等に割当可能）
    case toggleInputMode

    // MARK: - 英数直接入力

    /// 英数モードの印字可能文字を直接挿入
    case directInsert(String)

    // MARK: - 文ナビゲーション（Option+矢印、idle 時のみ）

    /// 文頭へ移動（Option+←）— 既に文頭なら前の文の文頭へ
    case moveSentenceStart

    /// 文末へ移動（Option+→）— 既に文末なら次の文の文末へ
    case moveSentenceEnd

    /// 選択中の文を前の文と入れ替え（Option+↑）
    case swapSentenceUp

    /// 選択中の文を次の文と入れ替え（Option+↓）
    case swapSentenceDown

    // MARK: - スマート選択（Shift+Option+矢印、idle 時のみ）

    /// スマート選択を拡大（Shift+Option+→）— カッコ内→カッコ含む→文→ブロック
    case smartSelectExpand

    /// スマート選択を縮小（Shift+Option+←）— 拡大の逆
    case smartSelectShrink

    /// 文選択を上に拡張（Shift+Option+↑）— 未選択なら現在の文を選択
    case selectSentenceUp

    /// 文選択を下に拡張（Shift+Option+↓）— 未選択なら現在の文を選択
    case selectSentenceDown

    // MARK: - パススルー

    /// super.pressesBegan に委譲（IME で処理しない）
    case pass
}
