import XCTest
@testable import PDFComicViewer

final class SpreadPresentationTests: XCTestCase {
    func testRightBindingPlacesEarlierPageOnRight() {
        XCTAssertEqual(
            SpreadPresentation.placement(for: .pair(1, 2), binding: .right),
            PagePlacement(left: 2, right: 1, centered: nil)
        )
    }

    func testLeftBindingPlacesEarlierPageOnLeft() {
        XCTAssertEqual(
            SpreadPresentation.placement(for: .pair(1, 2), binding: .left),
            PagePlacement(left: 1, right: 2, centered: nil)
        )
    }

    func testSinglePageIsCenteredRegardlessOfBindingDirection() {
        XCTAssertEqual(
            SpreadPresentation.placement(for: .single(4), binding: .right),
            PagePlacement(left: nil, right: nil, centered: 4)
        )
    }

    func testFindsRebuiltUnitContainingCurrentPhysicalPage() {
        let units: [DisplayUnit] = [.single(0), .pair(1, 2), .single(3)]

        XCTAssertEqual(SpreadPresentation.unitIndex(containing: 2, in: units), 1)
    }

    func testReturnsNilWhenNoDisplayUnitContainsPhysicalPage() {
        let units: [DisplayUnit] = [.single(0), .pair(1, 2)]

        XCTAssertNil(SpreadPresentation.unitIndex(containing: 3, in: units))
    }
}
