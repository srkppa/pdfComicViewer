# PDF漫画ビューアー 実装計画

> **エージェント実装者向け:** 必須サブスキルとして `superpowers:subagent-driven-development`（推奨）または `superpowers:executing-plans` を使い、各タスクを順番に実行すること。進捗はチェックボックス（`- [ ]`）で管理する。

**目標:** ローカルの漫画PDFを、右綴じの見開き、横長ページの自動単独表示、手動レイアウト修正、読書位置保存に対応して読めるmacOSアプリを作る。

**アーキテクチャ:** SwiftUIをアプリケーションと操作画面に使い、PDFKitをPDFの読み込みとベクター描画に使う。ページの組み立て、左右配置、状態保存をUIから分離した純粋な型として実装し、`ReaderViewModel`がそれらを調整する。Swift Packageでビルドとテストを行い、最後に個人利用用の`.app`バンドルを生成する。

**技術スタック:** Swift 6、SwiftUI、AppKit、PDFKit、XCTest、Swift Package Manager、macOS 15以上

## 全体制約

- 対応OSはmacOSのみとし、外部パッケージへ依存しない。
- 既定の綴じ方向は右綴じ、既定の表示モードは見開き、既定の見開き位置は表紙単独とする。
- PDFをアップロード、複製、変更せず、ネットワーク通信を行わない。
- パスワードを保存しない。
- 一時的な倍率とパン位置は保存せず、ページ変更時はウインドウに合わせる表示へ戻す。
- UIに表示する文言とエラーメッセージは日本語にする。
- Mac App Store配布、自動更新、配布用署名、公証、ページめくりアニメーションは実装しない。
- 各タスクで追加したコードは、対象テストと`swift test`全体が成功してからコミットする。

---

## ファイル構成

```text
Package.swift
Sources/PDFComicViewer/
  App/PDFComicViewerApp.swift          # アプリ起動、メニュー、ウインドウ設定
  Domain/ReaderTypes.swift             # 表示・綴じ・ページ設定の値型
  Domain/SpreadBuilder.swift           # 物理ページから表示単位を組み立てる
  Domain/SpreadPresentation.swift      # 読む順番を画面の左右へ配置する
  Document/DocumentSession.swift       # PDFDocumentとページ情報を保持する
  Document/PDFDocumentLoader.swift     # ファイル検証、読み込み、解除
  Persistence/ReadingProgressStore.swift # PDFごとの設定をJSON保存する
  Reader/ReaderViewModel.swift         # 閲覧状態とユーザー操作を調整する
  Rendering/SpreadLayoutCalculator.swift # ページ描画矩形を計算する
  Rendering/SpreadCanvasView.swift     # PDFPageをベクター描画するNSView
  Rendering/PDFSpreadView.swift        # NSScrollViewをSwiftUIへ接続する
  Rendering/PagePreviewCache.swift     # 現在位置前後だけを先読みするLRU
  UI/ReaderView.swift                  # 初期、閲覧、エラー、ドロップ画面
  UI/ReaderToolbar.swift               # 閲覧操作とページ番号
  UI/PasswordSheet.swift               # PDFパスワード入力
  UI/ReaderInputMonitor.swift          # キー、クリック、全画面操作
Tests/PDFComicViewerTests/
  SpreadBuilderTests.swift
  SpreadPresentationTests.swift
  ReadingProgressStoreTests.swift
  PDFDocumentLoaderTests.swift
  ReaderViewModelTests.swift
  SpreadLayoutCalculatorTests.swift
  PagePreviewCacheTests.swift
  Support/PDFFixtureFactory.swift
Resources/Info.plist                   # .appバンドル情報とPDF文書型
scripts/build-app.sh                   # releaseビルドを.appへ組み立てる
```

---

### Task 1: Swift Packageとアプリの骨格

**ファイル:**
- 作成: `Package.swift`
- 作成: `Sources/PDFComicViewer/App/PDFComicViewerApp.swift`
- 作成: `Sources/PDFComicViewer/Domain/ReaderTypes.swift`
- 作成: `Tests/PDFComicViewerTests/AppConfigurationTests.swift`

**インターフェース:**
- 提供: `AppConfiguration.applicationName: String`
- 提供: `PDFComicViewerApp: App`

- [ ] **ステップ1: パッケージ設定の失敗テストを書く**

```swift
import XCTest
@testable import PDFComicViewer

final class AppConfigurationTests: XCTestCase {
    func testApplicationNameIsJapaneseReaderName() {
        XCTAssertEqual(AppConfiguration.applicationName, "PDF漫画ビューアー")
    }
}
```

- [ ] **ステップ2: 未実装による失敗を確認する**

実行: `swift test --filter AppConfigurationTests`

期待結果: `no such module 'PDFComicViewer'`または`AppConfiguration`未定義で失敗する。

- [ ] **ステップ3: パッケージと最小アプリを作る**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PDFComicViewer",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "PDFComicViewer", targets: ["PDFComicViewer"])],
    targets: [
        .executableTarget(name: "PDFComicViewer"),
        .testTarget(name: "PDFComicViewerTests", dependencies: ["PDFComicViewer"])
    ]
)
```

```swift
// ReaderTypes.swift
enum AppConfiguration {
    static let applicationName = "PDF漫画ビューアー"
}
```

```swift
// PDFComicViewerApp.swift
import SwiftUI

