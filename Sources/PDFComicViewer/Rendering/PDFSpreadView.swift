import AppKit
import PDFKit
import SwiftUI

@MainActor
struct PDFSpreadView: NSViewRepresentable {
    let document: PDFDocument
    let placement: PagePlacement
    let zoomCommand: ZoomCommand
    let pagePreviewSnapshot: PagePreviewSnapshot

    func makeCoordinator() -> Coordinator {
        Coordinator(initialZoomCommand: zoomCommand)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let canvas = SpreadCanvasView(
            document: document,
            placement: placement,
            previewImages: pagePreviewSnapshot.images,
            previewGeneration: pagePreviewSnapshot.generation,
            previewRevision: pagePreviewSnapshot.revision
        )
        let scrollView = SpreadScrollView()
        scrollView.documentView = canvas
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1
        scrollView.maxMagnification = 6
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = scrollView.documentView as? SpreadCanvasView else { return }
        canvas.update(
            document: document,
            placement: placement,
            previewImages: pagePreviewSnapshot.images,
            previewGeneration: pagePreviewSnapshot.generation,
            previewRevision: pagePreviewSnapshot.revision
        )
        canvas.relayout(to: scrollView.contentSize)

        guard context.coordinator.lastZoomCommand != zoomCommand else { return }
        context.coordinator.lastZoomCommand = zoomCommand
        apply(zoomCommand.action, to: scrollView, canvas: canvas)
    }

    private func apply(
        _ action: ZoomCommand.Action,
        to scrollView: NSScrollView,
        canvas: SpreadCanvasView
    ) {
        switch action {
        case .fit:
            scrollView.magnification = 1
            canvas.relayout(to: scrollView.contentSize)
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        case .zoomIn:
            canvas.disablePreviewsForZoom()
            setMagnification(scrollView.magnification * 1.25, on: scrollView)
        case .zoomOut:
            canvas.disablePreviewsForZoom()
            setMagnification(scrollView.magnification / 1.25, on: scrollView)
        }
    }

    private func setMagnification(_ magnification: CGFloat, on scrollView: NSScrollView) {
        let clamped = min(
            max(magnification, scrollView.minMagnification),
            scrollView.maxMagnification
        )
        let visibleCenter = CGPoint(
            x: scrollView.contentView.bounds.midX,
            y: scrollView.contentView.bounds.midY
        )
        scrollView.setMagnification(clamped, centeredAt: visibleCenter)
    }

    final class Coordinator {
        var lastZoomCommand: ZoomCommand

        init(initialZoomCommand: ZoomCommand) {
            lastZoomCommand = initialZoomCommand
        }
    }
}

@MainActor
final class SpreadScrollView: NSScrollView {
    private struct DragSession {
        let pointer: CGPoint
        let clipOrigin: CGPoint
    }

    private var dragSession: DragSession?

    override func layout() {
        super.layout()
        guard let canvas = documentView as? SpreadCanvasView else { return }
        canvas.relayout(to: contentSize)
    }

    override func keyDown(with event: NSEvent) {
        guard !ReaderInputMapping.shouldConsumeUnhandledKey(
            keyCode: event.keyCode,
            hasCommandOrControlOrOption: event.modifierFlags
                .intersection([.command, .control, .option])
                .isEmpty == false
        ) else { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        beginPageDrag(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        continuePageDrag(at: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        endPageDrag()
    }

    func beginPageDrag(at windowLocation: CGPoint) {
        dragSession = DragSession(
            pointer: convert(windowLocation, from: nil),
            clipOrigin: contentView.bounds.origin
        )
    }

    func continuePageDrag(at windowLocation: CGPoint) {
        guard let dragSession, let documentView else { return }
        let clipSize = contentView.bounds.size
        let documentBounds = documentView.bounds
        let maximumOrigin = CGPoint(
            x: documentBounds.maxX - clipSize.width,
            y: documentBounds.maxY - clipSize.height
        )
        let origin = ReaderDragPan.origin(
            startPointer: dragSession.pointer,
            currentPointer: convert(windowLocation, from: nil),
            startOrigin: dragSession.clipOrigin,
            maximumOrigin: maximumOrigin,
            magnification: magnification
        )
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }

    func endPageDrag() {
        dragSession = nil
    }
}
