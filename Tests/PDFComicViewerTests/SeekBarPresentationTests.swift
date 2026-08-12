import XCTest
@testable import PDFComicViewer

final class SeekBarPresentationTests: XCTestCase {
    func testRightBindingPlacesFirstUnitAtRightEnd() {
        let value = SeekBarPresentation.sliderValue(
            unitIndex: 0,
            unitCount: 10,
            binding: .right
        )

        XCTAssertEqual(value, 9)
    }

    func testLeftBindingPlacesFirstUnitAtLeftEnd() {
        let value = SeekBarPresentation.sliderValue(
            unitIndex: 0,
            unitCount: 10,
            binding: .left
        )

        XCTAssertEqual(value, 0)
    }

    func testSliderValueAndUnitIndexRoundTripForBothBindings() {
        for binding in [BindingDirection.right, BindingDirection.left] {
            for index in 0..<10 {
                let value = SeekBarPresentation.sliderValue(
                    unitIndex: index,
                    unitCount: 10,
                    binding: binding
                )
                let restored = SeekBarPresentation.unitIndex(
                    sliderValue: value,
                    unitCount: 10,
                    binding: binding
                )

                XCTAssertEqual(restored, index, "binding=\(binding) index=\(index)")
            }
        }
    }

    func testOutOfRangeInputsAreClamped() {
        XCTAssertEqual(
            SeekBarPresentation.sliderValue(unitIndex: -5, unitCount: 10, binding: .left),
            0
        )
        XCTAssertEqual(
            SeekBarPresentation.sliderValue(unitIndex: 99, unitCount: 10, binding: .left),
            9
        )
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: -3, unitCount: 10, binding: .left),
            0
        )
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: 99, unitCount: 10, binding: .left),
            9
        )
    }

    func testSingleUnitAndEmptyDocumentAreSafe() {
        XCTAssertEqual(
            SeekBarPresentation.sliderValue(unitIndex: 0, unitCount: 1, binding: .right),
            0
        )
        XCTAssertEqual(
            SeekBarPresentation.sliderValue(unitIndex: 0, unitCount: 0, binding: .right),
            0
        )
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: 0, unitCount: 0, binding: .right),
            0
        )
    }

    func testRoundingSnapsToNearestUnit() {
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: 3.4, unitCount: 10, binding: .left),
            3
        )
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: 3.6, unitCount: 10, binding: .left),
            4
        )
    }
}