@main
struct PDFComicViewerApp: App {
    var body: some Scene {
        WindowGroup(AppConfiguration.applicationName) {
            Text("PDFを開いてください")
                .frame(minWidth: 900, minHeight: 650)
        }
    }
}
```

- [ ] **ステップ4: テストとビルドを確認する**

実行: `swift test && swift build`

期待結果: テスト1件が成功し、`Build complete!`で終了する。

- [ ] **ステップ5: コミットする**

```bash
git add Package.swift Sources Tests
git commit -m "chore: scaffold macOS comic viewer"
```

---

### Task 2: ページの組み立て規則

**ファイル:**
- 変更: `Sources/PDFComicViewer/Domain/ReaderTypes.swift`
- 作成: `Sources/PDFComicViewer/Domain/SpreadBuilder.swift`
- 作成: `Tests/PDFComicViewerTests/SpreadBuilderTests.swift`

**インターフェース:**
- 提供: `DisplayMode`, `PairingAlignment`, `PageLayoutOverride`, `PageGeometry`, `DisplayUnit`
- 提供: `SpreadBuilder.build(pages:mode:alignment:overrides:) -> [DisplayUnit]`

- [ ] **ステップ1: 表紙、横長、手動修正を含む失敗テストを書く**

```swift
import XCTest
@testable import PDFComicViewer

final class SpreadBuilderTests: XCTestCase {
    private let portrait = PageGeometry(width: 600, height: 900)
    private let landscape = PageGeometry(width: 1200, height: 800)

    func testCoverAlignmentKeepsFirstPageSingle() {
        let result = SpreadBuilder.build(
            pages: Array(repeating: portrait, count: 5),
            mode: .spread, alignment: .coverSingle, overrides: [:]
        )
        XCTAssertEqual(result, [.single(0), .pair(1, 2), .pair(3, 4)])
    }

    func testLandscapeBreaksAndRestartsPairing() {
        let result = SpreadBuilder.build(
            pages: [portrait, portrait, portrait, landscape, portrait, portrait],
            mode: .spread, alignment: .coverSingle, overrides: [:]
        )
        XCTAssertEqual(result, [.single(0), .pair(1, 2), .single(3), .pair(4, 5)])
    }

    func testManualPairOverrideBeatsLandscapeDetection() {
        let result = SpreadBuilder.build(
            pages: [landscape, portrait], mode: .spread,
            alignment: .shifted, overrides: [0: .pairable]
        )
        XCTAssertEqual(result, [.pair(0, 1)])
    }

    func testSingleModeReturnsEveryPhysicalPage() {
        let result = SpreadBuilder.build(
            pages: [portrait, landscape], mode: .single,
            alignment: .coverSingle, overrides: [:]
        )
        XCTAssertEqual(result, [.single(0), .single(1)])
    }
}
```

- [ ] **ステップ2: テストの失敗を確認する**

実行: `swift test --filter SpreadBuilderTests`

期待結果: ドメイン型と`SpreadBuilder`が未定義で失敗する。

- [ ] **ステップ3: 値型と最小アルゴリズムを実装する**

```swift
enum DisplayMode: String, Codable, Sendable { case single, spread }
enum PairingAlignment: String, Codable, Sendable { case coverSingle, shifted }
enum PageLayoutOverride: String, Codable, Sendable { case automatic, single, pairable }
struct PageGeometry: Equatable, Sendable { let width: Double; let height: Double }
enum DisplayUnit: Equatable, Sendable { case single(Int); case pair(Int, Int) }

extension DisplayUnit {
    var pageIndexes: [Int] {
        switch self {
        case .single(let page): [page]
        case .pair(let first, let second): [first, second]
        }
    }
    var anchorPage: Int { pageIndexes[0] }
}
```

```swift
enum SpreadBuilder {
    static func build(
        pages: [PageGeometry], mode: DisplayMode,
        alignment: PairingAlignment, overrides: [Int: PageLayoutOverride]
    ) -> [DisplayUnit] {
        guard mode == .spread else { return pages.indices.map(DisplayUnit.single) }
        var result: [DisplayUnit] = []
        var pending: Int?

        for index in pages.indices {
            let override = overrides[index] ?? .automatic
            let automaticSingle = (index == 0 && alignment == .coverSingle)
                || pages[index].width > pages[index].height
            let mustBeSingle = override == .single
                || (override == .automatic && automaticSingle)

            if mustBeSingle {
                if let pending { result.append(.single(pending)) }
                pending = nil
                result.append(.single(index))
            } else if let first = pending {
                result.append(.pair(first, index))
                pending = nil
            } else {
                pending = index
            }
        }
        if let pending { result.append(.single(pending)) }
        return result
    }
}
```

- [ ] **ステップ4: 端数、連続横長、空配列のテストを追加して成功を確認する**

追加ケース: 0、1、2、偶数、奇数ページ、先頭・中間・末尾の横長、横長の連続、`.single`による手動区切り。

実行: `swift test --filter SpreadBuilderTests && swift test`

期待結果: 追加ケースを含む全テストが成功する。

- [ ] **ステップ5: コミットする**

```bash
git add Sources/PDFComicViewer/Domain Tests/PDFComicViewerTests/SpreadBuilderTests.swift
git commit -m "feat: add comic spread grouping"
```

---

### Task 3: 左右配置と現在ページの維持

**ファイル:**
- 変更: `Sources/PDFComicViewer/Domain/ReaderTypes.swift`
- 作成: `Sources/PDFComicViewer/Domain/SpreadPresentation.swift`
- 作成: `Tests/PDFComicViewerTests/SpreadPresentationTests.swift`

**インターフェース:**
- 提供: `BindingDirection`, `PagePlacement`
- 提供: `SpreadPresentation.placement(for:binding:) -> PagePlacement`
- 提供: `SpreadPresentation.unitIndex(containing:in:) -> Int?`

- [ ] **ステップ1: 右綴じ、左綴じ、アンカーの失敗テストを書く**

```swift
func testRightBindingPlacesEarlierPageOnRight() {
    XCTAssertEqual(
        SpreadPresentation.placement(for: .pair(1, 2), binding: .right),
        PagePlacement(left: 2, right: 1, centered: nil)
    )
}

