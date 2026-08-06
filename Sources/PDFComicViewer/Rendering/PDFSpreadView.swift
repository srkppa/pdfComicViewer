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
        case .zoomIn:
            canvas.discardPreviews()
            setMagnification(scrollView.magnification * 1.25, on: scrollView)
        case .zoomOut:
            canvas.discardPreviews()
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
private final class SpreadScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let canvas = documentView as? SpreadCanvasView else { return }
        canvas.relayout(to: contentSize)
    }
}
