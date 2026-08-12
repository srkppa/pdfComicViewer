# 次の巻へ自動遷移・絞り込み検索 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PDF漫画ビューアーに、シリーズ最後のページで「次へ」を押したときに同じフォルダの次のPDFへ自動的に進む機能と、サイドバーのPDF一覧をファイル名・フォルダ名で絞り込む検索機能を追加する。

**Architecture:** ディレクトリI/Oを伴う処理と、配列から答えを選ぶだけの純粋ロジックを分離する（既存の`DirectoryTreeNode.sorted(by:direction:)`と同じ方針）。次の巻の探索はサイドバーの走査状態に依存しない独立した仕組みとし、`ReaderViewModel`にコンストラクタ注入する。検索の絞り込みはサイドバーのツリー構造に対する純粋関数として実装し、`DirectorySidebarViewModel`が並べ替えと合成する。

**Tech Stack:** Swift 6.0 / SwiftUI / AppKit / XCTest / Swift Package Manager

## Global Constraints

- プラットフォームは macOS 15 以上（`Package.swift` の `platforms: [.macOS(.v15)]`）。Swift tools version は 6.0。
- Swift 6 の strict concurrency を満たすこと。アクター境界を越える値は `Sendable` であること。
- ユーザーに見えるテキスト（ボタン名、メニュー項目、ツールチップ、エラー文言、プレースホルダ）はすべて日本語。
- コード内のコメントは日本語で、「なぜそうしたか」を書く。自明な処理の説明は書かない。
- テストは `swift test` で全件パスすること。着手前の基準は 163 件。
- 「次の巻」の判定は開いているPDFと同じフォルダ直下のみを対象とし、サブフォルダをまたがない。順序は常にファイル名の`localizedStandardCompare`昇順（サイドバーの並べ替え設定には影響されない）。
- 検索の一致判定は大文字・小文字を無視した部分一致（`localizedCaseInsensitiveContains`）。フォルダ名が一致したら中身は絞らず全部残す。
- コミットメッセージは英語の Conventional Commits 形式とし、末尾に次の行を入れる。

```
Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
```

---

## ファイル構成

### 新規作成

| ファイル | 責務 |
|---|---|
| `Sources/PDFComicViewer/Directory/SeriesNavigating.swift` | 「次のPDF」を選ぶ純粋関数（`SeriesNavigation`）と、それを使うディレクトリ読み込みのプロトコル・ライブ実装（`SeriesNavigating` / `SeriesNavigator`） |
| `Tests/PDFComicViewerTests/SeriesNavigationTests.swift` | 純粋関数のテスト（I/Oなし） |
| `Tests/PDFComicViewerTests/SeriesNavigatingTests.swift` | ライブ実装のテスト（一時ディレクトリを使うI/Oあり） |

### 変更

| ファイル | 変更内容 |
|---|---|
| `Sources/PDFComicViewer/Reader/ReaderViewModel.swift` | `seriesNavigator`を注入。`next()`に、最後の表示単位で「次へ」を押したときの自動遷移分岐を追加 |
| `Sources/PDFComicViewer/App/PDFComicViewerApp.swift` | `AppServices`が`SeriesNavigator()`を明示的に渡す |
| `Sources/PDFComicViewer/Directory/DirectoryTreeNode.swift` | `[DirectoryTreeNode].filtered(byQuery:)`を追加 |
| `Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift` | `searchQuery`・`displayedNodes`を追加、`setRoot`で`searchQuery`をリセット |
| `Sources/PDFComicViewer/UI/DirectorySidebarView.swift` | 検索欄の追加、一覧表示を`sortedNodes`から`displayedNodes`へ |
| `Tests/PDFComicViewerTests/ReaderViewModelTests.swift` | 追加テスト、既存の`testNextAtLastUnitStaysAtLastUnit`をフェイク注入に変更 |
| `Tests/PDFComicViewerTests/DirectoryTreeNodeTests.swift` | 追加テスト |
| `Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift` | 追加テスト |
| `README.md` | 追加機能の説明 |

---

### Task 1: 次のURLを選ぶ純粋ロジック

