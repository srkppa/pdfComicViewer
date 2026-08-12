import XCTest
@testable import PDFComicViewer

@MainActor
final class DirectorySidebarViewModelTests: XCTestCase {
    func testSetRootTriggersScanAndPublishesNodes() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let node = DirectoryTreeNode(url: rootURL.appending(path: "one.pdf"), kind: .pdf)
        let scanner = FakeDirectoryScanner(result: .success([node]))
        let model = makeModel(scanner: scanner)

        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }

        XCTAssertEqual(model.rootURL, rootURL.standardizedFileURL)
        XCTAssertEqual(model.nodes, [node])
        XCTAssertNil(model.errorMessage)
        let scannedRoots = await scanner.scannedRootURLs
        XCTAssertEqual(scannedRoots, [rootURL.standardizedFileURL])
    }

    func testSettingSameRootDoesNotRescan() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let scanner = FakeDirectoryScanner(result: .success([]))
        let model = makeModel(scanner: scanner)
        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }

        model.setRoot(rootURL)
        try await Task.sleep(for: .milliseconds(20))

        let scannedRoots = await scanner.scannedRootURLs
        XCTAssertEqual(scannedRoots.count, 1)
    }

    func testFailedScanPublishesErrorMessageAndClearsNodes() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let node = DirectoryTreeNode(url: rootURL.appending(path: "one.pdf"), kind: .pdf)
        let scanner = FakeDirectoryScanner(result: .success([node]))
        let model = makeModel(scanner: scanner)
        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }
        let otherRoot = URL(fileURLWithPath: "/tmp/other")
        await scanner.setResult(.failure(DirectoryScanError.unreadableFolder), forRoot: otherRoot)

        model.setRoot(otherRoot)
        try await waitUntil { model.isLoading == false }

        XCTAssertTrue(model.nodes.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    func testOnlyLatestScanResultIsApplied() async throws {
        let firstRoot = URL(fileURLWithPath: "/tmp/first")
        let secondRoot = URL(fileURLWithPath: "/tmp/second")
        let firstNode = DirectoryTreeNode(url: firstRoot.appending(path: "first.pdf"), kind: .pdf)
        let secondNode = DirectoryTreeNode(url: secondRoot.appending(path: "second.pdf"), kind: .pdf)
        let scanner = FakeDirectoryScanner(result: .success([firstNode]))
        await scanner.setDelay(.milliseconds(100), forRoot: firstRoot.standardizedFileURL)
        await scanner.setResult(.success([secondNode]), forRoot: secondRoot.standardizedFileURL)
        let model = makeModel(scanner: scanner)

        model.setRoot(firstRoot)
        model.setRoot(secondRoot)
        try await waitUntil { model.isLoading == false }
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(model.nodes, [secondNode])
    }

    func testReloadRescansCurrentRoot() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let scanner = FakeDirectoryScanner(result: .success([]))
        let model = makeModel(scanner: scanner)
        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }

        model.reload()
        try await waitUntil { model.isLoading == false }

        let scannedRoots = await scanner.scannedRootURLs
        XCTAssertEqual(scannedRoots.count, 2)
    }

    func testDisplayOptionsDefaultToNameAscendingAndHiddenDate() {
        let model = makeModel(scanner: FakeDirectoryScanner(result: .success([])))

        XCTAssertEqual(model.sortKey, .name)
        XCTAssertEqual(model.sortDirection, .ascending)
        XCTAssertFalse(model.showsModificationDate)
    }

    func testSortedNodesReflectsSortKeyAndDirection() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let nodeB = DirectoryTreeNode(url: rootURL.appending(path: "b.pdf"), kind: .pdf)
        let nodeA = DirectoryTreeNode(url: rootURL.appending(path: "a.pdf"), kind: .pdf)
        let scanner = FakeDirectoryScanner(result: .success([nodeB, nodeA]))
        let model = makeModel(scanner: scanner)
        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }

        XCTAssertEqual(model.sortedNodes.map(\.name), ["a.pdf", "b.pdf"])

        model.sortDirection = model.sortDirection.toggled

        XCTAssertEqual(model.sortedNodes.map(\.name), ["b.pdf", "a.pdf"])
    }

    func testPDFURLsExcludesFolders() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let pdfURL = rootURL.appending(path: "one.pdf")
        let folderURL = rootURL.appending(path: "series")
        let pdf = DirectoryTreeNode(url: pdfURL, kind: .pdf)
        let folder = DirectoryTreeNode(url: folderURL, kind: .folder, children: [])
        let scanner = FakeDirectoryScanner(result: .success([folder, pdf]))
        let model = makeModel(scanner: scanner)
        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }

        let urls = model.pdfURLs(for: [pdf.id, folder.id])

        XCTAssertEqual(urls, [pdfURL])
    }

    func testResetProgressSetsLastPageIndexToZero() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let pdfURL = rootURL.appending(path: "one.pdf")
        let store = FakeSidebarProgressStore(records: [
            .fixture(path: pdfURL.standardizedFileURL.path, lastPageIndex: 42)
        ])
        let model = makeModel(
            scanner: FakeDirectoryScanner(result: .success([])),
            progressStore: store
        )

        await model.resetProgress(for: [pdfURL])

        let reloaded = try await store.load(for: pdfURL)
        XCTAssertEqual(reloaded?.preferences.lastPageIndex, 0)
    }

    func testResetProgressIgnoresURLsWithoutRecord() async throws {
        let store = FakeSidebarProgressStore()
        let model = makeModel(
            scanner: FakeDirectoryScanner(result: .success([])),
            progressStore: store
        )

        await model.resetProgress(for: [URL(fileURLWithPath: "/tmp/comics/unknown.pdf")])

        let records = try await store.allRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testTrashMovesFilesRemovesRecordsAndRescans() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let pdfURL = rootURL.appending(path: "one.pdf")
        let store = FakeSidebarProgressStore(records: [
            .fixture(path: pdfURL.standardizedFileURL.path, lastPageIndex: 3)
        ])
        let trash = FakeFileTrash()
        let scanner = FakeDirectoryScanner(result: .success([]))
        let model = makeModel(scanner: scanner, progressStore: store, trashService: trash)
        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }

        let failureCount = await model.trash(urls: [pdfURL])
        try await waitUntil { model.isLoading == false }

        XCTAssertEqual(failureCount, 0)
        let trashed = await trash.trashedURLs
        XCTAssertEqual(trashed, [pdfURL])
        let removed = await store.removedURLs
        XCTAssertEqual(removed, [pdfURL])
        let scannedRoots = await scanner.scannedRootURLs
        XCTAssertEqual(scannedRoots.count, 2)
    }

    func testTrashKeepsRecordsForFilesThatFailed() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let okURL = rootURL.appending(path: "ok.pdf")
        let failingURL = rootURL.appending(path: "locked.pdf")
        let store = FakeSidebarProgressStore(records: [
            .fixture(path: okURL.standardizedFileURL.path, lastPageIndex: 1),
            .fixture(path: failingURL.standardizedFileURL.path, lastPageIndex: 2)
        ])
        let trash = FakeFileTrash(failingURLs: [failingURL])
        let model = makeModel(
            scanner: FakeDirectoryScanner(result: .success([])),
            progressStore: store,
            trashService: trash
        )
        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }

        let failureCount = await model.trash(urls: [okURL, failingURL])

        XCTAssertEqual(failureCount, 1)
        let removed = await store.removedURLs
        XCTAssertEqual(removed, [okURL])
    }

    func testTrashWithEmptyInputDoesNothing() async throws {
        let trash = FakeFileTrash()
        let scanner = FakeDirectoryScanner(result: .success([]))
        let model = makeModel(scanner: scanner, trashService: trash)
        model.setRoot(URL(fileURLWithPath: "/tmp/comics"))
        try await waitUntil { model.isLoading == false }

        let failureCount = await model.trash(urls: [])

        XCTAssertEqual(failureCount, 0)
        let scannedRoots = await scanner.scannedRootURLs
        XCTAssertEqual(scannedRoots.count, 1)
    }

    private func makeModel(
        scanner: any DirectoryScanning,
        progressStore: any ReadingProgressStoring = FakeSidebarProgressStore(),
        trashService: any FileTrashing = FakeFileTrash()
    ) -> DirectorySidebarViewModel {
        DirectorySidebarViewModel(
            scanner: scanner,
            progressStore: progressStore,
            trashService: trashService
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else {
                return XCTFail("条件が期限内に成立しませんでした")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor FakeSidebarProgressStore: ReadingProgressStoring {
    private var recordsByPath: [String: DocumentRecord] = [:]
    private(set) var removedURLs: [URL] = []

    init(records: [DocumentRecord] = []) {
        for record in records {
            recordsByPath[record.normalizedPath] = record
        }
    }

    func load(for url: URL) throws -> DocumentRecord? {
        recordsByPath[url.standardizedFileURL.path]
    }

    func save(_ record: DocumentRecord) throws {
        recordsByPath[record.normalizedPath] = record
    }

    func allRecords() throws -> [DocumentRecord] {
        Array(recordsByPath.values)
    }

    func remove(for url: URL) throws {
        removedURLs.append(url)
        recordsByPath[url.standardizedFileURL.path] = nil
    }
}

private actor FakeFileTrash: FileTrashing {
    private var failingURLs: Set<URL> = []
    private(set) var trashedURLs: [URL] = []

    init(failingURLs: Set<URL> = []) {
        self.failingURLs = failingURLs
    }

    func trash(_ urls: [URL]) async -> [URL] {
        trashedURLs.append(contentsOf: urls)
        return urls.filter { failingURLs.contains($0) }
    }
}

private extension DocumentRecord {
    static func fixture(path: String, lastPageIndex: Int) -> DocumentRecord {
        var preferences = DocumentPreferences.defaults
        preferences.lastPageIndex = lastPageIndex
        return DocumentRecord(
            bookmarkData: Data("bookmark".utf8),
            normalizedPath: path,
            metadata: FileMetadata(
                size: 1_024,
                modificationDate: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            preferences: preferences
        )
    }
}

private actor FakeDirectoryScanner: DirectoryScanning {
    private var defaultResult: Result<[DirectoryTreeNode], Error>
    private var resultsByRoot: [URL: Result<[DirectoryTreeNode], Error>] = [:]
    private var delaysByRoot: [URL: Duration] = [:]
    private(set) var scannedRootURLs: [URL] = []

    init(result: Result<[DirectoryTreeNode], Error>) {
        self.defaultResult = result
    }

    func scan(rootURL: URL) async throws -> [DirectoryTreeNode] {
        let normalized = rootURL.standardizedFileURL
        scannedRootURLs.append(normalized)
        if let delay = delaysByRoot[normalized] {
            try await Task.sleep(for: delay)
        }
        switch resultsByRoot[normalized] ?? defaultResult {
        case .success(let nodes):
            return nodes
        case .failure(let error):
            throw error
        }
    }

    func setResult(_ result: Result<[DirectoryTreeNode], Error>, forRoot root: URL) {
        resultsByRoot[root] = result
    }

    func setDelay(_ delay: Duration, forRoot root: URL) {
        delaysByRoot[root] = delay
    }
}
