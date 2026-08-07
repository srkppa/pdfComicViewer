# ディレクトリサイドバー実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ウインドウ右側に開閉可能なディレクトリツリーサイドバーを追加してPDFを選んで開けるようにし、開いているPDFを閉じて空の状態へ戻す機能を追加する。

**Architecture:** 既存の単一ドキュメント表示ロジック（`ReaderViewModel`）はそのまま維持し、フォルダ走査とツリー状態を持つ独立した `DirectorySidebarViewModel` を新設する。`ReaderView` が両方の ViewModel を仲介し、開いたPDFの親フォルダへサイドバーのルートを自動追従させる。サイドバーからのPDF選択は既存の `model.open(url:)` をそのまま呼ぶため、パスワード入力・置き換え確認などの既存フローに変更は不要。

**Tech Stack:** Swift 6 / SwiftUI / PDFKit / XCTest（既存スタックのまま、新規依存追加なし）

## Global Constraints

- macOS 15.0以降、Swift 6.0以降（既存の `Package.swift` のまま）
- UI文字列はすべて日本語（既存コードベースの一貫した方針）
- 複数PDFの同時タブ表示は対象外。表示は「1つのPDFを表示する」単一ドキュメントモデルを維持する
- サイドバーの状態（ルートフォルダ、開閉、展開ノード）はアプリ再起動をまたいで永続化しない
- サイドバー幅は固定260pt（リサイズ不可）
- 非サンドボックスのローカルビルドのため、セキュリティスコープ付きブックマークなどサンドボックス専用APIは不要
- 新規の非同期処理は既存の `PDFDocumentLoader` / `ReaderViewModel` と同じ「世代カウンタで後勝ちを判定し、古い結果を無視する」パターンに従う（`Task.detached` はバックグラウンド処理専用に留め、明示的なタスクキャンセル連鎖には依存しない）

---

### Task 1: DirectoryTreeNode データモデル

**Files:**
- Create: `Sources/PDFComicViewer/Directory/DirectoryTreeNode.swift`
- Test: `Tests/PDFComicViewerTests/DirectoryTreeNodeTests.swift`

**Interfaces:**
- Produces: `struct DirectoryTreeNode: Identifiable, Equatable, Sendable` with `let id: String`, `let url: URL`, `let name: String`, `let kind: Kind`（`enum Kind: Equatable, Sendable { case folder, pdf }`）, `var children: [DirectoryTreeNode]?`。イニシャライザは `init(url: URL, kind: Kind, children: [DirectoryTreeNode]? = nil)` で、`id` は `url.standardizedFileURL.path`、`name` は `url.lastPathComponent` から自動導出される。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/DirectoryTreeNodeTests.swift`:

```swift
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
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `swift test --filter DirectoryTreeNodeTests`
Expected: FAIL（`DirectoryTreeNode` が存在しないためビルドエラー）

- [ ] **Step 3: 最小実装を書く**

`Sources/PDFComicViewer/Directory/DirectoryTreeNode.swift`:

```swift
import Foundation

struct DirectoryTreeNode: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case folder
        case pdf
    }

    let id: String
    let url: URL
    let name: String
    let kind: Kind
    var children: [DirectoryTreeNode]?

    init(url: URL, kind: Kind, children: [DirectoryTreeNode]? = nil) {
        self.id = url.standardizedFileURL.path
        self.url = url
        self.name = url.lastPathComponent
        self.kind = kind
        self.children = children
    }
}
```

- [ ] **Step 4: テストを実行して成功を確認する**

Run: `swift test --filter DirectoryTreeNodeTests`
Expected: PASS

- [ ] **Step 5: コミットする**