**Files:**
- Create: `Sources/PDFComicViewer/Directory/SeriesNavigating.swift`
- Test: `Tests/PDFComicViewerTests/SeriesNavigationTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `SeriesNavigation.nextURL(after current: URL, in sortedURLs: [URL]) -> URL?`

ソート済みURL配列の中から`current`の次の要素を返す。`current`が見つからない、または既に最後なら`nil`。呼び出し側の正規化が揃っていない場合に備え、内部で`standardizedFileURL`同士を比較する。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/SeriesNavigationTests.swift`を新規作成する。

```swift
import XCTest
@testable import PDFComicViewer

final class SeriesNavigationTests: XCTestCase {
    func testNextURLReturnsFollowingElement() {
        let urls = [
            URL(fileURLWithPath: "/tmp/1.pdf"),
            URL(fileURLWithPath: "/tmp/2.pdf"),
            URL(fileURLWithPath: "/tmp/3.pdf")
        ]

        let next = SeriesNavigation.nextURL(after: urls[0], in: urls)

        XCTAssertEqual(next, urls[1])
    }

    func testNextURLReturnsNilAtLastElement() {
        let urls = [
            URL(fileURLWithPath: "/tmp/1.pdf"),
            URL(fileURLWithPath: "/tmp/2.pdf")
        ]

        let next = SeriesNavigation.nextURL(after: urls[1], in: urls)

        XCTAssertNil(next)
    }

    func testNextURLReturnsNilWhenCurrentIsNotInList() {
        let urls = [URL(fileURLWithPath: "/tmp/1.pdf")]

        let next = SeriesNavigation.nextURL(
            after: URL(fileURLWithPath: "/tmp/missing.pdf"),
            in: urls
        )

        XCTAssertNil(next)
    }

    func testNextURLReturnsNilForEmptyList() {
        let next = SeriesNavigation.nextURL(
            after: URL(fileURLWithPath: "/tmp/1.pdf"),
            in: []
        )

        XCTAssertNil(next)
    }

    func testNextURLComparesStandardizedURLs() {
        // 呼び出し側の正規化が揃っていなくても一致判定できることを確認する。
        let urls = [
            URL(fileURLWithPath: "/tmp/./1.pdf"),
            URL(fileURLWithPath: "/tmp/2.pdf")
        ]

        let next = SeriesNavigation.nextURL(
            after: URL(fileURLWithPath: "/tmp/1.pdf"),
            in: urls
        )

        XCTAssertEqual(next, urls[1])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter SeriesNavigationTests`
Expected: FAIL（`cannot find 'SeriesNavigation' in scope` でビルドエラー）

- [ ] **Step 3: 最小限の実装を書く**

`Sources/PDFComicViewer/Directory/SeriesNavigating.swift`を新規作成する。

```swift
import Foundation

/// ソート済みURL配列から「次」を選ぶ純粋ロジック。
/// ディレクトリの読み込み（I/O）とは切り離してテストできるようにする。
enum SeriesNavigation {
    /// `sortedURLs`の中から`current`の次のURLを返す。
    /// `current`が含まれていない、または既に最後なら`nil`。
    static func nextURL(after current: URL, in sortedURLs: [URL]) -> URL? {
        let target = current.standardizedFileURL
        guard let index = sortedURLs.firstIndex(where: { $0.standardizedFileURL == target }) else {
            return nil
        }
        let nextIndex = index + 1
        guard sortedURLs.indices.contains(nextIndex) else { return nil }
        return sortedURLs[nextIndex]
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `swift test --filter SeriesNavigationTests`
Expected: PASS（5件）

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/Directory/SeriesNavigating.swift Tests/PDFComicViewerTests/SeriesNavigationTests.swift
git commit -m "$(cat <<'EOF'
feat: add pure logic for picking the next URL in a sorted list

SeriesNavigation.nextURL(after:in:) is the answer-picking half of
"jump to the next volume" — no filesystem I/O, so it is cheap to test
against every boundary (missing current, last element, empty list)
without touching disk.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 同じフォルダの次のPDFを探すライブ実装

**Files:**
- Modify: `Sources/PDFComicViewer/Directory/SeriesNavigating.swift`
- Test: `Tests/PDFComicViewerTests/SeriesNavigatingTests.swift`

**Interfaces:**
- Consumes: `SeriesNavigation.nextURL(after:in:)`（Task 1）
- Produces:
  - `protocol SeriesNavigating: Sendable { func nextVolumeURL(after url: URL) async -> URL? }`
  - `struct SeriesNavigator: SeriesNavigating`

開いているPDFの親フォルダだけを都度読み直す（サイドバーの走査状態には依存しない）。隠しファイル除外・拡張子`.pdf`のみ・`localizedStandardCompare`で並べ替えという判定基準は、既存の`DirectoryScanner`（`Sources/PDFComicViewer/Directory/DirectoryScanning.swift`）と同じにする。ただしこちらは再帰しない（同じフォルダ直下のみ）。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/SeriesNavigatingTests.swift`を新規作成する。`DirectoryScannerTests.swift`と同じ一時ディレクトリのヘルパーパターンを使う。

