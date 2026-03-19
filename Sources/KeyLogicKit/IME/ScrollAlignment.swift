/// `scrollRevision` によるプログラム的スクロール時のカーソル配置方法
public enum ScrollAlignment {
    /// 最小限のスクロール（デフォルト、`scrollRangeToVisible` + `enforceScrolloff`）
    case minimal
    /// カーソルを上端から `scrollOffLines` 行目に配置
    case top
}
