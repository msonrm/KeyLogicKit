/// アンドゥ可能な外部テキスト編集リクエスト。
///
/// App Intent 等からプログラム的にテキストを変更する際、
/// `IMETextViewRepresentable` の `undoableEdit` Binding にセットすると
/// `undoManager` に登録され Cmd+Z で元に戻せる。
public struct UndoableEdit: Equatable {
    /// 変更後のテキスト全体
    public let text: String
    /// 変更後のカーソル位置（UTF-16 offset）
    public let cursorLocation: Int
    /// 変更後の選択長（UTF-16 単位、通常 0）
    public let selectionLength: Int

    public init(text: String, cursorLocation: Int, selectionLength: Int = 0) {
        self.text = text
        self.cursorLocation = cursorLocation
        self.selectionLength = selectionLength
    }
}