```swift
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
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter SeriesNavigatingTests`
Expected: FAIL（`cannot find 'SeriesNavigator' in scope` でビルドエラー）

- [ ] **Step 3: 最小限の実装を書く**

`Sources/PDFComicViewer/Directory/SeriesNavigating.swift`の末尾（`enum SeriesNavigation { ... }`の直後）に追加する。

```swift
protocol SeriesNavigating: Sendable {
    /// 開いているPDFと同じフォルダ直下から、ファイル名順で次のPDFを探す。
    /// サブフォルダはまたがない。見つからなければ`nil`。
    func nextVolumeURL(after url: URL) async -> URL?
}

struct SeriesNavigator: SeriesNavigating {
    func nextVolumeURL(after url: URL) async -> URL? {
        let target = url.standardizedFileURL
        let parent = target.deletingLastPathComponent()
        let siblings = await Task.detached(priority: .userInitiated) {
            Self.pdfSiblings(in: parent)
        }.value
        return SeriesNavigation.nextURL(after: target, in: siblings)
    }

    private static func pdfSiblings(in folder: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let pdfs = contents.filter { childURL in
            guard let resourceValues = try? childURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ), resourceValues.isSymbolicLink != true, resourceValues.isDirectory != true else {
                return false
            }
            return childURL.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame
        }
        return pdfs.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `swift test --filter SeriesNavigatingTests`
Expected: PASS（6件）

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/Directory/SeriesNavigating.swift Tests/PDFComicViewerTests/SeriesNavigatingTests.swift
git commit -m "$(cat <<'EOF'
feat: add SeriesNavigator to find the next PDF in the same folder

Re-reads only the current file's parent directory each time, so it
never depends on whether the sidebar has already scanned that folder.
Filtering rules (skip hidden files and symlinks, .pdf extension only,
localizedStandardCompare order) mirror DirectoryScanner, but this does
not recurse into subfolders.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `ReaderViewModel`への自動遷移の組み込み

**Files:**
- Modify: `Sources/PDFComicViewer/Reader/ReaderViewModel.swift:32-48`（プロパティ・init）
- Modify: `Sources/PDFComicViewer/Reader/ReaderViewModel.swift:144-153`（`next()`）
- Modify: `Sources/PDFComicViewer/App/PDFComicViewerApp.swift:42-45`
- Test: `Tests/PDFComicViewerTests/ReaderViewModelTests.swift`

**Interfaces:**
- Consumes: `SeriesNavigating.nextVolumeURL(after:)`（Task 2）
- Produces: `ReaderViewModel.init(loader:progressStore:seriesNavigator:)` — `seriesNavigator`は既定値`SeriesNavigator()`を持つ

`seriesNavigator`はステートレスな依存（`DirectoryScanning`同様、複数インスタンスを持っても壊れない）なので、`progressStore`とは違い既定値を持たせる。これにより既存の30箇所以上ある`ReaderViewModel(loader:progressStore:)`の呼び出しを書き換えずに済む。ただし、最後の表示単位で`next()`を呼ぶ既存テスト（`testNextAtLastUnitStaysAtLastUnit`）だけは、既定値（実際にファイルシステムを読みに行くライブ実装）に依存すると`/tmp`を実際に読みに行ってしまいテストが非決定的になるため、明示的にフェイクを注入する形に直す。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/ReaderViewModelTests.swift`の末尾、`private final class FakePDFLoader`の定義（現在193行目付近）より前に、フェイクを追加する。