```bash
git add Sources/PDFComicViewer/Directory/DirectoryTreeNode.swift Tests/PDFComicViewerTests/DirectoryTreeNodeTests.swift
git commit -m "feat: add DirectoryTreeNode data model

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: DirectoryScanning プロトコルとライブ実装

**Files:**
- Create: `Sources/PDFComicViewer/Directory/DirectoryScanning.swift`
- Test: `Tests/PDFComicViewerTests/DirectoryScannerTests.swift`

**Interfaces:**
- Consumes: `DirectoryTreeNode`（Task 1）
- Produces: `protocol DirectoryScanning: Sendable { func scan(rootURL: URL) async throws -> [DirectoryTreeNode] }`、ライブ実装 `struct DirectoryScanner: DirectoryScanning`、`enum DirectoryScanError: LocalizedError { case unreadableFolder }`（`errorDescription` は日本語メッセージ「フォルダを読み込めません。」）。Task 3 はこの protocol を DI 経由で利用する。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/DirectoryScannerTests.swift`:

```swift
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
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `swift test --filter DirectoryScannerTests`
Expected: FAIL（`DirectoryScanner` / `DirectoryScanning` / `DirectoryScanError` が存在しないためビルドエラー）

- [ ] **Step 3: 最小実装を書く**

`Sources/PDFComicViewer/Directory/DirectoryScanning.swift`:

```swift
import Foundation

protocol DirectoryScanning: Sendable {
    func scan(rootURL: URL) async throws -> [DirectoryTreeNode]
}

enum DirectoryScanError: LocalizedError {
    case unreadableFolder

    var errorDescription: String? {
        switch self {
        case .unreadableFolder:
            "フォルダを読み込めません。"
        }
    }
}

struct DirectoryScanner: DirectoryScanning {
    func scan(rootURL: URL) async throws -> [DirectoryTreeNode] {
        try await Task.detached(priority: .userInitiated) {
            try Self.scanChildren(of: rootURL)
        }.value
    }

    private static func scanChildren(of url: URL) throws -> [DirectoryTreeNode] {
        let fileManager = FileManager.default
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw DirectoryScanError.unreadableFolder
        }

        var folderNodes: [DirectoryTreeNode] = []
        var pdfNodes: [DirectoryTreeNode] = []

        for childURL in contents {
            guard let resourceValues = try? childURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ), resourceValues.isSymbolicLink != true else {
                continue
            }

            if resourceValues.isDirectory == true {
                let children = (try? scanChildren(of: childURL)) ?? []
                folderNodes.append(
                    DirectoryTreeNode(url: childURL, kind: .folder, children: children)
                )
            } else if childURL.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
                pdfNodes.append(DirectoryTreeNode(url: childURL, kind: .pdf))
            }
        }

        folderNodes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        pdfNodes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return folderNodes + pdfNodes
    }
}
```

- [ ] **Step 4: テストを実行して成功を確認する**

Run: `swift test --filter DirectoryScannerTests`
Expected: PASS

- [ ] **Step 5: コミットする**

```bash
git add Sources/PDFComicViewer/Directory/DirectoryScanning.swift Tests/PDFComicViewerTests/DirectoryScannerTests.swift
git commit -m "feat: add DirectoryScanner for building PDF folder trees

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: DirectorySidebarViewModel

**Files:**
- Create: `Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift`
- Test: `Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift`

**Interfaces:**
- Consumes: `DirectoryTreeNode`（Task 1）、`DirectoryScanning` / `DirectoryScanError`（Task 2）
- Produces: `@MainActor final class DirectorySidebarViewModel: ObservableObject` with `@Published private(set) var rootURL: URL?`, `@Published private(set) var nodes: [DirectoryTreeNode] = []`, `@Published private(set) var isLoading = false`, `@Published var errorMessage: String?`, `init(scanner: any DirectoryScanning = DirectoryScanner())`, `func setRoot(_ url: URL)`。Task 6（`ReaderView`）はこの型を `@StateObject` として保持し、`setRoot(_:)` を呼び、`errorMessage` へ直接書き込む。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift`:

```swift
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
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `swift test --filter DirectorySidebarViewModelTests`
Expected: FAIL（`DirectorySidebarViewModel` が存在しないためビルドエラー）

