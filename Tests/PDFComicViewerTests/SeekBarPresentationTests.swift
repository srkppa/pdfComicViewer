import XCTest
@testable import PDFComicViewer

final class SeekBarPresentationTests: XCTestCase {
    func testRightBindingFlipsTheSliderHorizontally() {
        // 右綴じは1ページ目を右端に置きたい。macOSのSliderは「左端から現在値まで」を
        // 必ず塗るため、値だけ反転するとつまみは正しくても塗りの向きが逆になる。
        // View自体を反転させて、つまみ・塗り・操作方向をまとめて揃える。
        XCTAssertEqual(SeekBarPresentation.horizontalScale(for: .right), -1)
    }

    func testLeftBindingKeepsTheSliderUnflipped() {
        XCTAssertEqual(SeekBarPresentation.horizontalScale(for: .left), 1)
    }

    func testSliderValueTracksUnitIndexDirectly() {
        // 向きの反転はView側の水平反転が担うため、値そのものは反転させない。
        XCTAssertEqual(SeekBarPresentation.sliderValue(unitIndex: 0, unitCount: 10), 0)
        XCTAssertEqual(SeekBarPresentation.sliderValue(unitIndex: 9, unitCount: 10), 9)
    }

    func testSliderValueAndUnitIndexRoundTrip() {
        for index in 0..<10 {
            let value = SeekBarPresentation.sliderValue(unitIndex: index, unitCount: 10)
            let restored = SeekBarPresentation.unitIndex(sliderValue: value, unitCount: 10)

            XCTAssertEqual(restored, index, "index=\(index)")
        }
    }

    func testOutOfRangeInputsAreClamped() {
        XCTAssertEqual(SeekBarPresentation.sliderValue(unitIndex: -5, unitCount: 10), 0)
        XCTAssertEqual(SeekBarPresentation.sliderValue(unitIndex: 99, unitCount: 10), 9)
        XCTAssertEqual(SeekBarPresentation.unitIndex(sliderValue: -3, unitCount: 10), 0)
        XCTAssertEqual(SeekBarPresentation.unitIndex(sliderValue: 99, unitCount: 10), 9)
    }

    func testSingleUnitAndEmptyDocumentAreSafe() {
        XCTAssertEqual(SeekBarPresentation.sliderValue(unitIndex: 0, unitCount: 1), 0)
        XCTAssertEqual(SeekBarPresentation.sliderValue(unitIndex: 0, unitCount: 0), 0)
        XCTAssertEqual(SeekBarPresentation.unitIndex(sliderValue: 0, unitCount: 0), 0)
    }

    func testRoundingSnapsToNearestUnit() {
        XCTAssertEqual(SeekBarPresentation.unitIndex(sliderValue: 3.4, unitCount: 10), 3)
        XCTAssertEqual(SeekBarPresentation.unitIndex(sliderValue: 3.6, unitCount: 10), 4)
    }
}
