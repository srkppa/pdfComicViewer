import XCTest
@testable import PDFComicViewer

final class DirectoryScannerTests: XCTestCase {
    func testScanFiltersToPDFFilesAndKeepsAllFoldersSortedWithFoldersFirst() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(named: "b-comic.pdf", in: root)
        try makeFile(named: "a-comic.PDF", in: root)
        try makeFile(named: "notes.txt", in: root)
        try makeFile(named: ".hidden.pdf", in: root)
        _ = try makeDirectory(named: "empty-folder", in: root)
        let subWithPDF = try makeDirectory(named: "sub-with-pdf", in: root)
        try makeFile(named: "inner.pdf", in: subWithPDF)

        let nodes = try await DirectoryScanner().scan(rootURL: root)

        XCTAssertEqual(
            nodes.map(\.name),
            ["empty-folder", "sub-with-pdf", "a-comic.PDF", "b-comic.pdf"]
        )
        XCTAssertEqual(nodes.first { $0.name == "empty-folder" }?.children, [])
        let subNode = try XCTUnwrap(nodes.first { $0.name == "sub-with-pdf" })
        XCTAssertEqual(subNode.children?.map(\.name), ["inner.pdf"])
        XCTAssertEqual(subNode.children?.first?.kind, .pdf)
    }

    func testScanThrowsForUnreadableRoot() async throws {
        let missingRoot = FileManager.default.temporaryDirectory
            .appending(path: "DirectoryScannerTests-missing-\(UUID().uuidString)")

        do {
            _ = try await DirectoryScanner().scan(rootURL: missingRoot)
            XCTFail("エラーが発生するはずです")
        } catch {
            XCTAssertTrue(error is DirectoryScanError)
        }
    }

    func testScanSkipsUnreadableSubfolderButKeepsSiblings() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let restricted = try makeDirectory(named: "restricted", in: root)
        try makeFile(named: "inner.pdf", in: restricted)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: restricted.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: restricted.path
            )
        }
        try makeFile(named: "sibling.pdf", in: root)

        let nodes = try await DirectoryScanner().scan(rootURL: root)

        XCTAssertEqual(nodes.map(\.name), ["restricted", "sibling.pdf"])
        XCTAssertEqual(nodes.first { $0.name == "restricted" }?.children, [])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "DirectoryScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDirectory(named name: String, in parent: URL) throws -> URL {
        let url = parent.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(named name: String, in parent: URL) throws {
        try Data("fixture".utf8).write(to: parent.appending(path: name))
    }
}