- [ ] **Step 3: 最小実装を書く**

`Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift`:

```swift
import Foundation

@MainActor
final class DirectorySidebarViewModel: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var nodes: [DirectoryTreeNode] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let scanner: any DirectoryScanning
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0

    init(scanner: any DirectoryScanning = DirectoryScanner()) {
        self.scanner = scanner
    }

    func setRoot(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard rootURL != normalized else { return }
        rootURL = normalized
        reload()
    }

    private func reload() {
        guard let rootURL else { return }
        scanTask?.cancel()
        scanGeneration += 1
        let generation = scanGeneration
        isLoading = true
        errorMessage = nil
        let scanner = scanner
        scanTask = Task { [weak self] in
            do {
                let scannedNodes = try await scanner.scan(rootURL: rootURL)
                guard let self, generation == self.scanGeneration else { return }
                self.nodes = scannedNodes
                self.isLoading = false
            } catch {
                guard let self, generation == self.scanGeneration else { return }
                self.nodes = []
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 4: テストを実行して成功を確認する**

Run: `swift test --filter DirectorySidebarViewModelTests`
Expected: PASS

- [ ] **Step 5: コミットする**

```bash
git add Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift
git commit -m "feat: add DirectorySidebarViewModel for tree state management

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: ReaderViewModel に closeDocument() を追加

**Files:**
- Modify: `Sources/PDFComicViewer/Reader/ReaderViewModel.swift`
- Test: `Tests/PDFComicViewerTests/ReaderViewModelTests.swift`

**Interfaces:**
- Consumes: 既存の `ReaderViewModel` の private state（`session`, `pagePreviewTask`, `pagePreviewDocumentID`, `pagePreviewSnapshot`）と既存メソッド `flushPendingSaves()`, `rebuildKeepingCurrentPage()`
- Produces: `func closeDocument() async`（`ReaderViewModel` の public API）。Task 6（`ReaderToolbar`）と Task 7（`PDFComicViewerApp`）はこれを `Task { await model.closeDocument() }` の形で呼ぶ。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/ReaderViewModelTests.swift` の末尾（`private func waitUntil` の直前）に追加:

```swift
    func testCloseDocumentFlushesSaveAndResetsState() async throws {
        let url = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, store) = await makeOpenedModel(pageCount: 4, url: url)
        model.next()

        await model.closeDocument()

        XCTAssertNil(model.session)
        XCTAssertEqual(model.currentPhysicalPage, 0)
        XCTAssertTrue(model.displayUnits.isEmpty)
        let savedRecords = await store.savedRecords
        XCTAssertEqual(savedRecords.count, 1)
        XCTAssertEqual(savedRecords[0].preferences.lastPageIndex, 1)
    }

    func testCloseDocumentWithNoOpenDocumentIsNoOp() async {
        let store = FakeProgressStore()
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(.fixture(pageCount: 1))),
            progressStore: store
        )

        await model.closeDocument()

        XCTAssertNil(model.session)
        let savedRecords = await store.savedRecords
        XCTAssertTrue(savedRecords.isEmpty)
    }
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `swift test --filter ReaderViewModelTests`
Expected: FAIL（`closeDocument()` が存在しないためビルドエラー）

- [ ] **Step 3: 最小実装を書く**

`Sources/PDFComicViewer/Reader/ReaderViewModel.swift` の `confirmReplacement(keepPreferences:)` メソッドの直後に追加:

```swift
    func closeDocument() async {
        guard session != nil else { return }
        await flushPendingSaves()
        session = nil
        passwordRequest = nil
        replacementConfirmation = nil
        errorMessage = nil
        warningMessage = nil
        pagePreviewTask?.cancel()
        pagePreviewDocumentID = UUID()
        pagePreviewSnapshot = .empty
        rebuildKeepingCurrentPage()
    }
```