```swift
private actor FakeSeriesNavigator: SeriesNavigating {
    private var nextURLsByCurrentURL: [URL: URL] = [:]
    private(set) var requestedURLs: [URL] = []

    init(nextURLsByCurrentURL: [URL: URL] = [:]) {
        self.nextURLsByCurrentURL = nextURLsByCurrentURL
    }

    func nextVolumeURL(after url: URL) async -> URL? {
        requestedURLs.append(url)
        return nextURLsByCurrentURL[url.standardizedFileURL]
    }
}
```

既存の`testNextAtLastUnitStaysAtLastUnit`（191〜201行目）を、フェイクを明示的に注入する形に書き換える。

```swift
    func testNextAtLastUnitStaysAtLastUnit() async {
        // 既定のSeriesNavigator（実ファイルシステムを読む）に頼ると、
        // 最後の表示単位でnext()を押したときに実際の/tmpを読みに行ってしまい
        // テストが非決定的になる。何も返さないフェイクを明示的に注入する。
        let (model, _) = await makeOpenedModel(
            pageCount: 4,
            seriesNavigator: FakeSeriesNavigator()
        )
        model.next()
        model.next()

        model.next()

        XCTAssertEqual(model.currentUnitIndex, 2)
        XCTAssertEqual(model.currentUnit, .single(3))
        XCTAssertEqual(model.currentPhysicalPage, 3)
    }
```

`makeOpenedModel`（693行目付近）に`seriesNavigator`引数を追加する。

```swift
    private func makeOpenedModel(
        pageCount: Int,
        url: URL = URL(fileURLWithPath: "/tmp/comic.pdf"),
        lastPageIndex: Int = 0,
        seriesNavigator: any SeriesNavigating = FakeSeriesNavigator()
    ) async -> (ReaderViewModel, FakeProgressStore) {
        let session = DocumentSession.fixture(pageCount: pageCount, url: url)
        let store = FakeProgressStore(
            record: .fixture(
                url: url,
                metadata: session.metadata,
                lastPageIndex: lastPageIndex
            )
        )
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(session)),
            progressStore: store,
            seriesNavigator: seriesNavigator
        )
        await model.open(url: url)
        return (model, store)
    }
```

（`seriesNavigator`に既定値`FakeSeriesNavigator()`を与えるのは、`makeOpenedModel`を使う既存の全呼び出し箇所を書き換えずに済ませるため。`ReaderViewModel`本体の既定値`SeriesNavigator()`とは別物であることに注意。）

続けて、自動遷移そのものを検証するテストを`testNextAtLastUnitStaysAtLastUnit`の直後に追加する。

```swift
    func testNextAtLastUnitOpensNextVolumeWhenAvailable() async throws {
        let url = URL(fileURLWithPath: "/tmp/comic-1.pdf")
        let nextURL = URL(fileURLWithPath: "/tmp/comic-2.pdf")
        let navigator = FakeSeriesNavigator(nextURLsByCurrentURL: [url: nextURL])
        let loader = FakePDFLoader(result: .ready(.fixture(pageCount: 1, url: url)))
        loader.resultsByURL[nextURL] = .ready(.fixture(pageCount: 1, url: nextURL))
        let model = ReaderViewModel(
            loader: loader,
            progressStore: FakeProgressStore(),
            seriesNavigator: navigator
        )
        await model.open(url: url)

        model.next()
        try await waitUntil { model.session?.url == nextURL }

        XCTAssertEqual(model.session?.url, nextURL)
        let requested = await navigator.requestedURLs
        XCTAssertEqual(requested, [url])
    }

    func testNextAtLastUnitDoesNothingWhenNoNextVolumeExists() async throws {
        let url = URL(fileURLWithPath: "/tmp/comic-1.pdf")
        let navigator = FakeSeriesNavigator()
        let (model, _) = await makeOpenedModel(
            pageCount: 1,
            url: url,
            seriesNavigator: navigator
        )

        model.next()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.session?.url, url)
        let requested = await navigator.requestedURLs
        XCTAssertEqual(requested, [url])
    }

    func testRepeatedNextAtLastUnitDoesNotStartOverlappingLookups() async throws {
        let url = URL(fileURLWithPath: "/tmp/comic-1.pdf")
        let navigator = FakeSeriesNavigator()
        let (model, _) = await makeOpenedModel(
            pageCount: 1,
            url: url,
            seriesNavigator: navigator
        )

        model.next()
        model.next()
        model.next()
        try await Task.sleep(for: .milliseconds(50))

        // 探索中は同じ処理を二重に始めない。連打しても1回しか問い合わせない。
        let requested = await navigator.requestedURLs
        XCTAssertEqual(requested, [url])
    }
```

