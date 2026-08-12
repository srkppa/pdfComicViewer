import XCTest
@testable import PDFComicViewer

final class SeriesNavigationTests: XCTestCase {
    func testNextURLReturnsFollowingElement() {
        let urls = [
            URL(fileURLWithPath: "/tmp/1.pdf"),
            URL(fileURLWithPath: "/tmp/2.pdf"),
            URL(fileURLWithPath: "/tmp/3.pdf")
        ]

        let next = SeriesNavigation.nextURL(after: urls[0], in: urls)

        XCTAssertEqual(next, urls[1])
    }

    func testNextURLReturnsNilAtLastElement() {
        let urls = [
            URL(fileURLWithPath: "/tmp/1.pdf"),
            URL(fileURLWithPath: "/tmp/2.pdf")
        ]

        let next = SeriesNavigation.nextURL(after: urls[1], in: urls)

        XCTAssertNil(next)
    }

    func testNextURLReturnsNilWhenCurrentIsNotInList() {
        let urls = [URL(fileURLWithPath: "/tmp/1.pdf")]

        let next = SeriesNavigation.nextURL(
            after: URL(fileURLWithPath: "/tmp/missing.pdf"),
            in: urls
        )

        XCTAssertNil(next)
    }

    func testNextURLReturnsNilForEmptyList() {
        let next = SeriesNavigation.nextURL(
            after: URL(fileURLWithPath: "/tmp/1.pdf"),
            in: []
        )

        XCTAssertNil(next)
    }

    func testNextURLComparesStandardizedURLs() {
        // 呼び出し側の正規化が揃っていなくても一致判定できることを確認する。
        let urls = [
            URL(fileURLWithPath: "/tmp/./1.pdf"),
            URL(fileURLWithPath: "/tmp/2.pdf")
        ]

        let next = SeriesNavigation.nextURL(
            after: URL(fileURLWithPath: "/tmp/1.pdf"),
            in: urls
        )

        XCTAssertEqual(next, urls[1])
    }
}
