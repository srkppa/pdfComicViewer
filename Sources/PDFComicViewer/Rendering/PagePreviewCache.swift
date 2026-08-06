import AppKit
import PDFKit

actor PagePreviewCache {
    private var images: [Int: CGImage] = [:]

    func insert(_ image: CGImage, for pageIndex: Int) {
        images[pageIndex] = image
    }

    func image(for pageIndex: Int) -> CGImage? {
        images[pageIndex]
    }

    func retainOnly(_ indexes: Set<Int>) {
        images = images.filter { indexes.contains($0.key) }
    }
}

@MainActor
enum PagePreviewRenderer {
    static func render(page: PDFPage, maxSize: CGSize) -> CGImage? {
        let thumbnail = page.thumbnail(of: maxSize, for: .cropBox)
        return thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
