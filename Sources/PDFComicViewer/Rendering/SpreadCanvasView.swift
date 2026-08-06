import AppKit
import PDFKit

@MainActor
final class SpreadCanvasView: NSView {
    private let gutter: CGFloat = 12
    private var document: PDFDocument
    private var placement: PagePlacement
    private var pages: [PDFPage] = []
    private var pageIndexes: [Int] = []
    private var pageFrames: [CGRect] = []
    private var previewImages: [Int: CGImage]
    private var previewGeneration: PagePreviewGeneration?
    private var previewRevision: Int
    private var discardedPreviewGeneration: PagePreviewGeneration?
    private var previewsDisabledForCurrentPresentation = false
    private var usesPreviews = false

    init(
        document: PDFDocument,
        placement: PagePlacement,
        previewImages: [Int: CGImage],
        previewGeneration: PagePreviewGeneration? = nil,
        previewRevision: Int = 0
    ) {
        self.document = document
        self.placement = placement
        self.previewImages = previewImages
        self.previewGeneration = previewGeneration
        self.previewRevision = previewRevision
        usesPreviews = !previewImages.isEmpty
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

    func update(
        document: PDFDocument,
        placement: PagePlacement,
        previewImages: [Int: CGImage],
        previewGeneration: PagePreviewGeneration?,
        previewRevision: Int
    ) {
        let presentationChanged = self.document !== document || self.placement != placement
        if presentationChanged {
            self.document = document
            self.placement = placement
            reloadPages()
            relayoutPages()
            discardPreviews()
            previewsDisabledForCurrentPresentation = false
            discardedPreviewGeneration = nil
        }
        guard self.previewGeneration != previewGeneration || self.previewRevision != previewRevision else {
            return
        }
        self.previewImages = previewImages
        self.previewGeneration = previewGeneration
        self.previewRevision = previewRevision
        usesPreviews = !previewImages.isEmpty
            && previewGeneration != discardedPreviewGeneration
            && !previewsDisabledForCurrentPresentation
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

        var usedPreview = false
        for ((pageIndex, page), pageFrame) in zip(zip(pageIndexes, pages), pageFrames)
            where pageFrame.intersects(dirtyRect) {
            let preview = previewImage(for: pageIndex)
            usedPreview = usedPreview || preview != nil
            draw(page, preview: preview, in: pageFrame, context: context)
        }
        if usedPreview {
            Task { @MainActor [weak self] in
                self?.discardPreviews()
            }
        }
    }

    func previewImage(for pageIndex: Int) -> CGImage? {
        guard usesPreviews else { return nil }
        return previewImages[pageIndex]
    }

    func discardPreviews() {
        discardedPreviewGeneration = previewGeneration
        guard usesPreviews else { return }
        usesPreviews = false
        previewImages = [:]
        needsDisplay = true
    }

    func disablePreviewsForZoom() {
        previewsDisabledForCurrentPresentation = true
        discardPreviews()
    }

    private func reloadPages() {
        let indexes: [Int?]
        if let centered = placement.centered {
            indexes = [centered]
        } else {
            indexes = [placement.left, placement.right]
        }
        pageIndexes = indexes.compactMap { index in
            guard let index, document.pageCount > index, index >= 0 else { return nil }
            return index
        }
        pages = pageIndexes.compactMap { index in
            guard document.pageCount > index, index >= 0 else { return nil }
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

    private func draw(
        _ page: PDFPage,
        preview: CGImage?,
        in frame: CGRect,
        context: CGContext
    ) {
        if let preview {
            context.saveGState()
            defer { context.restoreGState() }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(frame)
            context.interpolationQuality = .high
            context.draw(preview, in: frame)
            return
        }
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
