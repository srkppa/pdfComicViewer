import XCTest
@testable import PDFComicViewer

final class SeriesNavigatingTests: XCTestCase {
    func testNextVolumeURLReturnsNextPDFByName() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(named: "1巻.pdf", in: root)
        try makeFile(named: "2巻.pdf", in: root)
        try makeFile(named: "3巻.pdf", in: root)

        let next = await SeriesNavigator().nextVolumeURL(
            after: root.appending(path: "1巻.pdf")
        )

        XCTAssertEqual(next?.lastPathComponent, "2巻.pdf")
    }

    func testNextVolumeURLReturnsNilAtLastFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(named: "1巻.pdf", in: root)
        try makeFile(named: "2巻.pdf", in: root)

        let next = await SeriesNavigator().nextVolumeURL(
            after: root.appending(path: "2巻.pdf")
        )

        XCTAssertNil(next)
    }

    func testNextVolumeURLIgnoresNonPDFFilesAndFoldersNamedLikeOne() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(named: "1.pdf", in: root)
        try makeFile(named: "2.pdf", in: root)
        try makeFile(named: "notes.txt", in: root)
        // フォルダ名がpdfっぽくても、フォルダはPDFとして扱わない。
        _ = try makeDirectory(named: "3.pdf", in: root)

        let next = await SeriesNavigator().nextVolumeURL(
            after: root.appending(path: "1.pdf")
        )

        XCTAssertEqual(next?.lastPathComponent, "2.pdf")
    }

    func testNextVolumeURLIgnoresHiddenFiles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(named: "1.pdf", in: root)
        try makeFile(named: ".hidden.pdf", in: root)
        try makeFile(named: "2.pdf", in: root)

        let next = await SeriesNavigator().nextVolumeURL(
            after: root.appending(path: "1.pdf")
        )

        XCTAssertEqual(next?.lastPathComponent, "2.pdf")
    }

    func testNextVolumeURLDoesNotDescendIntoSubfolders() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(named: "1.pdf", in: root)
        let sub = try makeDirectory(named: "sub", in: root)
        try makeFile(named: "2.pdf", in: sub)

        let next = await SeriesNavigator().nextVolumeURL(
            after: root.appending(path: "1.pdf")
        )

        XCTAssertNil(next)
    }

    func testNextVolumeURLReturnsNilWhenCurrentFileIsMissing() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(named: "1.pdf", in: root)

        let next = await SeriesNavigator().nextVolumeURL(
            after: root.appending(path: "missing.pdf")
        )

        XCTAssertNil(next)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SeriesNavigatingTests-\(UUID().uuidString)")
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
