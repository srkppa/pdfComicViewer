import AppKit

enum SidebarRowInteraction {
    /// ⌘・⇧ クリックはListの複数選択を広げる操作なので、
    /// 行タップで開く動作に横取りさせない。
    /// 修飾なしのクリックだけを「開く」として扱う。
    static func shouldOpenPDF(modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection([.command, .shift]).isEmpty
    }
}