- [ ] **Step 4: テストを実行して成功を確認する**

Run: `swift test --filter ReaderViewModelTests`
Expected: PASS

- [ ] **Step 5: コミットする**

```bash
git add Sources/PDFComicViewer/Reader/ReaderViewModel.swift Tests/PDFComicViewerTests/ReaderViewModelTests.swift
git commit -m "feat: add ReaderViewModel.closeDocument()

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: DirectorySidebarView（ツリーUI）

**Files:**
- Create: `Sources/PDFComicViewer/UI/DirectorySidebarView.swift`

**Interfaces:**
- Consumes: `DirectorySidebarViewModel`（Task 3）, `DirectoryTreeNode`（Task 1）, `ReaderTheme`（`ReaderToolbar.swift` 内で既に定義済み）
- Produces: `@MainActor struct DirectorySidebarView: View` with `init(model: DirectorySidebarViewModel, currentFileURL: URL?, chooseFolder: @escaping () -> Void, openPDF: @escaping (URL) -> Void)`。Task 6（`ReaderView`）がこれをサイドバーパネルとして配置する。

このタスクは既存コードベースの慣行（`ReaderView` / `ReaderToolbar` など、View自体に切り出せるロジックがない場合はテスト対象外）に従い、自動テストなしでビルド確認のみ行う。

- [ ] **Step 1: 実装する**

`Sources/PDFComicViewer/UI/DirectorySidebarView.swift`:

```swift
import SwiftUI

