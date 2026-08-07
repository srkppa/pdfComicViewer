import CoreGraphics

/// ディレクトリサイドバーのドラッグリサイズに関する純粋な計算ロジック。
enum SidebarResizing {
    static let minimumWidth: CGFloat = 200
    static let maximumWidth: CGFloat = 480

    static func width(startingWidth: CGFloat, translation: CGFloat) -> CGFloat {
        min(max(startingWidth + translation, minimumWidth), maximumWidth)
    }
}
