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

    func testScanPopulatesModificationDateForFilesAndFolders() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(named: "a-comic.pdf", in: root)
        _ = try makeDirectory(named: "sub", in: root)

        let nodes = try await DirectoryScanner().scan(rootURL: root)

        for node in nodes {
            XCTAssertNotNil(node.modificationDate, "\(node.name) の更新日が取得できていません")
        }
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

    func testScanExcludesSymlinksAndDoesNotRecurseIntoCycles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(named: "real.pdf", in: root)
        let subfolder = try makeDirectory(named: "sub", in: root)
        // Symlink inside `sub` pointing back up at `root`, which would recurse
        // forever if the scanner ever descended into it.
        let cycleLink = subfolder.appending(path: "cycle-back-to-root")
        try FileManager.default.createSymbolicLink(at: cycleLink, withDestinationURL: root)

        let nodes = try await DirectoryScanner().scan(rootURL: root)

        XCTAssertEqual(nodes.map(\.name), ["sub", "real.pdf"])
        let subNode = try XCTUnwrap(nodes.first { $0.name == "sub" })
        XCTAssertEqual(subNode.children, [])
    }

    func testScanStopsPromptlyWhenCancelled() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Build a moderately deep/wide tree so an uncancelled scan would take
        // measurably longer than a cancelled one.
        var current = root
        for depth in 0..<50 {
            current = try makeDirectory(named: "level-\(depth)", in: current)
            for fileIndex in 0..<20 {
                try makeFile(named: "file-\(fileIndex).pdf", in: current)
            }
        }

        let scanner = DirectoryScanner()

        let baselineClock = ContinuousClock()
        let baselineStart = baselineClock.now
        _ = try await scanner.scan(rootURL: root)
        let uncancelledDuration = baselineClock.now - baselineStart

        let cancelledClock = ContinuousClock()
        let cancelledStart = cancelledClock.now
        let task = Task { try await scanner.scan(rootURL: root) }
        task.cancel()
        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected outcome when cancellation is observed promptly.
        }
        let cancelledDuration = cancelledClock.now - cancelledStart

        // A promptly-cancelled scan should complete in a small fraction of the
        // time an uncancelled full walk takes, proving the walk actually
        // stopped early rather than running to completion regardless.
        XCTAssertLessThan(cancelledDuration, uncancelledDuration / 2)
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
