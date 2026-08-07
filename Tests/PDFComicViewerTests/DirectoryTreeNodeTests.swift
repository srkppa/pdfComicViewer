import XCTest
@testable import PDFComicViewer

final class DirectoryTreeNodeTests: XCTestCase {
    func testInitDerivesIDAndNameFromURL() {
        let url = URL(fileURLWithPath: "/tmp/comics/One Piece.pdf")

        let node = DirectoryTreeNode(url: url, kind: .pdf)

        XCTAssertEqual(node.id, url.standardizedFileURL.path)
        XCTAssertEqual(node.name, "One Piece.pdf")
        XCTAssertEqual(node.kind, .pdf)
        XCTAssertNil(node.children)
    }

    func testFolderNodeCanHoldChildren() {
        let folderURL = URL(fileURLWithPath: "/tmp/comics")
        let childURL = folderURL.appending(path: "One Piece.pdf")
        let child = DirectoryTreeNode(url: childURL, kind: .pdf)

        let folder = DirectoryTreeNode(url: folderURL, kind: .folder, children: [child])

        XCTAssertEqual(folder.kind, .folder)
        XCTAssertEqual(folder.children, [child])
    }

    func testFirstNodeWithIDFindsTopLevelNode() {
        let pdfURL = URL(fileURLWithPath: "/tmp/comics/One Piece.pdf")
        let pdf = DirectoryTreeNode(url: pdfURL, kind: .pdf)
        let nodes = [pdf]

        let found = nodes.firstNode(withID: pdf.id)

        XCTAssertEqual(found, pdf)
    }

    func testFirstNodeWithIDFindsDeeplyNestedNode() {
        let targetURL = URL(fileURLWithPath: "/tmp/comics/SeriesA/vol1/page1.pdf")
        let target = DirectoryTreeNode(url: targetURL, kind: .pdf)
        let vol1URL = URL(fileURLWithPath: "/tmp/comics/SeriesA/vol1")
        let vol1 = DirectoryTreeNode(url: vol1URL, kind: .folder, children: [target])
        let seriesAURL = URL(fileURLWithPath: "/tmp/comics/SeriesA")
        let seriesA = DirectoryTreeNode(url: seriesAURL, kind: .folder, children: [vol1])
        let nodes = [seriesA]

        let found = nodes.firstNode(withID: target.id)

        XCTAssertEqual(found, target)
    }

    func testFirstNodeWithIDReturnsNilWhenNotFound() {
        let pdfURL = URL(fileURLWithPath: "/tmp/comics/One Piece.pdf")
        let pdf = DirectoryTreeNode(url: pdfURL, kind: .pdf)
        let nodes = [pdf]

        let found = nodes.firstNode(withID: "/nonexistent/path.pdf")

        XCTAssertNil(found)
    }
}
