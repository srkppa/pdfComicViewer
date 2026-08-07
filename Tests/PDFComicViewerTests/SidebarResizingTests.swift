import XCTest
@testable import PDFComicViewer

final class SidebarResizingTests: XCTestCase {
    func testWidthAddsPositiveTranslation() {
        let width = SidebarResizing.width(startingWidth: 260, translation: 40)

        XCTAssertEqual(width, 300)
    }

    func testWidthSubtractsNegativeTranslation() {
        let width = SidebarResizing.width(startingWidth: 260, translation: -40)

        XCTAssertEqual(width, 220)
    }

    func testWidthClampsToMinimum() {
        let width = SidebarResizing.width(startingWidth: 260, translation: -1_000)

        XCTAssertEqual(width, SidebarResizing.minimumWidth)
    }

    func testWidthClampsToMaximum() {
        let width = SidebarResizing.width(startingWidth: 260, translation: 1_000)

        XCTAssertEqual(width, SidebarResizing.maximumWidth)
    }
}