@MainActor
struct DirectorySidebarView: View {
    @ObservedObject var model: DirectorySidebarViewModel
    let currentFileURL: URL?
    let chooseFolder: () -> Void
    let openPDF: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxHeight: .infinity)
        .background(ReaderTheme.surface)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(ReaderTheme.secondaryText)
                .accessibilityHidden(true)
            Text(model.rootURL?.lastPathComponent ?? "フォルダ未選択")
                .font(.callout.weight(.medium))
                .foregroundStyle(ReaderTheme.primaryText)
                .lineLimit(1)
            Spacer()
            Button(action: chooseFolder) {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(ReaderTheme.primaryText)
            .accessibilityLabel("フォルダを選択")
            .help("フォルダを選択")
        }
        .padding(10)
    }

    @ViewBuilder
    private var content: some View {
        if model.rootURL == nil {
            emptyRootState
        } else if model.isLoading && model.nodes.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(ReaderTheme.secondaryText)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if model.nodes.isEmpty {
            Text("PDFが見つかりません")
                .font(.callout)
                .foregroundStyle(ReaderTheme.secondaryText)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List(model.nodes, children: \.children) { node in
                row(for: node)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for node: DirectoryTreeNode) -> some View {
        let isCurrent = node.kind == .pdf
            && node.url.standardizedFileURL == currentFileURL?.standardizedFileURL
        return HStack(spacing: 6) {
            Image(systemName: node.kind == .folder ? "folder" : "doc.richtext")
                .foregroundStyle(isCurrent ? ReaderTheme.accent : ReaderTheme.secondaryText)
                .accessibilityHidden(true)
            Text(node.name)
                .foregroundStyle(isCurrent ? ReaderTheme.accent : ReaderTheme.primaryText)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard node.kind == .pdf else { return }
            openPDF(node.url)
        }
        .accessibilityLabel(node.name)
        .accessibilityAddTraits(node.kind == .pdf ? .isButton : [])
    }

    private var emptyRootState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ReaderTheme.secondaryText)
                .accessibilityHidden(true)
            Text("フォルダを選ぶと\nPDFの一覧を表示します")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(ReaderTheme.secondaryText)
            Button("フォルダを選択…", action: chooseFolder)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
```

- [ ] **Step 2: ビルドを確認する**

Run: `swift build`
Expected: ビルド成功（エラーなし）

- [ ] **Step 3: コミットする**

```bash
git add Sources/PDFComicViewer/UI/DirectorySidebarView.swift
git commit -m "feat: add DirectorySidebarView tree UI

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: ReaderToolbar と ReaderView にサイドバーを配線する

`ReaderToolbar` の変更と `ReaderView` の変更は互いに依存し合う（`ReaderToolbar` の新しい必須パラメータを `ReaderView` の2箇所の呼び出しが同時に満たす必要がある）ため、ビルドが常に通る状態を保てるよう1タスクにまとめる。

**Files:**
- Modify: `Sources/PDFComicViewer/UI/ReaderToolbar.swift`
- Modify: `Sources/PDFComicViewer/UI/ReaderView.swift`

**Interfaces:**
- Consumes: `DirectorySidebarViewModel`（Task 3）, `DirectorySidebarView`（Task 5）, `ReaderViewModel.closeDocument()`（Task 4）
- Produces: `ReaderToolbar` の `init` に `sidebarIsVisible: Binding<Bool>` パラメータを追加する（`keyboardFocusChange` の前に追加し、デフォルト値なしの必須パラメータとする）。Task 7（`PDFComicViewerApp`）はこのタスクで追加される `ReaderViewModel.closeDocument()` の呼び出し方をそのまま踏襲する。

- [ ] **Step 1: 実装する**

`Sources/PDFComicViewer/UI/ReaderToolbar.swift` の `struct ReaderToolbar` を以下のように変更する。

まず `struct ReaderToolbar` の宣言部分（1〜50行目付近）を置き換える:

```swift
@MainActor
struct ReaderToolbar: View {
    @ObservedObject var model: ReaderViewModel
    @Binding var sidebarIsVisible: Bool
    @FocusState private var focusedControl: FocusedReaderControl?

    let keyboardFocusChange: (Bool) -> Void

    init(
        model: ReaderViewModel,
        sidebarIsVisible: Binding<Bool>,
        keyboardFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self._sidebarIsVisible = sidebarIsVisible
        self.keyboardFocusChange = keyboardFocusChange
    }
```

次に `body` 内、`Text(pageCounterText)` の直後・「全画面表示を切り替える」ボタンの前にある `Divider().frame(height: 20)` の前に、以下を挿入する:

```swift
            Divider().frame(height: 20)

            iconButton(
                "PDFを閉じる",
                systemImage: "xmark.circle",
                action: { Task { await model.closeDocument() } }
            )
            .disabled(model.session == nil)
            .focused($focusedControl, equals: .close)

            iconButton(
                sidebarIsVisible ? "フォルダ一覧を隠す" : "フォルダ一覧を表示",
                systemImage: "sidebar.right",
                action: { sidebarIsVisible.toggle() }
            )
            .focused($focusedControl, equals: .sidebar)
```

最後に `private enum FocusedReaderControl: Hashable` に2ケースを追加する:

```swift
private enum FocusedReaderControl: Hashable {
    case open
    case binding
    case displayMode
    case alignment
    case zoomOut
    case fit
    case zoomIn
    case close
    case sidebar
    case fullScreen
}
```

- [ ] **Step 2: `ReaderView` の `@State` 宣言を追加する**

`Sources/PDFComicViewer/UI/ReaderView.swift` の `struct ReaderView` 冒頭の `@State` 宣言群に以下を追加する:

```swift
    @StateObject private var sidebarModel = DirectorySidebarViewModel()
    @State private var sidebarIsVisible = false
    @State private var folderImporterIsPresented = false
```

`var body: some View` を以下のように変更する（既存の `ZStack { ... }` 全体を `HStack` で包み、末尾にサイドバーパネルを追加する）:

```swift
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                ReaderTheme.canvas.ignoresSafeArea()

                readerArea

                if model.isLoading {
                    loadingOverlay
                }

                if let warningMessage = model.warningMessage {
                    warningBanner(warningMessage)
                }

                if isFullScreen, controlsVisible {
                    VStack {
                        ReaderToolbar(
                            model: model,
                            sidebarIsVisible: $sidebarIsVisible,
                            keyboardFocusChange: { focused in
                                toolbarControlHasKeyboardFocus = focused
                            }
                        )
                            .padding(.top, 12)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if sidebarIsVisible, !isFullScreen {
                Divider()
                DirectorySidebarView(
                    model: sidebarModel,
                    currentFileURL: model.session?.url,
                    chooseFolder: { folderImporterIsPresented = true },
                    openPDF: { url in Task { await model.open(url: url) } }
                )
                .frame(width: 260)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: sidebarIsVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ReaderTheme.canvas)
        .preferredColorScheme(.dark)
        .tint(ReaderTheme.accent)
        .toolbar {
            if !isFullScreen {
                ToolbarItem(placement: .principal) {
                    ReaderToolbar(
                        model: model,
                        sidebarIsVisible: $sidebarIsVisible,
                        keyboardFocusChange: { focused in
                            toolbarControlHasKeyboardFocus = focused
                        }
                    )
                }
            }
        }
        .toolbarVisibility(isFullScreen ? .hidden : .visible, for: .windowToolbar)
        .fileImporter(
            isPresented: $fileImporterIsPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .fileImporter(
            isPresented: $folderImporterIsPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFolderImport
        )
        .dropDestination(for: URL.self) { urls, _ in
            openDroppedPDF(from: urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .sheet(isPresented: passwordSheetIsPresented) {
            PasswordSheet(
                errorMessage: model.errorMessage,
                submit: { password in
                    Task { await model.unlock(password: password) }
                },
                cancel: model.cancelUnlock
            )
            .interactiveDismissDisabled()
        }
        .alert("PDFが置き換えられています", isPresented: $replacementPromptIsPresented) {
            Button("読書位置と設定を引き継ぐ") {
                confirmReplacement(keepPreferences: true)
            }
            Button("新しいPDFとして開く") {
                confirmReplacement(keepPreferences: false)
            }
        } message: {
            Text("以前の読書位置と設定を引き継ぎますか？")
        }
        .alert("PDFを開けません", isPresented: errorAlertIsPresented) {
            Button("別のPDFを選ぶ") {
                model.errorMessage = nil
                fileImporterIsPresented = true
            }
            Button("閉じる", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "別のPDFを選んでください。")
        }
        .onChange(of: model.fileOpenRequestSequence) { _, _ in
            fileImporterIsPresented = true
        }
        .onChange(of: model.replacementConfirmation != nil, initial: true) { _, pending in
            if pending {
                replacementPromptIsPresented = true
            }
        }
        .onChange(of: model.session?.url) { _, newURL in
            guard let newURL else { return }
            sidebarModel.setRoot(newURL.deletingLastPathComponent())
        }
        .onChange(of: sidebarModel.rootURL) { oldValue, newValue in
            guard oldValue == nil, newValue != nil else { return }
            sidebarIsVisible = true
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await model.flushPendingSaves() }
        }
    }
```

- [ ] **Step 3: フォルダインポート完了ハンドラを追加する**

`private func handleFileImport(_ result: Result<[URL], any Error>) { ... }` の直後に追加する:

```swift
    private func handleFolderImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            sidebarModel.setRoot(url)
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            sidebarModel.errorMessage = "フォルダを選択できませんでした。"
        }
    }
```

- [ ] **Step 4: ビルドを確認する**

Run: `swift build`
Expected: ビルド成功（エラーなし）

- [ ] **Step 5: 既存の自動テストがすべて通ることを確認する**

Run: `swift test`
Expected: PASS（すべてのテストが成功する。UIレイアウト変更のみでロジック変更はないため既存テストへの影響はない）

- [ ] **Step 6: コミットする**

```bash
git add Sources/PDFComicViewer/UI/ReaderToolbar.swift Sources/PDFComicViewer/UI/ReaderView.swift
git commit -m "feat: wire directory sidebar into ReaderToolbar and ReaderView

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: File メニューに「PDFを閉じる」を追加する

**Files:**
- Modify: `Sources/PDFComicViewer/App/PDFComicViewerApp.swift`

**Interfaces:**
- Consumes: `ReaderViewModel.closeDocument()`（Task 4）
- Produces: なし（メニュー項目の追加のみ）

- [ ] **Step 1: 実装する**

`Sources/PDFComicViewer/App/PDFComicViewerApp.swift` の `CommandGroup(replacing: .newItem)` ブロックを以下のように変更する:

```swift
        CommandGroup(replacing: .newItem) {
            Button("PDFを開く…") {
                model.requestFileOpen()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("PDFを閉じる") {
                Task { await model.closeDocument() }
            }
            .disabled(model.session == nil)
        }
```

- [ ] **Step 2: ビルドを確認する**

Run: `swift build`
Expected: ビルド成功

- [ ] **Step 3: コミットする**

```bash
git add Sources/PDFComicViewer/App/PDFComicViewerApp.swift
git commit -m "feat: add close document menu item

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: README を更新する

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: なし
- Produces: なし（ドキュメントのみ）

- [ ] **Step 1: 「主な特徴」に項目を追加する**

`README.md` の「主な特徴」箇条書き（`- キーボード、クリック、ドラッグによる操作` の直後）に追加する:

```markdown
- 右側のディレクトリサイドバーからPDFを選んで開く（開閉可能）
```

- [ ] **Step 2: 「基本操作」に閉じる操作とサイドバー操作を追記する**

`README.md` の「基本操作」箇条書きの末尾（`- 全画面表示の切り替え: ...` の直後）に追加する:

```markdown
- PDFを閉じる: ツールバーの「PDFを閉じる」、またはFileメニューの「PDFを閉じる」
- ディレクトリサイドバーの表示切り替え: ツールバーの「フォルダ一覧を表示／隠す」
```

さらに、「基本操作」の段落末尾（`綴じ方向、表示方法、...` の段落の後）に新しい段落を追加する:

```markdown

ウインドウ右側のディレクトリサイドバーには、開いているPDFの親フォルダ以下がツリー表示されます。PDFをクリックすると開き、フォルダの三角マークで展開・折りたたみができます。サイドバー右上のフォルダアイコンから、直接フォルダを選ぶこともできます。
```

- [ ] **Step 3: コミットする**

```bash
git add README.md
git commit -m "docs: document directory sidebar and close document features

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: 最終確認

**Files:** なし（検証のみ）

**Interfaces:** なし

- [ ] **Step 1: 全自動テストを実行する**

Run: `swift test`
Expected: PASS（すべてのテストが成功する）

- [ ] **Step 2: Releaseビルドを確認する**

Run: `scripts/build-app.sh`
Expected: `build/PDFComicViewer.app` が生成される

- [ ] **Step 3: 手動でアプリを起動し、3つの新機能を確認する**

Run: `open build/PDFComicViewer.app`

確認項目:
- PDFを1つ開くと、右側にそのPDFの親フォルダがサイドバーとして自動的に開く
- サイドバーのツリーでPDFをクリックすると表示が切り替わり、フォルダの三角マークで展開・折りたたみができる
- サイドバー右上のフォルダアイコンから、任意のフォルダを直接選べる
- ツールバーの「フォルダ一覧を表示／隠す」ボタンでサイドバーが開閉する
- ツールバーの「PDFを閉じる」ボタンとFileメニューの「PDFを閉じる」で、表示がドロップ待ちの空状態に戻る（サイドバーの選択状態は維持される）

Expected: すべて期待通りに動作する

- [ ] **Step 4: 問題がなければ完了を報告する**

新規コミットは不要（Task 1〜8 ですべてコミット済み）。動作確認で問題が見つかった場合は該当タスクに戻って修正し、再度コミットする。
