import AppKit
import PDFKit

@MainActor
final class SpreadCanvasView: NSView {
    private let gutter: CGFloat = 12
    private var document: PDFDocument
    private var placement: PagePlacement
    private var pages: [PDFPage] = []
    private var pageFrames: [CGRect] = []

    init(document: PDFDocument, placement: PagePlacement) {
        self.document = document
        self.placement = placement
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = ReaderTheme.canvasNSColor.cgColor
        reloadPages()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    func update(document: PDFDocument, placement: PagePlacement) {
        guard self.document !== document || self.placement != placement else { return }
        self.document = document
        self.placement = placement
        reloadPages()
        relayoutPages()
        needsDisplay = true
    }

    func relayout(to viewport: CGSize) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        if frame.size != viewport {
            setFrameSize(viewport)
        }
        relayoutPages()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(ReaderTheme.canvasNSColor.cgColor)
        context.fill(dirtyRect)

        for (page, pageFrame) in zip(pages, pageFrames) where pageFrame.intersects(dirtyRect) {
            draw(page, in: pageFrame, context: context)
        }
    }

    private func reloadPages() {
        let indexes: [Int?]
        if let centered = placement.centered {
            indexes = [centered]
        } else {
            indexes = [placement.left, placement.right]
        }
        pages = indexes.compactMap { index in
            guard let index, document.pageCount > index, index >= 0 else { return nil }
            return document.page(at: index)
        }
    }

    private func relayoutPages() {
        pageFrames = SpreadLayoutCalculator.frames(
            pageSizes: pages.map { displayedSize(of: $0) },
            viewport: bounds.size,
            gutter: gutter
        )
        needsDisplay = true
    }

    private func displayedSize(of page: PDFPage) -> CGSize {
        let cropBox = page.bounds(for: .cropBox)
        switch normalizedRotation(of: page) {
        case 90, 270:
            return CGSize(width: cropBox.height, height: cropBox.width)
        default:
            return cropBox.size
        }
    }

    private func draw(_ page: PDFPage, in frame: CGRect, context: CGContext) {
        let cropBox = page.bounds(for: .cropBox)
        let pageSize = displayedSize(of: page)
        guard cropBox.width > 0, cropBox.height > 0,
              pageSize.width > 0, pageSize.height > 0 else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(frame)
        context.clip(to: frame)
        context.translateBy(x: frame.minX, y: frame.minY)
        context.scaleBy(
            x: frame.width / pageSize.width,
            y: frame.height / pageSize.height
        )
        page.draw(with: .cropBox, to: context)
    }

    private func normalizedRotation(of page: PDFPage) -> Int {
        (page.rotation % 360 + 360) % 360
    }
}