func testLeftBindingPlacesEarlierPageOnLeft() {
    XCTAssertEqual(
        SpreadPresentation.placement(for: .pair(1, 2), binding: .left),
        PagePlacement(left: 1, right: 2, centered: nil)
    )
}

func testFindsRebuiltUnitContainingCurrentPhysicalPage() {
    let units: [DisplayUnit] = [.single(0), .pair(1, 2), .single(3)]
    XCTAssertEqual(SpreadPresentation.unitIndex(containing: 2, in: units), 1)
}
```

- [ ] **ステップ2: 未定義による失敗を確認する**

実行: `swift test --filter SpreadPresentationTests`

期待結果: `SpreadPresentation`未定義で失敗する。

- [ ] **ステップ3: 左右配置とアンカー検索を実装する**

```swift
enum BindingDirection: String, Codable, Sendable { case right, left }
struct PagePlacement: Equatable, Sendable {
    let left: Int?
    let right: Int?
    let centered: Int?
}

enum SpreadPresentation {
    static func placement(for unit: DisplayUnit, binding: BindingDirection) -> PagePlacement {
        switch unit {
        case .single(let page): return .init(left: nil, right: nil, centered: page)
        case .pair(let earlier, let later):
            return binding == .right
                ? .init(left: later, right: earlier, centered: nil)
                : .init(left: earlier, right: later, centered: nil)
        }
    }

    static func unitIndex(containing page: Int, in units: [DisplayUnit]) -> Int? {
        units.firstIndex { unit in
            switch unit {
            case .single(let value): value == page
            case .pair(let first, let second): first == page || second == page
            }
        }
    }
}
```

- [ ] **ステップ4: テスト全体を実行する**

実行: `swift test`

期待結果: 全テストが成功する。

- [ ] **ステップ5: コミットする**

```bash
git add Sources/PDFComicViewer/Domain Tests/PDFComicViewerTests/SpreadPresentationTests.swift
git commit -m "feat: map spreads to binding direction"
```

---

### Task 4: PDFごとの設定保存

**ファイル:**
- 変更: `Sources/PDFComicViewer/Domain/ReaderTypes.swift`
- 作成: `Sources/PDFComicViewer/Persistence/ReadingProgressStore.swift`
- 作成: `Tests/PDFComicViewerTests/ReadingProgressStoreTests.swift`

**インターフェース:**
- 提供: `DocumentPreferences`, `DocumentRecord`, `FileMetadata`
- 提供: `ReadingProgressStoring.load(for:)`, `save(_:)`, `allRecords()`
- 提供: `FileReadingProgressStore(fileURL:)`
- 提供: `DocumentBookmarkService.makeBookmark(for:)`, `resolve(_:)`

- [ ] **ステップ1: 保存と破損データ復旧の失敗テストを書く**

```swift
func testRoundTripsDocumentPreferences() async throws {
    let file = temporaryDirectory.appending(path: "progress.json")
    let store = FileReadingProgressStore(fileURL: file)
    let record = DocumentRecord(
        bookmarkData: Data([1, 2]), normalizedPath: "/tmp/comic.pdf",
        metadata: .init(size: 42, modificationDate: Date(timeIntervalSince1970: 10)),
        preferences: .init(lastPageIndex: 8, binding: .right, displayMode: .spread,
            alignment: .coverSingle, pageOverrides: [3: .single])
    )
    try await store.save(record)
    XCTAssertEqual(try await store.load(for: URL(fileURLWithPath: "/tmp/comic.pdf")), record)
}

func testCorruptFileIsReportedWithoutDeletingIt() async throws {
    try Data("not-json".utf8).write(to: progressFile)
    let store = FileReadingProgressStore(fileURL: progressFile)
    await XCTAssertThrowsErrorAsync { try await store.allRecords() }
    XCTAssertTrue(FileManager.default.fileExists(atPath: progressFile.path))
}
```

- [ ] **ステップ2: 未実装による失敗を確認する**

実行: `swift test --filter ReadingProgressStoreTests`

期待結果: 保存型とストアが未定義で失敗する。

- [ ] **ステップ3: Codable値型とactorストアを実装する**

```swift
struct DocumentPreferences: Codable, Equatable, Sendable {
    var lastPageIndex: Int
    var binding: BindingDirection
    var displayMode: DisplayMode
    var alignment: PairingAlignment
    var pageOverrides: [Int: PageLayoutOverride]

    static let defaults = Self(
        lastPageIndex: 0, binding: .right, displayMode: .spread,
        alignment: .coverSingle, pageOverrides: [:]
    )
}

struct FileMetadata: Codable, Equatable, Sendable {
    let size: Int64
    let modificationDate: Date
}

struct DocumentRecord: Codable, Equatable, Sendable {
    var bookmarkData: Data
    var normalizedPath: String
    var metadata: FileMetadata
    var preferences: DocumentPreferences
}

protocol ReadingProgressStoring: Sendable {
    func load(for url: URL) async throws -> DocumentRecord?
    func save(_ record: DocumentRecord) async throws
    func allRecords() async throws -> [DocumentRecord]
}

enum DocumentBookmarkService {
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: data, options: [],
                       relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}