`waitUntil`ヘルパーは786行目付近に既に存在する（`private func waitUntil(timeout:condition:) async throws`）。上のテストはそれをそのまま使う——**再定義しないこと**。再定義すると`invalid redeclaration of 'waitUntil'`でビルドが壊れる。

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter ReaderViewModelTests`
Expected: FAIL（`extra argument 'seriesNavigator' in call` などのビルドエラー）

- [ ] **Step 3: 最小限の実装を書く**

`Sources/PDFComicViewer/Reader/ReaderViewModel.swift`の`private let progressStore: any ReadingProgressStoring`（33行目）の直後に追加する。

```swift
    private let seriesNavigator: any SeriesNavigating
```

`private let pagePreviewCache = PagePreviewCache()`の直後、`saveTask`宣言の前に追加する。

```swift
    private var nextVolumeTask: Task<Void, Never>?
```

`init(loader:progressStore:)`（45〜48行目）を差し替える。

```swift
    init(
        loader: any PDFDocumentLoading,
        progressStore: any ReadingProgressStoring,
        seriesNavigator: any SeriesNavigating = SeriesNavigator()
    ) {
        self.loader = loader
        self.progressStore = progressStore
        self.seriesNavigator = seriesNavigator
    }
```

`next()`（144〜153行目）を差し替える。

```swift
    func next() {
        guard !displayUnits.isEmpty else { return }
        let nextIndex = min(currentUnitIndex + 1, displayUnits.count - 1)
        guard nextIndex != currentUnitIndex else {
            advanceToNextVolumeIfPossible()
            return
        }
        currentUnitIndex = nextIndex
        updateCurrentPageFromUnit()
        schedulePagePreviews()
        fitToWindow()
        scheduleSave()
    }

    /// 最後のページで「次へ」を押したときに、同じフォルダの次のPDFへ自動的に進む。
    /// 見つからなければ何もしない。探索中の連打で二重に始めないよう
    /// `nextVolumeTask`でガードする。
    ///
    /// 探索は非同期（ディレクトリI/O）なので、結果が返るまでの間にユーザーが
    /// 別の操作をしている可能性がある。`open(url:)`を呼ぶ前に、探索開始時と
    /// 状態が変わっていないか2つの観点で再確認する。
    /// - `loadGeneration`: open/unlock/closeDocument/confirmReplacementの
    ///   どれが起きても必ず増えるため、文書のライフサイクルが動いたこと
    ///   （別の文書を開いた、閉じた、同じURLを開き直した、など）を一括で
    ///   検知できる。
    /// - `currentUnitIndex`: `previous()`や`jumpToUnit()`によるページ送りは
    ///   `loadGeneration`を変えないため、別途チェックが要る。
    private func advanceToNextVolumeIfPossible() {
        guard nextVolumeTask == nil, let session else { return }
        let startingURL = session.url
        let startingGeneration = loadGeneration
        let startingUnitIndex = currentUnitIndex
        nextVolumeTask = Task { [weak self] in
            defer { self?.nextVolumeTask = nil }
            guard let self,
                  let nextURL = await self.seriesNavigator.nextVolumeURL(after: startingURL),
                  self.loadGeneration == startingGeneration,
                  self.currentUnitIndex == startingUnitIndex else {
                return
            }
            await self.open(url: nextURL)
        }
    }
```

- [ ] **Step 4: `AppServices`を更新する**

`Sources/PDFComicViewer/App/PDFComicViewerApp.swift`の`readerModel`定義（42〜45行目）を差し替える。

```swift
    static let readerModel = ReaderViewModel(
        loader: PDFDocumentLoader(),
        progressStore: progressStore,
        seriesNavigator: SeriesNavigator()
    )
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `swift test`
Expected: PASS（163 + 5 + 6 + 3 = 177件）

- [ ] **Step 6: コミット**

