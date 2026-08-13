import XCTest
@testable import PDFComicViewer

final class SearchResultPresentationTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/comics")

    func testNoParentNameWhenNotSearching() {
        // 検索していないときは階層がそのまま見えているので添えない。
        let name = SearchResultPresentation.parentFolderName(
            nodeURL: root.appending(path: "Series/1.pdf"),
            rootURL: root,
            searchQuery: ""
        )

        XCTAssertNil(name)
    }

    func testNoParentNameForWhitespaceOnlyQuery() {
        let name = SearchResultPresentation.parentFolderName(
            nodeURL: root.appending(path: "Series/1.pdf"),
            rootURL: root,
            searchQuery: "   "
        )

        XCTAssertNil(name)
    }

    func testReturnsImmediateParentFolderNameWhileSearching() {
        let name = SearchResultPresentation.parentFolderName(
            nodeURL: root.appending(path: "Series/vol/3.pdf"),
            rootURL: root,
            searchQuery: "3"
        )

        XCTAssertEqual(name, "vol")
    }

    func testNoParentNameWhenTheFileSitsDirectlyUnderTheRoot() {
        // ルート直下なら親＝表示中のフォルダ自身なので、添えても情報が増えない。
        let name = SearchResultPresentation.parentFolderName(
            nodeURL: root.appending(path: "1.pdf"),
            rootURL: root,
            searchQuery: "1"
        )

        XCTAssertNil(name)
    }

    func testComparesRootUsingStandardizedPaths() {
        // 呼び出し側の正規化が揃っていなくてもルート判定が効くこと。
        let name = SearchResultPresentation.parentFolderName(
            nodeURL: URL(fileURLWithPath: "/tmp/comics/1.pdf"),
            rootURL: URL(fileURLWithPath: "/tmp/./comics"),
            searchQuery: "1"
        )

        XCTAssertNil(name)
    }

    func testReturnsParentNameWhenRootIsUnknown() {
        let name = SearchResultPresentation.parentFolderName(
            nodeURL: root.appending(path: "Series/1.pdf"),
            rootURL: nil,
            searchQuery: "1"
        )

        XCTAssertEqual(name, "Series")
    }
}
