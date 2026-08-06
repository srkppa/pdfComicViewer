import CoreGraphics
import XCTest
@testable import PDFComicViewer

final class SpreadLayoutCalculatorTests: XCTestCase {
    func testSinglePageIsCenteredAndFitsViewport() {
        let frames = SpreadLayoutCalculator.frames(
            pageSizes: [CGSize(width: 600, height: 900)],
            viewport: CGSize(width: 1_200, height: 800),
            gutter: 12
        )

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].width, 800 * 600 / 900, accuracy: 0.01)
        XCTAssertEqual(frames[0].height, 800, accuracy: 0.01)
        XCTAssertEqual(frames[0].midX, 600, accuracy: 0.01)
        XCTAssertEqual(frames[0].midY, 400, accuracy: 0.01)
    }

    func testPairFitsViewportAndKeepsGutter() {
        let frames = SpreadLayoutCalculator.frames(
            pageSizes: [
                CGSize(width: 600, height: 900),
                CGSize(width: 600, height: 900)
            ],
            viewport: CGSize(width: 1_012, height: 900),
            gutter: 12
        )

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 12, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(frames[0].minX, 0)
        XCTAssertLessThanOrEqual(frames[1].maxX, 1_012)
        XCTAssertLessThanOrEqual(frames[0].maxY, 900)
        XCTAssertLessThanOrEqual(frames[1].maxY, 900)
    }

    func testPagesKeepIndependentAspectRatios() {
        let frames = SpreadLayoutCalculator.frames(
            pageSizes: [
                CGSize(width: 600, height: 900),
                CGSize(width: 800, height: 600)
            ],
            viewport: CGSize(width: 1_412, height: 900),
            gutter: 12
        )

        XCTAssertEqual(frames[0].width / frames[0].height, 600.0 / 900.0, accuracy: 0.001)
        XCTAssertEqual(frames[1].width / frames[1].height, 800.0 / 600.0, accuracy: 0.001)
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 12, accuracy: 0.01)
    }

    func testEmptyPageListProducesNoFrames() {
        XCTAssertEqual(
            SpreadLayoutCalculator.frames(
                pageSizes: [],
                viewport: CGSize(width: 1_000, height: 800),
                gutter: 12
            ),
            []
        )
    }
}

final class ZoomCommandTests: XCTestCase {
    func testRepeatedActionWithNewSequenceIsANewCommand() {
        let first = ZoomCommand(action: .zoomIn, sequence: 1)
        let repeated = ZoomCommand(action: .zoomIn, sequence: 2)

        XCTAssertNotEqual(first, repeated)
    }
}
