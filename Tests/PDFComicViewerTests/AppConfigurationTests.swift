import XCTest
@testable import PDFComicViewer

final class AppConfigurationTests: XCTestCase {
    func testApplicationNameIsJapaneseReaderName() {
        XCTAssertEqual(AppConfiguration.applicationName, "PDF漫画ビューアー")
    }
}
