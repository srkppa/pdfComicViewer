import XCTest
@testable import PDFComicViewer

final class SeekBarVisibilityTests: XCTestCase {
    func testShownWhenNearBottomWithOpenMultiUnitDocument() {
        let isShown = SeekBarVisibility.isShown(
            pointerIsNearBottom: true,
            isDragging: false,
            hasOpenDocument: true,
            displayUnitCount: 3,
            isLoading: false
        )

        XCTAssertTrue(isShown)
    }

    func testStaysShownWhileDraggingEvenIfPointerNoLongerReportedNearBottom() {
        // ドラッグ中はAppKitのイベント配送が乱れてホバー判定が更新されないことがある。
        // その揺らぎに関係なく、ドラッグ中である事実だけで表示を維持する。
        let isShown = SeekBarVisibility.isShown(
            pointerIsNearBottom: false,
            isDragging: true,
            hasOpenDocument: true,
            displayUnitCount: 3,
            isLoading: false
        )

        XCTAssertTrue(isShown)
    }

    func testHiddenWhenNeitherNearBottomNorDragging() {
        let isShown = SeekBarVisibility.isShown(
            pointerIsNearBottom: false,
            isDragging: false,
            hasOpenDocument: true,
            displayUnitCount: 3,
            isLoading: false
        )

        XCTAssertFalse(isShown)
    }

    func testHiddenWithoutAnOpenDocumentEvenIfDragging() {
        let isShown = SeekBarVisibility.isShown(
            pointerIsNearBottom: true,
            isDragging: true,
            hasOpenDocument: false,
            displayUnitCount: 3,
            isLoading: false
        )

        XCTAssertFalse(isShown)
    }

    func testHiddenWithOnlyOneDisplayUnit() {
        let isShown = SeekBarVisibility.isShown(
            pointerIsNearBottom: true,
            isDragging: false,
            hasOpenDocument: true,
            displayUnitCount: 1,
            isLoading: false
        )

        XCTAssertFalse(isShown)
    }

    func testHiddenWhileLoadingEvenIfDragging() {
        let isShown = SeekBarVisibility.isShown(
            pointerIsNearBottom: true,
            isDragging: true,
            hasOpenDocument: true,
            displayUnitCount: 3,
            isLoading: true
        )

        XCTAssertFalse(isShown)
    }
}