```

```swift
actor FileReadingProgressStore: ReadingProgressStoring {
    private let fileURL: URL
    private var records: [DocumentRecord]?

    init(fileURL: URL) { self.fileURL = fileURL }

    func load(for url: URL) throws -> DocumentRecord? {
        let target = url.standardizedFileURL
        return try loadRecords().first { record in
            if let resolved = try? DocumentBookmarkService.resolve(record.bookmarkData),
               resolved.standardizedFileURL == target { return true }
            return record.normalizedPath == target.path
        }
    }

    func save(_ record: DocumentRecord) throws {
        var values = try loadRecords()
        values.removeAll { $0.normalizedPath == record.normalizedPath }
        values.append(record)
        let data = try JSONEncoder().encode(values)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        records = values
    }

    func allRecords() throws -> [DocumentRecord] { try loadRecords() }

    private func loadRecords() throws -> [DocumentRecord] {
        if let records { return records }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return []
        }
        let decoded = try JSONDecoder().decode([DocumentRecord].self,
                                               from: Data(contentsOf: fileURL))
        records = decoded
        return decoded
    }
}
```

`loadRecords()`はメモリ上の値があればそれを返し、ファイルがなければ空配列、ファイルがあれば`JSONDecoder().decode([DocumentRecord].self, from:)`の結果を返す。存在する破損JSONは`DecodingError`として返す。テスト専用ヘルパーは次の形でテストファイル内へ定義する。

```swift
func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do { try await expression(); XCTFail("エラーを期待", file: file, line: line) }
    catch { }
}
```

移動済みファイルのテストでは、一時ディレクトリ内でブックマークを作成してファイル名を変更し、`load(for:)`が同じレコードを返すことを確認する。

- [ ] **ステップ4: 保存テストと全テストを実行する**

実行: `swift test --filter ReadingProgressStoreTests && swift test`

期待結果: 原子的保存、復元、上書き、破損データのテストが成功する。

- [ ] **ステップ5: コミットする**

```bash
git add Sources/PDFComicViewer/Persistence Sources/PDFComicViewer/Domain Tests/PDFComicViewerTests/ReadingProgressStoreTests.swift
git commit -m "feat: persist per-document reading state"
```

---

### Task 5: PDFの読み込み、ページ情報、パスワード解除

**ファイル:**
- 作成: `Sources/PDFComicViewer/Document/DocumentSession.swift`
- 作成: `Sources/PDFComicViewer/Document/PDFDocumentLoader.swift`
- 作成: `Tests/PDFComicViewerTests/Support/PDFFixtureFactory.swift`
- 作成: `Tests/PDFComicViewerTests/PDFDocumentLoaderTests.swift`

**インターフェース:**
- 提供: `DocumentSession(document:url:pages:metadata:)`
- 提供: `PDFOpenResult.ready`, `PDFOpenResult.passwordRequired`
- 提供: `PDFDocumentLoading.open(url:) async throws`, `unlock(_:password:)`

- [ ] **ステップ1: 通常、空、暗号化PDFの失敗テストを書く**

```swift
@MainActor
func testOpensPDFAndReadsCropBoxGeometry() async throws {
    let url = try PDFFixtureFactory.makePDF(pageSizes: [CGSize(width: 600, height: 900)])
    let result = try await PDFDocumentLoader().open(url: url)
    guard case .ready(let session) = result else { return XCTFail("readyを期待") }
    XCTAssertEqual(session.pages, [.init(width: 600, height: 900)])
}

@MainActor
func testLockedPDFRequestsPasswordAndUnlocks() async throws {
    let url = try PDFFixtureFactory.makeEncryptedPDF(password: "secret")
    let result = try await PDFDocumentLoader().open(url: url)
    guard case .passwordRequired(let locked) = result else { return XCTFail("passwordRequiredを期待") }
    let session = try PDFDocumentLoader().unlock(locked, password: "secret")
    XCTAssertEqual(session.document.pageCount, 1)
}
```

- [ ] **ステップ2: 失敗を確認する**

実行: `swift test --filter PDFDocumentLoaderTests`

期待結果: ローダーとテストPDF生成処理が未定義で失敗する。

- [ ] **ステップ3: テスト用PDF生成処理を作る**

`CGDataConsumer`と`CGContext`を使い、指定された`mediaBox`ごとに空白ページを生成する。暗号化テストでは補助情報へ`kCGPDFContextUserPassword`と`kCGPDFContextOwnerPassword`を設定する。空バイトのファイルと不正なバイト列も生成できるAPIにする。

```swift
enum PDFFixtureFactory {
    static func makePDF(pageSizes: [CGSize], password: String? = nil) throws -> URL
    static func makeEncryptedPDF(password: String) throws -> URL
    static func makeCorruptFile() throws -> URL
}
```

- [ ] **ステップ4: ローダーとセッションを実装する**

```swift
@MainActor
final class DocumentSession {
    let document: PDFDocument
    let url: URL
    let pages: [PageGeometry]
    let metadata: FileMetadata

    init(document: PDFDocument, url: URL, pages: [PageGeometry], metadata: FileMetadata) {
        self.document = document
        self.url = url
        self.pages = pages
        self.metadata = metadata
    }
}
```

```swift
@MainActor
protocol PDFDocumentLoading {
    func open(url: URL) async throws -> PDFOpenResult
    func unlock(_ locked: LockedPDFDocument, password: String) throws -> DocumentSession
}

enum PDFLoaderError: LocalizedError {
    case unreadableFile, invalidPDF, incorrectPassword
}

@MainActor
struct LockedPDFDocument {
    let document: PDFDocument
    let url: URL
    let metadata: FileMetadata
}

