import XCTest
@testable import PDFComicViewer

final class FileTrashServiceTests: XCTestCase {
    func testMissingFileIsReportedAsFailure() async {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "FileTrashServiceTests-missing-\(UUID().uuidString).pdf")

        let failures = await FileTrashService().trash([missing])

        XCTAssertEqual(failures, [missing])
    }

    func testEmptyInputReturnsNoFailures() async {
        let failures = await FileTrashService().trash([])

        XCTAssertTrue(failures.isEmpty)
    }
}
