import CoreGraphics
import PDFKit
import XCTest
@testable import PDFComicViewer

@MainActor
final class PagePreviewRenderingTests: XCTestCase {
    func testCanvasUsesCurrentPlacementPreviewUntilItIsDiscarded() throws {
        let url = try PDFFixtureFactory.makePDF(
            pageSizes: [CGSize(width: 600, height: 900)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        let preview = makeImage(gray: 127)
        let canvas = SpreadCanvasView(
            document: document,
            placement: PagePlacement(left: nil, right: nil, centered: 0),
            previewImages: [0: preview]
        )

        XCTAssertNotNil(canvas.previewImage(for: 0))

        canvas.discardPreviews()

        XCTAssertNil(canvas.previewImage(for: 0))
    }

    func testCanvasAcceptsNewSnapshotRevisionForTheSameGeneration() throws {
        let url = try PDFFixtureFactory.makePDF(
            pageSizes: [CGSize(width: 600, height: 900)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        let generation = PagePreviewGeneration(documentID: UUID(), sequence: 1)
        let canvas = SpreadCanvasView(
            document: document,
            placement: PagePlacement(left: nil, right: nil, centered: 0),
            previewImages: [:],
            previewGeneration: generation,
            previewRevision: 1
        )

        canvas.update(
            document: document,
            placement: PagePlacement(left: nil, right: nil, centered: 0),
            previewImages: [0: makeImage(gray: 127)],
            previewGeneration: generation,
            previewRevision: 2
        )

        XCTAssertNotNil(canvas.previewImage(for: 0))

        canvas.discardPreviews()
        canvas.update(
            document: document,
            placement: PagePlacement(left: nil, right: nil, centered: 0),
            previewImages: [0: makeImage(gray: 255)],
            previewGeneration: generation,
            previewRevision: 3
        )

        XCTAssertNil(canvas.previewImage(for: 0))
    }

    func testZoomRejectsDelayedPreviewUntilPlacementChanges() throws {
        let url = try PDFFixtureFactory.makePDF(pageSizes: [
            CGSize(width: 600, height: 900),
            CGSize(width: 600, height: 900)
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        let initialGeneration = PagePreviewGeneration(documentID: UUID(), sequence: 1)
        let delayedGeneration = PagePreviewGeneration(
            documentID: initialGeneration.documentID,
            sequence: 2
        )
        let firstPlacement = PagePlacement(left: nil, right: nil, centered: 0)
        let secondPlacement = PagePlacement(left: nil, right: nil, centered: 1)
        let canvas = SpreadCanvasView(
            document: document,
            placement: firstPlacement,
            previewImages: [:],
            previewGeneration: initialGeneration,
            previewRevision: 1
        )

        canvas.disablePreviewsForZoom()
        canvas.update(
            document: document,
            placement: firstPlacement,
            previewImages: [0: makeImage(gray: 127)],
            previewGeneration: delayedGeneration,
            previewRevision: 2
        )

        XCTAssertNil(canvas.previewImage(for: 0))

        canvas.update(
            document: document,
            placement: secondPlacement,
            previewImages: [1: makeImage(gray: 255)],
            previewGeneration: delayedGeneration,
            previewRevision: 3
        )

        XCTAssertNotNil(canvas.previewImage(for: 1))
    }

    private func makeImage(gray: UInt8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 1,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: CGFloat(gray) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}