@MainActor
enum PDFOpenResult {
    case ready(DocumentSession)
    case passwordRequired(LockedPDFDocument)
}
```

`open(url:)`では`Task.detached`内で`Data(contentsOf:options: .mappedIfSafe)`を実行し、メインアクターへ戻って`PDFDocument(data:)`を生成する。`PDFDocument(data:)`が失敗した場合と`pageCount == 0`の場合は`.invalidPDF`へ統合し、`isLocked`なら`.passwordRequired`を返す。ページ寸法は`.cropBox`から取得し、32ページごとに`Task.yield()`してUIへ実行機会を返す。

- [ ] **ステップ5: ローダーテストと全テストを実行する**

実行: `swift test --filter PDFDocumentLoaderTests && swift test`

期待結果: 通常、縦横混在、空バイトと不正データの`.invalidPDF`、正しいパスワード、誤ったパスワードのテストが成功する。

- [ ] **ステップ6: コミットする**

```bash
git add Sources/PDFComicViewer/Document Tests/PDFComicViewerTests/PDFDocumentLoaderTests.swift Tests/PDFComicViewerTests/Support
git commit -m "feat: load and unlock local PDF documents"
```

---

### Task 6: 閲覧状態と操作の調整

**ファイル:**
- 作成: `Sources/PDFComicViewer/Reader/ReaderViewModel.swift`
- 作成: `Tests/PDFComicViewerTests/ReaderViewModelTests.swift`

**インターフェース:**
- 提供: `@MainActor final class ReaderViewModel: ObservableObject`
- 提供: `open`, `unlock`, `next`, `previous`, `setDisplayMode`, `toggleAlignment`, `setBinding`, `setPageOverride`
- 使用: `PDFDocumentLoading`, `ReadingProgressStoring`, `SpreadBuilder`, `SpreadPresentation`

- [ ] **ステップ1: 開く、移動、再構築の失敗テストを書く**

```swift
@MainActor
func testOpenBuildsSpreadsAndRestoresSavedPage() async {
    let loader = FakePDFLoader(session: .fixture(pageCount: 6))
    let store = FakeProgressStore(preferences: .fixture(lastPageIndex: 4))
    let model = ReaderViewModel(loader: loader, progressStore: store)
    await model.open(url: URL(fileURLWithPath: "/tmp/comic.pdf"))
    XCTAssertEqual(model.currentPhysicalPage, 4)
    XCTAssertEqual(model.currentUnit, .pair(3, 4))
}

@MainActor
func testChangingModeKeepsCurrentPhysicalPage() async {
    let model = ReaderViewModel.fixture(currentPage: 2)
    model.setDisplayMode(.single)
    XCTAssertEqual(model.currentUnit, .single(2))
}

@MainActor
func testFailedOpenKeepsCurrentDocument() async {
    let model = ReaderViewModel.fixtureWithReadableDocument()
    await model.open(url: URL(fileURLWithPath: "/tmp/broken.pdf"))
    XCTAssertNotNil(model.session)
    XCTAssertNotNil(model.errorMessage)
}
```

- [ ] **ステップ2: 未定義による失敗を確認する**

実行: `swift test --filter ReaderViewModelTests`

期待結果: `ReaderViewModel`未定義で失敗する。

- [ ] **ステップ3: 公開状態と操作を実装する**

```swift
@MainActor
struct ReplacementConfirmation {
    let record: DocumentRecord
    let session: DocumentSession
}

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var session: DocumentSession?
    @Published private(set) var displayUnits: [DisplayUnit] = []
    @Published private(set) var currentUnitIndex = 0
    @Published private(set) var currentPhysicalPage = 0
    @Published private(set) var isLoading = false
    @Published var passwordRequest: LockedPDFDocument?
    @Published var replacementConfirmation: ReplacementConfirmation?
    @Published var errorMessage: String?
    @Published var warningMessage: String?
    @Published var preferences = DocumentPreferences.defaults

    var currentUnit: DisplayUnit? {
        guard displayUnits.indices.contains(currentUnitIndex) else { return nil }
        return displayUnits[currentUnitIndex]
    }

    func next() {
        guard !displayUnits.isEmpty else { return }
        currentUnitIndex = min(currentUnitIndex + 1, displayUnits.count - 1)
        currentPhysicalPage = currentUnit?.anchorPage ?? 0
        scheduleSave()
    }
    func previous() {
        currentUnitIndex = max(currentUnitIndex - 1, 0)
        currentPhysicalPage = currentUnit?.anchorPage ?? 0
        scheduleSave()
    }
}
```

設定変更は変更前の`currentPhysicalPage`を保持し、`SpreadBuilder`で再構築した後、`unitIndex(containing:in:)`で表示単位を選び直す。保存は既存の`Task`をキャンセルし、300ミリ秒後に最新の`DocumentRecord`だけを書き込む。保存失敗は`warningMessage`へ日本語で設定し、閲覧状態を変更しない。

保存済みレコードと新しく開いたファイルのサイズまたは更新日時が異なる場合は、`ReplacementConfirmation(record:session:)`を設定して読み込みを保留する。`confirmReplacement(keepPreferences:)`で、`true`なら保存済み設定を維持してブックマークとファイル情報を更新し、`false`なら既定設定で新規レコードを作る。どちらの場合も確認されるまで現在のPDFを破棄しない。

`FakePDFLoader`と`FakeProgressStore`は`ReaderViewModelTests.swift`内で各プロトコルへ準拠させ、受け取ったURL、保存されたレコード、返す結果、投げるエラーをプロパティとして保持する。`.fixture`は同じテストファイル内のextensionとして、600×900のページ情報と`DocumentPreferences.defaults`を生成する。

- [ ] **ステップ4: 境界、綴じ方向、設定保存、パスワードのテストを追加する**

先頭で`previous()`、末尾で`next()`、見開き位置切り替え、ページ単位設定、左綴じ、解除失敗、解除キャンセル、保存失敗、ファイル情報が異なる場合の設定維持と設定破棄をテストする。

実行: `swift test --filter ReaderViewModelTests && swift test`

期待結果: 全テストが成功する。

- [ ] **ステップ5: コミットする**

```bash
git add Sources/PDFComicViewer/Reader Tests/PDFComicViewerTests/ReaderViewModelTests.swift
git commit -m "feat: coordinate comic reader state"
```

---

### Task 7: 見開きレイアウトとベクター描画

**ファイル:**
- 作成: `Sources/PDFComicViewer/Rendering/SpreadLayoutCalculator.swift`
- 作成: `Sources/PDFComicViewer/Rendering/SpreadCanvasView.swift`
- 作成: `Sources/PDFComicViewer/Rendering/PDFSpreadView.swift`
- 作成: `Tests/PDFComicViewerTests/SpreadLayoutCalculatorTests.swift`

**インターフェース:**
- 提供: `SpreadLayoutCalculator.frames(pageSizes:viewport:gutter:) -> [CGRect]`
- 提供: `PDFSpreadView(document:placement:zoomCommand:)`

- [ ] **ステップ1: 単独・見開きの矩形計算テストを書く**

```swift
func testSinglePageIsCenteredAndFitsViewport() {
    let frames = SpreadLayoutCalculator.frames(
        pageSizes: [CGSize(width: 600, height: 900)],
        viewport: CGSize(width: 1200, height: 800), gutter: 12
    )
    XCTAssertEqual(frames[0].height, 800, accuracy: 0.01)
    XCTAssertEqual(frames[0].midX, 600, accuracy: 0.01)
}

