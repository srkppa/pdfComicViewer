import XCTest
@testable import PDFComicViewer

final class ReadingProgressStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var progressFile: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "ReadingProgressStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        progressFile = temporaryDirectory.appending(path: "progress.json")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testRoundTripsDocumentPreferences() async throws {
        let store = FileReadingProgressStore(fileURL: progressFile)
        let record = DocumentRecord(
            bookmarkData: Data([1, 2]),
            normalizedPath: "/tmp/comic.pdf",
            metadata: .init(size: 42, modificationDate: Date(timeIntervalSince1970: 10)),
            preferences: .init(
                lastPageIndex: 8,
                binding: .right,
                displayMode: .spread,
                alignment: .coverSingle,
                pageOverrides: [3: .single]
            )
        )

        try await store.save(record)

        let reloadedStore = FileReadingProgressStore(fileURL: progressFile)
        let loaded = try await reloadedStore.load(for: URL(fileURLWithPath: "/tmp/comic.pdf"))
        XCTAssertEqual(loaded, record)
    }

    func testSaveReplacesExistingRecordForSameNormalizedPath() async throws {
        let store = FileReadingProgressStore(fileURL: progressFile)
        let original = makeRecord(path: "/tmp/comic.pdf", lastPageIndex: 2)
        let replacement = makeRecord(path: "/tmp/comic.pdf", lastPageIndex: 9)

        try await store.save(original)
        try await store.save(replacement)

        let records = try await store.allRecords()
        XCTAssertEqual(records, [replacement])
    }

    func testCorruptFileIsReportedWithoutDeletingIt() async throws {
        try Data("not-json".utf8).write(to: progressFile)
        let store = FileReadingProgressStore(fileURL: progressFile)

        await XCTAssertThrowsErrorAsync { _ = try await store.allRecords() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: progressFile.path))
    }

    func testLoadMatchesRecordAfterBookmarkedFileIsRenamed() async throws {
        let originalFile = temporaryDirectory.appending(path: "comic.pdf")
        let movedFile = temporaryDirectory.appending(path: "renamed-comic.pdf")
        try Data([0]).write(to: originalFile)
        let record = makeRecord(
            bookmarkData: try DocumentBookmarkService.makeBookmark(for: originalFile),
            path: originalFile.standardizedFileURL.path,
            lastPageIndex: 4
        )
        try FileManager.default.moveItem(at: originalFile, to: movedFile)
        let store = FileReadingProgressStore(fileURL: progressFile)

        try await store.save(record)

        let loaded = try await store.load(for: movedFile)
        XCTAssertEqual(loaded, record)
    }

    func testSaveAfterRenameReplacesRecordResolvedByOldBookmark() async throws {
        let originalFile = temporaryDirectory.appending(path: "comic.pdf")
        let movedFile = temporaryDirectory.appending(path: "renamed-comic.pdf")
        try Data([0]).write(to: originalFile)
        let original = makeRecord(
            bookmarkData: try DocumentBookmarkService.makeBookmark(for: originalFile),
            path: originalFile.standardizedFileURL.path,
            lastPageIndex: 2
        )
        let store = FileReadingProgressStore(fileURL: progressFile)
        try await store.save(original)
        try FileManager.default.moveItem(at: originalFile, to: movedFile)
        let latest = makeRecord(
            bookmarkData: try DocumentBookmarkService.makeBookmark(for: movedFile),
            path: movedFile.standardizedFileURL.path,
            lastPageIndex: 9
        )

        try await store.save(latest)

        let reloadedStore = FileReadingProgressStore(fileURL: progressFile)
        let loaded = try await reloadedStore.load(for: movedFile)
        let allRecords = try await reloadedStore.allRecords()
        XCTAssertEqual(loaded, latest)
        XCTAssertEqual(allRecords, [latest])
    }

    private func makeRecord(
        bookmarkData: Data = Data(),
        path: String,
        lastPageIndex: Int
    ) -> DocumentRecord {
        DocumentRecord(
            bookmarkData: bookmarkData,
            normalizedPath: path,
            metadata: .init(size: 10, modificationDate: Date(timeIntervalSince1970: 1)),
            preferences: .init(
                lastPageIndex: lastPageIndex,
                binding: .right,
                displayMode: .spread,
                alignment: .coverSingle,
                pageOverrides: [:]
            )
        )
    }
}

func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("エラーを期待", file: file, line: line)
    } catch {
    }
}