```bash
git add Sources/PDFComicViewer/Reader/ReaderViewModel.swift Sources/PDFComicViewer/App/PDFComicViewerApp.swift Tests/PDFComicViewerTests/ReaderViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: auto-advance to the next volume at the end of a document

next() now tries the next volume in the same folder instead of
no-op'ing when already on the last display unit. A guard task
prevents overlapping lookups from repeated presses, and finding no
next volume degrades to the previous no-op behavior. seriesNavigator
defaults to the live SeriesNavigator so the ~30 existing call sites
that construct ReaderViewModel directly need no changes; only the one
existing test that exercises the "already at last unit" branch gets an
explicit fake, since the live default would otherwise read the real
filesystem during that test.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: サイドバーツリーの絞り込み純粋ロジック

**Files:**
- Modify: `Sources/PDFComicViewer/Directory/DirectoryTreeNode.swift:70-71`（`sorted(by:direction:)`の直後）
- Test: `Tests/PDFComicViewerTests/DirectoryTreeNodeTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `[DirectoryTreeNode].filtered(byQuery: String) -> [DirectoryTreeNode]`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/DirectoryTreeNodeTests.swift`の末尾、`testSortDirectionToggledFlipsBetweenAscendingAndDescending`の直後（クラスの閉じ括弧の前）に追加する。

```swift
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

    func testFilteredByQueryReturnsEmptyForEmptyFolder() {
        let folder = DirectoryTreeNode(
            url: URL(fileURLWithPath: "/tmp/comics/Empty"),
            kind: .folder,
            children: []
        )

        let filtered = [folder].filtered(byQuery: "anything")

        XCTAssertTrue(filtered.isEmpty)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter DirectoryTreeNodeTests`
Expected: FAIL（`value of type '[DirectoryTreeNode]' has no member 'filtered'` でビルドエラー）

- [ ] **Step 3: 最小限の実装を書く**

`Sources/PDFComicViewer/Directory/DirectoryTreeNode.swift`の`sorted(by:direction:)`メソッドの直後、`private func sortedByKey`の前に追加する。

```swift
    /// クエリで絞り込んだコピーを返す。空文字（前後の空白を除去した上で）なら全件そのまま。
    /// フォルダ名・ファイル名が部分一致（大小文字を無視）したノードを残す。
    /// フォルダ自体がマッチしたら中身は絞らず全部残し、マッチしなければ子を
    /// 再帰的に絞り込んで、何か残るフォルダだけを残す
    /// （マッチしたファイルまでの経路を保つため）。
    func filtered(byQuery query: String) -> [DirectoryTreeNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return compactMap { node -> DirectoryTreeNode? in
            if node.name.localizedCaseInsensitiveContains(trimmed) {
                return node
            }
            guard node.kind == .folder, let children = node.children else { return nil }
            let filteredChildren = children.filtered(byQuery: trimmed)
            guard !filteredChildren.isEmpty else { return nil }
            var copy = node
            copy.children = filteredChildren
            return copy
        }
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `swift test --filter DirectoryTreeNodeTests`
Expected: PASS（既存分と合わせて全件）

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/Directory/DirectoryTreeNode.swift Tests/PDFComicViewerTests/DirectoryTreeNodeTests.swift
git commit -m "$(cat <<'EOF'
feat: add DirectoryTreeNode.filtered(byQuery:)

Keeps a node whose own name matches (folders keep all their children
untouched), and recursively prunes folders down to whatever matching
descendants remain, so the path to a match stays visible instead of
being flattened away.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: サイドバーの検索状態

**Files:**
- Modify: `Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift`
- Test: `Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift`

**Interfaces:**
- Consumes: `[DirectoryTreeNode].filtered(byQuery:)`（Task 4）
- Produces:
  - `DirectorySidebarViewModel.searchQuery: String`（`@Published`、既定値`""`）
  - `DirectorySidebarViewModel.displayedNodes: [DirectoryTreeNode]`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift`の`testSortedNodesReflectsSortKeyAndDirection`の直後に追加する。

```swift
    func testSearchQueryDefaultsToEmpty() {
        let model = makeModel(scanner: FakeDirectoryScanner(result: .success([])))

        XCTAssertEqual(model.searchQuery, "")
    }

    func testDisplayedNodesAppliesSearchAndSort() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/comics")
        let onePiece = DirectoryTreeNode(url: rootURL.appending(path: "OnePiece.pdf"), kind: .pdf)
        let naruto = DirectoryTreeNode(url: rootURL.appending(path: "Naruto.pdf"), kind: .pdf)
        let scanner = FakeDirectoryScanner(result: .success([naruto, onePiece]))
        let model = makeModel(scanner: scanner)
        model.setRoot(rootURL)
        try await waitUntil { model.isLoading == false }

        XCTAssertEqual(model.displayedNodes.map(\.name), ["Naruto.pdf", "OnePiece.pdf"])

        model.searchQuery = "one"

        XCTAssertEqual(model.displayedNodes.map(\.name), ["OnePiece.pdf"])
    }

    func testSetRootResetsSearchQuery() async throws {
        let scanner = FakeDirectoryScanner(result: .success([]))
        let model = makeModel(scanner: scanner)
        model.setRoot(URL(fileURLWithPath: "/tmp/comics"))
        try await waitUntil { model.isLoading == false }
        model.searchQuery = "something"

        model.setRoot(URL(fileURLWithPath: "/tmp/other"))

        XCTAssertEqual(model.searchQuery, "")

        // 同じフォルダを指定した場合はearly-returnガードに当たるため、
        // 検索中の入力を消してはいけない。
        try await waitUntil { model.isLoading == false }
        model.searchQuery = "still searching"

        model.setRoot(URL(fileURLWithPath: "/tmp/other"))

        XCTAssertEqual(model.searchQuery, "still searching")
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter DirectorySidebarViewModelTests`
Expected: FAIL（`value of type 'DirectorySidebarViewModel' has no member 'searchQuery'` でビルドエラー）

- [ ] **Step 3: 最小限の実装を書く**

`Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift`の`@Published var selectedNodeIDs: Set<String> = []`の直後に追加する。

```swift
    /// 検索欄の入力。空ならフィルタなし。フォルダを切り替えたら空に戻す。
    @Published var searchQuery: String = ""
```

`sortedNodes`の直後に追加する。

```swift
    /// `searchQuery`による絞り込みと`sortKey`/`sortDirection`による並べ替えを
    /// 両方適用した、実際にサイドバーへ渡す表示用のツリー。
    var displayedNodes: [DirectoryTreeNode] {
        nodes.filtered(byQuery: searchQuery).sorted(by: sortKey, direction: sortDirection)
    }
```

`setRoot(_:)`を差し替える。

```swift
    func setRoot(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard rootURL != normalized else { return }
        rootURL = normalized
        searchQuery = ""
        reload()
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `swift test --filter DirectorySidebarViewModelTests`
Expected: PASS（既存分と合わせて全件）

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: add search state and displayedNodes to the sidebar view model

displayedNodes composes the new query filter with the existing
sort — the view switches to this single source in the next task.
setRoot clears the query so a stale search from the previous folder
does not make the new one look empty.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: サイドバーの検索欄

**Files:**
- Modify: `Sources/PDFComicViewer/UI/DirectorySidebarView.swift`

**Interfaces:**
- Consumes: `DirectorySidebarViewModel.searchQuery`・`.displayedNodes`（Task 5）
- Produces: なし（Viewのみ）

- [ ] **Step 1: 検索欄を追加する**

`Sources/PDFComicViewer/UI/DirectorySidebarView.swift`の`body`を差し替える。

```swift
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.rootURL != nil {
                searchField
                Divider()
            }
            content
        }
        .frame(maxHeight: .infinity)
        .background(ReaderTheme.surface)
    }
```

`header`の直後に追加する。

```swift
    /// フォルダ選択後は常時表示する絞り込み検索欄。
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ReaderTheme.secondaryText)
                .accessibilityHidden(true)
            TextField("検索...", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(ReaderTheme.primaryText)
            if !model.searchQuery.isEmpty {
                Button {
                    model.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ReaderTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索語をクリア")
                .help("検索語をクリア")
                .nativeToolTip("検索語をクリア")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
```

- [ ] **Step 2: 一覧の表示元を`displayedNodes`に切り替える**

`content`内の該当箇所（現状は次のとおり）を

```swift
        } else if model.nodes.isEmpty {
            Text("PDFが見つかりません")
                .font(.callout)
                .foregroundStyle(ReaderTheme.secondaryText)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List(model.sortedNodes, children: \.children, selection: $model.selectedNodeIDs) { node in
                row(for: node)
            }
```

次のとおり差し替える（条件を`model.displayedNodes.isEmpty`に、Listのデータ源を`model.displayedNodes`に変える。それ以外は同じ）。

```swift
        } else if model.displayedNodes.isEmpty {
            Text("PDFが見つかりません")
                .font(.callout)
                .foregroundStyle(ReaderTheme.secondaryText)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List(model.displayedNodes, children: \.children, selection: $model.selectedNodeIDs) { node in
                row(for: node)
            }
```

（検索語が空のときは`nodes.filtered(byQuery: "")`が`nodes`をそのまま返すため、`model.displayedNodes.isEmpty`は元の`model.nodes.isEmpty`と同じ意味になる。検索で0件になったときも同じ「PDFが見つかりません」を流用する、という設計上の決定どおり。）

- [ ] **Step 3: ビルドとテストを確認する**

Run: `swift build && swift test`
Expected: ビルド成功、テスト全件PASS（このタスクはViewのみでテスト追加なし）

- [ ] **Step 4: 手元で動作確認する**

Run: `scripts/install-app.sh`

確認項目:
- フォルダを選択すると、ヘッダーの下に検索欄が現れる
- ファイル名の一部を入力すると、一致するPDFだけが残る
- フォルダ名の一部を入力すると、そのフォルダと中身が全部残る
- ネストしたフォルダの奥のPDFにマッチすると、そこまでの経路が自動的に展開されて表示される
- 一致が0件のとき「PDFが見つかりません」と出る
- クリアボタン（×）で検索語を消せる
- 別のフォルダを選び直すと検索語が消える

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/UI/DirectorySidebarView.swift
git commit -m "$(cat <<'EOF'
feat: add a search field to the directory sidebar

Sits below the header, always visible once a folder is chosen. The
list now reads from displayedNodes instead of sortedNodes, so a zero-
match search reuses the existing "no PDFs" message rather than adding
a second one.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: READMEの更新

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: 主な特徴に1行足す**

`README.md`の「## 主な特徴」の最後の項目（`- シークバーによるページ移動、読書位置のリセット、PDFのゴミ箱移動`）の直後に追加する。

```markdown
- シリーズ最後のページで自動的に次の巻を開く、サイドバーの絞り込み検索
```

- [ ] **Step 2: 基本操作に説明を足す**

「## 基本操作」の`- 次へ進む: ...`の行を差し替える。

```markdown
- 次へ進む: `Space`。矢印キーと画面左右のクリック領域は綴じ方向に応じて反転。最後のページで次へ進むと、同じフォルダに次のPDFがあれば自動的に開きます
```

箇条書きの最後（`- PDFを削除する: ...`の行）の直後に追加する。

```markdown
- PDFを絞り込む: サイドバーの検索欄にファイル名やフォルダ名の一部を入力
```

- [ ] **Step 3: サイドバーの段落の後に新しい段落を足す**

「サイドバーでは1クリックがPDFの選択、…」で始まる段落の直後に追加する。

```markdown
サイドバーの検索欄にキーワードを入力すると、ファイル名またはフォルダ名が部分一致するPDFだけに絞り込まれます（大文字・小文字は区別しません）。マッチしたファイルまでのフォルダは自動的に展開されたまま表示され、一致がなければ「PDFが見つかりません」と表示されます。フォルダを切り替えると検索語は消えます。
```

- [ ] **Step 4: 表示を確認する**

Run: `grep -n "次の巻\|絞り込み検索\|検索欄" README.md`
Expected: 追加した4箇所が出力される

- [ ] **Step 5: コミット**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs: document series auto-advance and the sidebar search field

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## 完了時の確認

すべてのタスクを終えたら、次を実行して全体を確認する。

```bash
swift build
swift test
zsh Tests/InstallAppScriptTests/install-app-bundle-tests.sh
scripts/install-app.sh
```

`swift test` は着手前の163件から、Task 1で5件、Task 2で6件、Task 3で3件、Task 4で6件、Task 5で3件の計23件増え、合計186件になる見込み。

手元での最終確認:
- シリーズ物のPDF（同じフォルダに複数PDF）を開き、最後のページで「次へ」を押すと次の巻が開く
- シリーズ最後の巻の最後のページで「次へ」を押しても何も起きない
- サイドバーの検索欄で絞り込みが機能する（Task 6のStep 4と同じ項目）