func testPairFitsWidthAndKeepsGutter() {
    let frames = SpreadLayoutCalculator.frames(
        pageSizes: [.init(width: 600, height: 900), .init(width: 600, height: 900)],
        viewport: .init(width: 1012, height: 900), gutter: 12
    )
    XCTAssertEqual(frames[1].minX - frames[0].maxX, 12, accuracy: 0.01)
    XCTAssertLessThanOrEqual(frames[1].maxX, 1012)
}
```

- [ ] **ステップ2: 未実装による失敗を確認する**

実行: `swift test --filter SpreadLayoutCalculatorTests`

期待結果: `SpreadLayoutCalculator`未定義で失敗する。

- [ ] **ステップ3: 縦横比を保つ矩形計算を実装する**

```swift
enum SpreadLayoutCalculator {
    static func frames(pageSizes: [CGSize], viewport: CGSize, gutter: CGFloat) -> [CGRect] {
        guard !pageSizes.isEmpty else { return [] }
        let totalNaturalWidth = pageSizes.reduce(0) { $0 + $1.width }
        let maxHeight = pageSizes.map(\.height).max() ?? 1
        let totalGutter = gutter * CGFloat(max(0, pageSizes.count - 1))
        let scale = min((viewport.width - totalGutter) / totalNaturalWidth,
                        viewport.height / maxHeight)
        let scaledGutter = gutter
        let totalWidth = pageSizes.reduce(0) { $0 + $1.width * scale }
            + scaledGutter * CGFloat(max(0, pageSizes.count - 1))
        var x = (viewport.width - totalWidth) / 2
        return pageSizes.map { size in
            let scaled = CGSize(width: size.width * scale, height: size.height * scale)
            defer { x += scaled.width + scaledGutter }
            return CGRect(x: x, y: (viewport.height - scaled.height) / 2,
                          width: scaled.width, height: scaled.height)
        }
    }
}
```

- [ ] **ステップ4: AppKit描画ビューとSwiftUIブリッジを実装する**

`SpreadCanvasView`は`PDFDocument`と`PagePlacement`から最大2つの`PDFPage`を保持し、`draw(_:)`で各ページの`.cropBox`を対応する矩形へベクター描画する。`PDFSpreadView`は`NSScrollView`を生成し、`allowsMagnification = true`、`minMagnification = 1`、`maxMagnification = 6`とする。「合わせる」命令では倍率を1へ戻してキャンバスを再レイアウトする。

```swift
struct PDFSpreadView: NSViewRepresentable {
    let document: PDFDocument
    let placement: PagePlacement
    let zoomCommand: ZoomCommand

    func makeNSView(context: Context) -> NSScrollView
    func updateNSView(_ scrollView: NSScrollView, context: Context)
}
```

`ZoomCommand`は`ReaderTypes.swift`へ追加する。連続して同じ操作を送っても更新を検出できるよう、`action`と増加する`sequence`を持たせる。

```swift
struct ZoomCommand: Equatable, Sendable {
    enum Action: Sendable { case fit, zoomIn, zoomOut }
    let action: Action
    let sequence: Int
}
```

- [ ] **ステップ5: テストとビルドを実行する**

実行: `swift test --filter SpreadLayoutCalculatorTests && swift test && swift build`

期待結果: レイアウトテストと全テストが成功し、AppKit/PDFKitコードがコンパイルできる。

- [ ] **ステップ6: コミットする**

```bash
git add Sources/PDFComicViewer/Rendering Tests/PDFComicViewerTests/SpreadLayoutCalculatorTests.swift
git commit -m "feat: render single pages and comic spreads"
```

---

### Task 8: 閲覧画面、ファイル操作、入力操作

**ファイル:**
- 作成: `Sources/PDFComicViewer/UI/ReaderView.swift`
- 作成: `Sources/PDFComicViewer/UI/ReaderToolbar.swift`
- 作成: `Sources/PDFComicViewer/UI/PasswordSheet.swift`
- 作成: `Sources/PDFComicViewer/UI/ReaderInputMonitor.swift`
- 変更: `Sources/PDFComicViewer/App/PDFComicViewerApp.swift`

**インターフェース:**
- 使用: `ReaderViewModel`の公開状態と操作
- 提供: `ReaderView`, `ReaderToolbar`, `PasswordSheet`, `ReaderInputMonitor`

- [ ] **ステップ1: アプリ起動時に実ViewModelを注入する**

```swift
@main
struct PDFComicViewerApp: App {
    @StateObject private var model = ReaderViewModel.live()

