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

    func testSortedByNameAscendingKeepsFoldersBeforeFiles() {
        let nodes = [
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/b.pdf"), kind: .pdf),
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/Zeta"), kind: .folder),
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/a.pdf"), kind: .pdf),
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/Alpha"), kind: .folder),
        ]

        let sorted = nodes.sorted(by: .name, direction: .ascending)

        XCTAssertEqual(sorted.map(\.name), ["Alpha", "Zeta", "a.pdf", "b.pdf"])
    }

    func testSortedByNameDescendingKeepsFoldersBeforeFiles() {
        let nodes = [
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/a.pdf"), kind: .pdf),
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/Alpha"), kind: .folder),
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/b.pdf"), kind: .pdf),
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/Zeta"), kind: .folder),
        ]

        let sorted = nodes.sorted(by: .name, direction: .descending)

        XCTAssertEqual(sorted.map(\.name), ["Zeta", "Alpha", "b.pdf", "a.pdf"])
    }

    func testSortedByModificationDateOrdersOldestAndNewestWithNilLast() {
        let old = Date(timeIntervalSince1970: 1000)
        let new = Date(timeIntervalSince1970: 2000)
        let oldNode = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/old.pdf"), kind: .pdf, modificationDate: old
        )
        let newNode = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/new.pdf"), kind: .pdf, modificationDate: new
        )
        let unknownNode = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/unknown.pdf"), kind: .pdf
        )
        let nodes = [newNode, unknownNode, oldNode]

        let ascending = nodes.sorted(by: .modificationDate, direction: .ascending)
        XCTAssertEqual(ascending.map(\.name), ["unknown.pdf", "old.pdf", "new.pdf"])

        let descending = nodes.sorted(by: .modificationDate, direction: .descending)
        XCTAssertEqual(descending.map(\.name), ["new.pdf", "old.pdf", "unknown.pdf"])
    }

    func testSortedAppliesRecursivelyToChildren() {
        let child1 = DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/vol/b.pdf"), kind: .pdf)
        let child2 = DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/vol/a.pdf"), kind: .pdf)
        let folder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/vol"), kind: .folder, children: [child1, child2]
        )

        let sorted = [folder].sorted(by: .name, direction: .ascending)

        XCTAssertEqual(sorted.first?.children?.map(\.name), ["a.pdf", "b.pdf"])
    }

    func testSortDirectionToggledFlipsBetweenAscendingAndDescending() {
        XCTAssertEqual(DirectorySortDirection.ascending.toggled, .descending)
        XCTAssertEqual(DirectorySortDirection.descending.toggled, .ascending)
    }

    func testFilteredByQueryReturnsAllNodesForEmptyQuery() {
        let nodes = [
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/a.pdf"), kind: .pdf),
            DirectoryTreeNode(url: URL(fileURLWithPath: "/tmp/comics/b.pdf"), kind: .pdf)
        ]

        XCTAssertEqual(nodes.filtered(byQuery: ""), nodes)
        XCTAssertEqual(nodes.filtered(byQuery: "   "), nodes)
    }

    func testFilteredByQueryMatchesFileNameCaseInsensitively() {
        let match = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/OnePiece.pdf"), kind: .pdf
        )
        let other = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Naruto.pdf"), kind: .pdf
        )

        let filtered = [match, other].filtered(byQuery: "onepiece")

        XCTAssertEqual(filtered, [match])
    }

    func testFilteredByQueryKeepsFolderThatMatchesWithAllChildren() {
        let child1 = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/OnePiece/1.pdf"), kind: .pdf
        )
        let child2 = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/OnePiece/2.pdf"), kind: .pdf
        )
        let folder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/OnePiece"),
            kind: .folder,
            children: [child1, child2]
        )
        let other = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Naruto.pdf"), kind: .pdf
        )

        let filtered = [folder, other].filtered(byQuery: "onepiece")

        XCTAssertEqual(filtered, [folder])
        XCTAssertEqual(filtered.first?.children, [child1, child2])
    }

    func testFilteredByQueryKeepsPathToMatchingDescendant() {
        let target = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series/vol/3巻.pdf"), kind: .pdf
        )
        let sibling = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series/vol/1巻.pdf"), kind: .pdf
        )
        let volFolder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series/vol"),
            kind: .folder,
            children: [sibling, target]
        )
        let seriesFolder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series"),
            kind: .folder,
            children: [volFolder]
        )

        let filtered = [seriesFolder].filtered(byQuery: "3巻")

        XCTAssertEqual(filtered.map(\.name), ["Series"])
        XCTAssertEqual(filtered.first?.children?.map(\.name), ["vol"])
        XCTAssertEqual(filtered.first?.children?.first?.children, [target])
    }

    func testFilteredByQueryDropsFolderWithNoMatchingDescendants() {
        let child = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Naruto/1.pdf"), kind: .pdf
        )
        let folder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Naruto"),
            kind: .folder,
            children: [child]
        )

        let filtered = [folder].filtered(byQuery: "onepiece")

        XCTAssertTrue(filtered.isEmpty)
    }

    func testFlattenedPDFMatchesReturnsEmptyForEmptyQuery() {
        let pdf = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/a.pdf"), kind: .pdf
        )

        // 空クエリのときは呼び出し側が絞り込み前のツリーを使う想定なので、
        // ここでは何も返さない。
        XCTAssertTrue([pdf].flattenedPDFMatches(byQuery: "").isEmpty)
        XCTAssertTrue([pdf].flattenedPDFMatches(byQuery: "   ").isEmpty)
    }

    func testFlattenedPDFMatchesCollapsesNestedFoldersIntoAFlatList() {
        let deep = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series/vol/3巻.pdf"), kind: .pdf
        )
        let sibling = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series/vol/1巻.pdf"), kind: .pdf
        )
        let volFolder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series/vol"),
            kind: .folder,
            children: [sibling, deep]
        )
        let seriesFolder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series"),
            kind: .folder,
            children: [volFolder]
        )

        let matches = [seriesFolder].flattenedPDFMatches(byQuery: "3巻")

        // フォルダは一切含まれず、マッチしたPDFだけが一列に並ぶ。
        XCTAssertEqual(matches.map(\.name), ["3巻.pdf"])
        XCTAssertTrue(matches.allSatisfy { $0.kind == .pdf })
    }

    func testFlattenedPDFMatchesIncludesEveryPDFUnderAMatchingFolder() {
        let first = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/OnePiece/1.pdf"), kind: .pdf
        )
        let nested = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/OnePiece/extra/2.pdf"), kind: .pdf
        )
        let extraFolder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/OnePiece/extra"),
            kind: .folder,
            children: [nested]
        )
        let folder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/OnePiece"),
            kind: .folder,
            children: [first, extraFolder]
        )

        let matches = [folder].flattenedPDFMatches(byQuery: "onepiece")

        // フォルダ名が一致したら、その配下のPDFは入れ子の奥まですべて拾う。
        XCTAssertEqual(Set(matches.map(\.name)), ["1.pdf", "2.pdf"])
    }

    func testFlattenedPDFMatchesStripChildrenSoNoDisclosureTriangleAppears() {
        let child = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series/1.pdf"), kind: .pdf
        )
        let folder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Series"),
            kind: .folder,
            children: [child]
        )

        let matches = [folder].flattenedPDFMatches(byQuery: "series")

        // childrenがnilでないとListが折りたたみ三角を描いてしまう。
        XCTAssertTrue(matches.allSatisfy { $0.children == nil })
    }

    func testFlattenedPDFMatchesReturnsEmptyWhenNothingMatches() {
        let child = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Naruto/1.pdf"), kind: .pdf
        )
        let folder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Naruto"),
            kind: .folder,
            children: [child]
        )

        XCTAssertTrue([folder].flattenedPDFMatches(byQuery: "onepiece").isEmpty)
    }

    func testFilteredByQueryReturnsEmptyForEmptyFolder() {
        let folder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Empty"),
            kind: .folder,
            children: []
        )

        let filtered = [folder].filtered(byQuery: "anything")

        XCTAssertTrue(filtered.isEmpty)
    }
}
