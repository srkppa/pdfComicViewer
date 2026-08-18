import XCTest
@testable import PDFComicViewer

final class SpreadBuilderTests: XCTestCase {
    private let portrait = PageGeometry(width: 600, height: 900)
    private let landscape = PageGeometry(width: 1200, height: 800)

    func testCoverAlignmentKeepsFirstPageSingle() {
        let result = SpreadBuilder.build(
            pages: Array(repeating: portrait, count: 5),
            mode: .spread, alignment: .coverSingle, overrides: [:]
        )

        XCTAssertEqual(result, [.single(0), .pair(1, 2), .pair(3, 4)])
    }

    func testLandscapeBreaksAndRestartsPairing() {
        let result = SpreadBuilder.build(
            pages: [portrait, portrait, portrait, landscape, portrait, portrait],
            mode: .spread, alignment: .coverSingle, overrides: [:]
        )

        XCTAssertEqual(result, [.single(0), .pair(1, 2), .single(3), .pair(4, 5)])
    }

    func testManualPairOverrideBeatsLandscapeDetection() {
        let result = SpreadBuilder.build(
            pages: [landscape, portrait], mode: .spread,
            alignment: .shifted, overrides: [0: .pairable]
        )

        XCTAssertEqual(result, [.pair(0, 1)])
    }

    func testSingleModeReturnsEveryPhysicalPage() {
        let result = SpreadBuilder.build(
            pages: [portrait, landscape], mode: .single,
            alignment: .coverSingle, overrides: [:]
        )

        XCTAssertEqual(result, [.single(0), .single(1)])
    }

    func testEmptyPagesProduceNoDisplayUnits() {
        let result = SpreadBuilder.build(
            pages: [], mode: .spread, alignment: .coverSingle, overrides: [:]
        )

        XCTAssertEqual(result, [])
    }

    func testOnePageProducesSingleDisplayUnit() {
        let result = SpreadBuilder.build(
            pages: [portrait], mode: .spread, alignment: .shifted, overrides: [:]
        )

        XCTAssertEqual(result, [.single(0)])
    }

    func testTwoPortraitPagesFormPairWhenShifted() {
        let result = SpreadBuilder.build(
            pages: [portrait, portrait], mode: .spread, alignment: .shifted, overrides: [:]
        )

        XCTAssertEqual(result, [.pair(0, 1)])
    }

    func testEvenPageCountFormsOnlyPairsWhenShifted() {
        let result = SpreadBuilder.build(
            pages: Array(repeating: portrait, count: 4),
            mode: .spread, alignment: .shifted, overrides: [:]
        )

        XCTAssertEqual(result, [.pair(0, 1), .pair(2, 3)])
    }

    func testOddPageCountLeavesLastPageSingle() {
        let result = SpreadBuilder.build(
            pages: Array(repeating: portrait, count: 5),
            mode: .spread, alignment: .shifted, overrides: [:]
        )

        XCTAssertEqual(result, [.pair(0, 1), .pair(2, 3), .single(4)])
    }

    func testConsecutiveLandscapePagesEachRemainSingle() {
        let result = SpreadBuilder.build(
            pages: [portrait, landscape, landscape, portrait],
            mode: .spread, alignment: .shifted, overrides: [:]
        )

        XCTAssertEqual(result, [.single(0), .single(1), .single(2), .single(3)])
    }

    func testLandscapeAtBeginningIsSingleBeforePairingRestarts() {
        let result = SpreadBuilder.build(
            pages: [landscape, portrait, portrait],
            mode: .spread, alignment: .shifted, overrides: [:]
        )

        XCTAssertEqual(result, [.single(0), .pair(1, 2)])
    }

    func testLandscapeAtEndFlushesPendingPageBeforeIt() {
        let result = SpreadBuilder.build(
            pages: [portrait, portrait, landscape],
            mode: .spread, alignment: .shifted, overrides: [:]
        )

        XCTAssertEqual(result, [.pair(0, 1), .single(2)])
    }

    func testManualSingleBreaksExistingPairing() {
        let result = SpreadBuilder.build(
            pages: [portrait, portrait, portrait, portrait],
            mode: .spread, alignment: .shifted, overrides: [1: .single]
        )

        XCTAssertEqual(result, [.single(0), .single(1), .pair(2, 3)])
    }

    /// 表紙が横長のPDFでも、見開き位置のずらしが効かなければならない。
    /// `alignment` の起点を「1ページ目」に固定していると、横長判定が先に
    /// 成立して分岐に届かず、切り替えても結果が変わらなくなる。
    func testCoverAlignmentAnchorsToFirstPairablePageAfterLandscapeCover() {
        let pages = [landscape, portrait, portrait, portrait, portrait]

        let cover = SpreadBuilder.build(
            pages: pages, mode: .spread, alignment: .coverSingle, overrides: [:]
        )
        let shifted = SpreadBuilder.build(
            pages: pages, mode: .spread, alignment: .shifted, overrides: [:]
        )

        XCTAssertEqual(cover, [.single(0), .single(1), .pair(2, 3), .single(4)])
        XCTAssertEqual(shifted, [.single(0), .pair(1, 2), .pair(3, 4)])
    }

    /// 1ページ目を手動で「単独」にしている場合も、その次の見開き可能ページが
    /// ずらしの起点になる。
    func testCoverAlignmentAnchorsToFirstPairablePageAfterManualSingleCover() {
        let pages = [portrait, portrait, portrait, portrait]

        let cover = SpreadBuilder.build(
            pages: pages, mode: .spread, alignment: .coverSingle, overrides: [0: .single]
        )
        let shifted = SpreadBuilder.build(
            pages: pages, mode: .spread, alignment: .shifted, overrides: [0: .single]
        )

        XCTAssertEqual(cover, [.single(0), .single(1), .pair(2, 3)])
        XCTAssertEqual(shifted, [.single(0), .pair(1, 2), .single(3)])
    }

    /// 全ページが横長でずらす余地が無くても、落ちずに全部単独で返る。
    func testAllLandscapePagesStaySingleUnderBothAlignments() {
        let pages = [landscape, landscape, landscape]

        let cover = SpreadBuilder.build(
            pages: pages, mode: .spread, alignment: .coverSingle, overrides: [:]
        )
        let shifted = SpreadBuilder.build(
            pages: pages, mode: .spread, alignment: .shifted, overrides: [:]
        )

        XCTAssertEqual(cover, [.single(0), .single(1), .single(2)])
        XCTAssertEqual(shifted, [.single(0), .single(1), .single(2)])
    }
}