    var body: some Scene {
        WindowGroup(AppConfiguration.applicationName) {
            ReaderView(model: model)
                .frame(minWidth: 900, minHeight: 650)
        }
        .commands { ReaderCommands(model: model) }
    }
}
```

`ReaderViewModel.live()`はApplication Support配下の`com.srkppa.PDFComicViewer/reading-progress.json`を使う`FileReadingProgressStore`と`PDFDocumentLoader`を組み立てるextensionとして`ReaderViewModel.swift`へ追加する。`ReaderCommands`は`PDFComicViewerApp.swift`内に定義し、ViewModelのファイル選択、ズーム命令、全画面命令を呼ぶ。

- [ ] **ステップ2: 初期画面、閲覧画面、ツールバーを実装する**

`ReaderView`は`session == nil`なら「PDFを開く」ボタン、`isLoading`なら`ProgressView`、読み込み済みなら`PDFSpreadView`を暗い背景上へ表示する。`.fileImporter(allowedContentTypes: [.pdf])`と`.dropDestination(for: URL.self)`の両方から`model.open(url:)`を呼ぶ。

`ReaderToolbar`には、開く、綴じ方向、`1ページ／見開き`、見開き位置、縮小、合わせる、拡大、全画面を配置し、現在ページを`12–13 / 180`形式で表示する。アイコンだけのボタンには日本語の`help`とaccessibility labelを設定する。

- [ ] **ステップ3: パスワードとエラー表示を実装する**

```swift
struct PasswordSheet: View {
    @State private var password = ""
    let errorMessage: String?
    let submit: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        Form {
            SecureField("パスワード", text: $password)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                Button("キャンセル", action: cancel)
                Button("開く") { submit(password) }.keyboardShortcut(.defaultAction)
            }
        }.padding()
    }
}
```

破損、空、見つからないファイルは日本語の`alert`で表示する。ファイル情報が保存時と異なる場合は「以前の読書位置と設定を引き継ぎますか？」と確認し、結果を`confirmReplacement(keepPreferences:)`へ渡す。新しいPDFの読み込み失敗時も既存の`PDFSpreadView`は残す。保存失敗は画面下部の非モーダル警告として表示する。

- [ ] **ステップ4: キー、クリック、全画面を実装する**

`ReaderInputMonitor`は対象ウインドウがキーウインドウの間だけローカルイベントモニターを登録し、左右矢印、Space、Shift-Space、`1`、`2`、`S`をViewModel操作へ変換する。右綴じでは左クリック領域を次、右クリック領域を前とし、左綴じでは反転する。ドラッグ量が3ポイントを超えた操作はページクリックとして扱わない。全画面は`NSWindow.toggleFullScreen(nil)`を呼ぶ。

全画面へ入ったらツールバーを独自オーバーレイへ切り替える。ポインター移動またはキー入力で`controlsVisible = true`にし、既存の非表示予約`Task`をキャンセルして2秒後に`false`へする。全画面を終了したら予約をキャンセルし、常に表示する。

- [ ] **ステップ5: メニューとコンテキスト操作を実装する**

Command-O、Command-Plus、Command-Minus、Command-0、Command-Control-Fを`Commands`へ登録する。コンテキストメニューを開いた座標から左、右、中央の物理ページを特定し、そのページへ`.automatic`、`.single`、`.pairable`を設定できるようにする。

- [ ] **ステップ6: 全テストとビルドを実行する**

実行: `swift test && swift build`

期待結果: 全テストが成功し、SwiftUI/AppKitを含むアプリがビルドできる。

- [ ] **ステップ7: コミットする**

```bash
git add Sources/PDFComicViewer/App Sources/PDFComicViewer/UI
git commit -m "feat: add macOS comic reader interface"
```

---

### Task 9: 前後ページの先読みとキャッシュ上限

**ファイル:**
- 作成: `Sources/PDFComicViewer/Rendering/PagePreviewCache.swift`
- 作成: `Tests/PDFComicViewerTests/PagePreviewCacheTests.swift`
- 変更: `Sources/PDFComicViewer/Reader/ReaderViewModel.swift`

**インターフェース:**
- 提供: `PagePreviewCache.insert(_:for:)`, `image(for:)`, `retainOnly(_:)`
- 使用: 現在、直前、直後の`DisplayUnit`が含むページインデックス

- [ ] **ステップ1: 上限と破棄順序の失敗テストを書く**

```swift
func testRetainsOnlyRequestedNeighborPages() async {
    let cache = PagePreviewCache()
    await cache.insert(makeImage(gray: 0), for: 0)
    await cache.insert(makeImage(gray: 1), for: 1)
    await cache.insert(makeImage(gray: 2), for: 2)
    await cache.retainOnly([1, 2])
    XCTAssertNil(await cache.image(for: 0))
    XCTAssertNotNil(await cache.image(for: 1))
    XCTAssertNotNil(await cache.image(for: 2))
}
```

テストの`makeImage(gray:)`は、`CGContext`へ1×1ピクセルのグレースケール画像を描き、`makeImage()`で返す関数として`PagePreviewCacheTests.swift`内へ定義する。

- [ ] **ステップ2: 未実装による失敗を確認する**

実行: `swift test --filter PagePreviewCacheTests`

期待結果: `PagePreviewCache`未定義で失敗する。

- [ ] **ステップ3: actorキャッシュを実装する**

```swift
actor PagePreviewCache {
    private var images: [Int: CGImage] = [:]
    func insert(_ image: CGImage, for pageIndex: Int) { images[pageIndex] = image }
    func image(for pageIndex: Int) -> CGImage? { images[pageIndex] }
    func retainOnly(_ indexes: Set<Int>) { images = images.filter { indexes.contains($0.key) } }
}
```

ViewModelは表示単位変更時に現在、直前、直後のページ集合を計算し、それ以外を即座に破棄する。先読み`Task`は次のページ移動時にキャンセルする。プレビューはページ遷移直後の仮表示だけに使い、拡大時は`PDFPage.draw`によるベクター描画へ置き換える。

`@MainActor PagePreviewRenderer.render(page:maxSize:) -> CGImage?`を同じファイルへ定義し、`PDFPage.thumbnail(of:for:)`から`CGImage`を取得する。ViewModelは`DocumentSession.document.page(at:)`をメインアクターで取得してこのレンダラーへ渡し、actorへは`CGImage`だけを保存する。

- [ ] **ステップ4: キャッシュテストと全テストを実行する**

実行: `swift test --filter PagePreviewCacheTests && swift test`

期待結果: 保持対象、破棄、同じページの置換、空集合のテストが成功する。

- [ ] **ステップ5: コミットする**

```bash
git add Sources/PDFComicViewer/Rendering/PagePreviewCache.swift Sources/PDFComicViewer/Reader/ReaderViewModel.swift Tests/PDFComicViewerTests/PagePreviewCacheTests.swift
git commit -m "perf: bound neighboring page preview cache"
```

---

### Task 10: `.app`生成と受け入れ確認

**ファイル:**
- 作成: `Resources/Info.plist`
- 作成: `scripts/build-app.sh`
- 作成: `.gitignore`
- 作成: `README.md`

**インターフェース:**
- 提供: `scripts/build-app.sh` → `build/PDFComicViewer.app`

- [ ] **ステップ1: アプリバンドル情報を書く**

`Info.plist`へ`CFBundleName = PDF漫画ビューアー`、`CFBundleIdentifier = com.srkppa.PDFComicViewer`、`CFBundleExecutable = PDFComicViewer`、`CFBundlePackageType = APPL`、`LSMinimumSystemVersion = 15.0`を設定する。`CFBundleDocumentTypes`で`com.adobe.pdf`をViewerとして宣言する。

- [ ] **ステップ2: 再現可能なビルドスクリプトを書く**

```bash
#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
swift build --package-path "$PROJECT_ROOT" -c release
BIN_PATH="$(swift build --package-path "$PROJECT_ROOT" -c release --show-bin-path)"
APP_PATH="$PROJECT_ROOT/build/PDFComicViewer.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/PDFComicViewer" "$APP_PATH/Contents/MacOS/PDFComicViewer"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
echo "$APP_PATH"
```

実行権限を付ける: `chmod +x scripts/build-app.sh`

`.gitignore`には`.build/`、`build/`、`.DS_Store`を登録する。READMEには必要環境、`swift test`、`scripts/build-app.sh`、生成されたアプリをFinderまたは`open build/PDFComicViewer.app`で開く方法、ショートカットを日本語で記載する。

- [ ] **ステップ3: テスト、releaseビルド、バンドル検証を実行する**

実行: `swift test && scripts/build-app.sh && plutil -lint Resources/Info.plist && test -x build/PDFComicViewer.app/Contents/MacOS/PDFComicViewer`

期待結果: 全テスト成功、`Info.plist: OK`、実行可能ファイルの存在確認が終了コード0になる。

- [ ] **ステップ4: 手動受け入れ確認を行う**

実行: `open build/PDFComicViewer.app`

次を順番に確認する。

1. 縦長6ページのPDFが`[1] [2,3] [4,5] [6]`で表示される。
2. 見開き位置をずらすと`[1,2] [3,4] [5,6]`になる。
3. 横長ページを含むPDFで、そのページだけが単独表示され、次の縦長ページから見開きが組み直される。
4. `1`と`2`で単ページ／見開きを切り替えられる。
5. ページ単位の自動・単独・見開き設定が反映される。
6. 右綴じと左綴じで左右配置、矢印、クリック領域が反転する。
7. 拡大、縮小、合わせる、パン、全画面が動作する。
8. パスワード付きPDFには入力画面、空または破損して開けないPDFには共通の日本語エラーが出る。
9. アプリを終了して同じPDFを開くと、読書位置と設定が復元される。
10. 数百ページのPDFを素早く送っても、遠いページのプレビューがキャッシュに残り続けない。

- [ ] **ステップ5: 最終検証を実行する**

実行: `swift test && swift build -c release && git diff --check && git status --short`

期待結果: テスト失敗0、releaseビルド成功、空白エラーなし。`git status --short`にはタスク10で追加した4ファイルだけが表示される。

- [ ] **ステップ6: コミットする**

```bash
git add .gitignore README.md Resources/Info.plist scripts/build-app.sh
git commit -m "build: package PDF comic viewer app"
```

- [ ] **ステップ7: コミット後の状態を確認する**

実行: `git status --short && git log --oneline -10`

期待結果: 作業ツリーが空で、タスク1〜10のコミットが順番に記録されている。
