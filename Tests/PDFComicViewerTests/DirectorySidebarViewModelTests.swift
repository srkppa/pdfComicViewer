import XCTest
@testable import PDFComicViewer

@MainActor
final class DirectorySidebarViewModelTests: XCTestCase {
    func testSetRootTriggersScanAndPublishesNodes() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let node = DirectoryTreeNode(url: rootURL.appending(path: "one.pdf"), kind: .pdf)
        let scanner = FakeDirectoryScanner(result: .success([node]))
        let model = DirectorySidebarViewModel(scanner: scanner)

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
        let model = DirectorySidebarViewModel(scanner: scanner)
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
        let model = DirectorySidebarViewModel(scanner: scanner)
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
        let model = DirectorySidebarViewModel(scanner: scanner)

        model.setRoot(firstRoot)
        model.setRoot(secondRoot)
        try await waitUntil { model.isLoading == false }
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(model.nodes, [secondNode])
    }

    func testReloadRescansCurrentRoot() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let scanner = FakeDirectoryScanner(result: .success([]))
        let model = DirectorySidebarViewModel(scanner: scanner)
        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }

        model.reload()
        try await waitUntil { model.isLoading == false }

        let scannedRoots = await scanner.scannedRootURLs
        XCTAssertEqual(scannedRoots.count, 2)
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
