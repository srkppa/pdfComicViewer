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
}
