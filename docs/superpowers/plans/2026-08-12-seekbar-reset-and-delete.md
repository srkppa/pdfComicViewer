# シークバー・最初に戻る・削除 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PDF漫画ビューアーに、下端ホバーで現れるシークバー、読書位置を先頭に戻す機能、複数選択によるゴミ箱移動を追加する。

**Architecture:** 綴じ方向の反転などの純粋ロジックは `Domain/` の独立した型に切り出してテストし、SwiftUIのView本体はテストしない（既存方針の踏襲）。ファイルシステム操作は `FileTrashing` プロトコルで抽象化してフェイク注入可能にする。読書位置ストアは `AppServices` で単一インスタンスを共有し、リーダーとサイドバーからの書き込み競合を防ぐ。

**Tech Stack:** Swift 6.0 / SwiftUI / AppKit / PDFKit / XCTest / Swift Package Manager

## Global Constraints

- プラットフォームは macOS 15 以上（`Package.swift` の `platforms: [.macOS(.v15)]`）。Swift tools version は 6.0。
- Swift 6 の strict concurrency を満たすこと。アクター境界を越える値は `Sendable` であること。
- ユーザーに見えるテキスト（ボタン名、メニュー項目、ツールチップ、エラー文言）はすべて日本語。
- コード内のコメントは日本語で、「なぜそうしたか」を書く。自明な処理の説明は書かない。
- テストは `swift test` で全件パスすること。着手前の基準は 135 件。
- ツールバーやサイドバーのアイコンボタンは既存の `iconButton` と同じ形（`.frame(width: 20, height: 20)` と `.contentShape(Rectangle())`）にすること。ホバー領域が小さすぎるとツールチップが出ない。
- SwiftUI の `.help()` は環境によって反映されないため、既存の `.nativeToolTip(_:)` を併記すること。
- コミットメッセージは英語の Conventional Commits 形式とし、末尾に次の行を入れる。

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

---

## ファイル構成

### 新規作成

| ファイル | 責務 |
|---|---|
| `Sources/PDFComicViewer/Domain/SeekBarPresentation.swift` | 表示単位インデックスとスライダー値の相互変換。綴じ方向の反転を閉じ込める |
| `Sources/PDFComicViewer/Persistence/FileTrashing.swift` | ゴミ箱移動のプロトコルとライブ実装 |
| `Sources/PDFComicViewer/UI/ReaderSeekBar.swift` | シークバーのView。ロジックは持たない |
| `Tests/PDFComicViewerTests/SeekBarPresentationTests.swift` | 上記変換のテスト |
| `Tests/PDFComicViewerTests/FileTrashServiceTests.swift` | ゴミ箱移動の失敗経路のテスト |

### 変更

| ファイル | 変更内容 |
|---|---|
| `Sources/PDFComicViewer/Reader/ReaderViewModel.swift` | `jumpToUnit(index:)` と `goToFirstPage()` を追加。`live()` を削除 |
| `Sources/PDFComicViewer/Persistence/ReadingProgressStore.swift` | `ReadingProgressStoring` に `remove(for:)` を追加し、`FileReadingProgressStore` に実装 |
| `Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift` | `progressStore` と `trashService` を注入。`pdfURLs(for:)` `resetProgress(for:)` `trash(urls:)` を追加 |
| `Sources/PDFComicViewer/UI/DirectorySidebarView.swift` | 複数選択、右クリックメニュー |
| `Sources/PDFComicViewer/UI/ReaderView.swift` | シークバーの配置とホバー検出、削除確認ダイアログ、`sidebarModel` を受け取る形に変更 |
| `Sources/PDFComicViewer/UI/ReaderToolbar.swift` | 「最初に戻る」「削除」ボタンを追加 |
| `Sources/PDFComicViewer/App/PDFComicViewerApp.swift` | `AppServices` に共有ストアと `sidebarModel` を持たせる |
| `README.md` | 追加機能の説明 |

---

### Task 1: シークバーの値変換ロジック

**Files:**
- Create: `Sources/PDFComicViewer/Domain/SeekBarPresentation.swift`
- Test: `Tests/PDFComicViewerTests/SeekBarPresentationTests.swift`

**Interfaces:**
- Consumes: 既存の `BindingDirection`（`Domain/ReaderTypes.swift`）
- Produces:
  - `SeekBarPresentation.sliderValue(unitIndex: Int, unitCount: Int, binding: BindingDirection) -> Double`
  - `SeekBarPresentation.unitIndex(sliderValue: Double, unitCount: Int, binding: BindingDirection) -> Int`

右綴じでは表示単位0（1ページ目）がスライダーの右端に対応する。左綴じでは左端。両関数は互いに逆変換になる。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/SeekBarPresentationTests.swift` を新規作成する。

```swift
import XCTest
@testable import PDFComicViewer

final class SeekBarPresentationTests: XCTestCase {
    func testRightBindingPlacesFirstUnitAtRightEnd() {
        let value = SeekBarPresentation.sliderValue(
            unitIndex: 0,
            unitCount: 10,
            binding: .right
        )

        XCTAssertEqual(value, 9)
    }

    func testLeftBindingPlacesFirstUnitAtLeftEnd() {
        let value = SeekBarPresentation.sliderValue(
            unitIndex: 0,
            unitCount: 10,
            binding: .left
        )

        XCTAssertEqual(value, 0)
    }

    func testSliderValueAndUnitIndexRoundTripForBothBindings() {
        for binding in [BindingDirection.right, BindingDirection.left] {
            for index in 0..<10 {
                let value = SeekBarPresentation.sliderValue(
                    unitIndex: index,
                    unitCount: 10,
                    binding: binding
                )
                let restored = SeekBarPresentation.unitIndex(
                    sliderValue: value,
                    unitCount: 10,
                    binding: binding
                )

                XCTAssertEqual(restored, index, "binding=\(binding) index=\(index)")
            }
        }
    }

    func testOutOfRangeInputsAreClamped() {
        XCTAssertEqual(
            SeekBarPresentation.sliderValue(unitIndex: -5, unitCount: 10, binding: .left),
            0
        )
        XCTAssertEqual(
            SeekBarPresentation.sliderValue(unitIndex: 99, unitCount: 10, binding: .left),
            9
        )
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: -3, unitCount: 10, binding: .left),
            0
        )
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: 99, unitCount: 10, binding: .left),
            9
        )
    }

    func testSingleUnitAndEmptyDocumentAreSafe() {
        XCTAssertEqual(
            SeekBarPresentation.sliderValue(unitIndex: 0, unitCount: 1, binding: .right),
            0
        )
        XCTAssertEqual(
            SeekBarPresentation.sliderValue(unitIndex: 0, unitCount: 0, binding: .right),
            0
        )
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: 0, unitCount: 0, binding: .right),
            0
        )
    }

    func testRoundingSnapsToNearestUnit() {
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: 3.4, unitCount: 10, binding: .left),
            3
        )
        XCTAssertEqual(
            SeekBarPresentation.unitIndex(sliderValue: 3.6, unitCount: 10, binding: .left),
            4
        )
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter SeekBarPresentationTests`
Expected: FAIL（`cannot find 'SeekBarPresentation' in scope` でビルドエラー）

- [ ] **Step 3: 最小限の実装を書く**

`Sources/PDFComicViewer/Domain/SeekBarPresentation.swift` を新規作成する。

```swift
import Foundation

/// シークバーのスライダー値と表示単位インデックスを相互変換する。
/// 綴じ方向による左右反転をここに閉じ込め、View側に条件分岐を散らさない。
enum SeekBarPresentation {
    /// 表示単位インデックス → スライダー値。右綴じでは左右を反転する。
    static func sliderValue(
        unitIndex: Int,
        unitCount: Int,
        binding: BindingDirection
    ) -> Double {
        guard unitCount > 1 else { return 0 }
        let clamped = min(max(unitIndex, 0), unitCount - 1)
        return binding == .right
            ? Double(unitCount - 1 - clamped)
            : Double(clamped)
    }

    /// スライダー値 → 表示単位インデックス。`sliderValue` の逆変換。
    static func unitIndex(
        sliderValue: Double,
        unitCount: Int,
        binding: BindingDirection
    ) -> Int {
        guard unitCount > 0 else { return 0 }
        let rounded = min(max(Int(sliderValue.rounded()), 0), unitCount - 1)
        return binding == .right
            ? unitCount - 1 - rounded
            : rounded
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `swift test --filter SeekBarPresentationTests`
Expected: PASS（6件）

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/Domain/SeekBarPresentation.swift Tests/PDFComicViewerTests/SeekBarPresentationTests.swift
git commit -m "$(cat <<'EOF'
feat: add seek bar value conversion with binding-aware direction

SeekBarPresentation maps between display-unit indexes and slider
values, reversing left/right for right-bound manga so the thumb moves
the same way the arrow keys and click regions already do.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 任意の表示単位へのジャンプ

**Files:**
- Modify: `Sources/PDFComicViewer/Reader/ReaderViewModel.swift`（`previous()` の直後、およそ175行目に追加）
- Test: `Tests/PDFComicViewerTests/ReaderViewModelTests.swift`（末尾のフィクスチャ定義より前に追加）

**Interfaces:**
- Consumes: なし
- Produces:
  - `ReaderViewModel.jumpToUnit(index: Int)` — 範囲外はクリップ。ドキュメント未読込時は何もしない
  - `ReaderViewModel.goToFirstPage()` — `jumpToUnit(index: 0)` を呼ぶ

既存の `next()` / `previous()` と同じ後処理（ページ更新、プレビュー再スケジュール、フィット、保存）を踏む。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/ReaderViewModelTests.swift` の最後のテストメソッドの直後（`@MainActor private final class FakePDFLoader` の定義より前）に追加する。

テストで使う `FakePDFLoader` `FakeProgressStore` `DocumentSession.fixture` は同ファイル内に既に定義されている。保存を検証するテストだけは実ファイルが要る。`currentRecord()` が `DocumentBookmarkService.makeBookmark(for:)` を呼び、存在しないパスでは例外になって保存が走らないため、既存の `makeTemporaryFileURL()` と `makeOpenedModel(pageCount:url:)` を使う。`pageCount: 5` は既定の見開き設定（`.spread` / `.coverSingle`）で3つの表示単位（single(0), pair(1,2), pair(3,4)）になる。

```swift
    func testJumpToUnitMovesToRequestedUnit() async {
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(.fixture(pageCount: 5))),
            progressStore: FakeProgressStore()
        )
        await model.open(url: URL(fileURLWithPath: "/tmp/comic.pdf"))

        model.jumpToUnit(index: 2)

        XCTAssertEqual(model.currentUnitIndex, 2)
        XCTAssertEqual(model.currentPhysicalPage, 3)
        XCTAssertEqual(model.preferences.lastPageIndex, 3)
    }

    func testJumpToUnitClampsOutOfRangeIndexes() async {
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(.fixture(pageCount: 5))),
            progressStore: FakeProgressStore()
        )
        await model.open(url: URL(fileURLWithPath: "/tmp/comic.pdf"))
        let lastIndex = model.displayUnits.count - 1

        model.jumpToUnit(index: 99)
        XCTAssertEqual(model.currentUnitIndex, lastIndex)

        model.jumpToUnit(index: -4)
        XCTAssertEqual(model.currentUnitIndex, 0)
    }

    func testJumpToUnitDoesNothingWithoutDocument() {
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(.fixture(pageCount: 1))),
            progressStore: FakeProgressStore()
        )

        model.jumpToUnit(index: 3)

        XCTAssertEqual(model.currentUnitIndex, 0)
        XCTAssertEqual(model.currentPhysicalPage, 0)
    }

    func testGoToFirstPageReturnsToFirstUnit() async {
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(.fixture(pageCount: 5))),
            progressStore: FakeProgressStore()
        )
        await model.open(url: URL(fileURLWithPath: "/tmp/comic.pdf"))
        model.next()
        model.next()
        XCTAssertNotEqual(model.currentUnitIndex, 0)

        model.goToFirstPage()

        XCTAssertEqual(model.currentUnitIndex, 0)
        XCTAssertEqual(model.currentPhysicalPage, 0)
        XCTAssertEqual(model.preferences.lastPageIndex, 0)
    }

    func testGoToFirstPagePersistsResetPosition() async throws {
        let url = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, store) = await makeOpenedModel(pageCount: 5, url: url)
        model.next()

        model.goToFirstPage()
        await model.flushPendingSaves()

        let saved = await store.savedRecords.last
        XCTAssertEqual(saved?.preferences.lastPageIndex, 0)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter ReaderViewModelTests`
Expected: FAIL（`value of type 'ReaderViewModel' has no member 'jumpToUnit'` でビルドエラー）

- [ ] **Step 3: 最小限の実装を書く**

`Sources/PDFComicViewer/Reader/ReaderViewModel.swift` の `previous()` の直後に追加する。

```swift
    /// シークバーや「最初に戻る」から任意の表示単位へ飛ぶ。
    /// 範囲外の指定は端にクリップし、呼び出し側にチェックを強いない。
    func jumpToUnit(index: Int) {
        guard !displayUnits.isEmpty else { return }
        let target = min(max(index, 0), displayUnits.count - 1)
        guard target != currentUnitIndex else { return }
        currentUnitIndex = target
        updateCurrentPageFromUnit()
        schedulePagePreviews()
        fitToWindow()
        scheduleSave()
    }

    func goToFirstPage() {
        jumpToUnit(index: 0)
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `swift test --filter ReaderViewModelTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/Reader/ReaderViewModel.swift Tests/PDFComicViewerTests/ReaderViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: add jumpToUnit and goToFirstPage to the reader

Both run the same post-move work as next()/previous() so the page
counter, preview cache, zoom fit, and debounced save all stay in sync.
Out-of-range indexes clamp instead of trapping.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 読書位置レコードの削除

**Files:**
- Modify: `Sources/PDFComicViewer/Persistence/ReadingProgressStore.swift`
- Modify: `Tests/PDFComicViewerTests/ReaderViewModelTests.swift`（`FakeProgressStore` に `remove(for:)` を追加）
- Test: `Tests/PDFComicViewerTests/ReadingProgressStoreTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `ReadingProgressStoring.remove(for url: URL) async throws` — 該当レコードを取り除く。存在しなくてもエラーにしない

削除したPDFの記録が残り続けないようにする。判定は既存の `save(_:)` と同じく「ブックマーク解決結果の一致、または `normalizedPath` の一致」を使う。ゴミ箱移動後はブックマークが移動先を指す可能性があるため、パス一致の側が効く。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/ReadingProgressStoreTests.swift` の `testSaveAfterRenameReplacesRecordResolvedByOldBookmark` の直後（`private func makeRecord` より前）に追加する。

```swift
    func testRemoveDeletesOnlyTheMatchingRecord() async throws {
        let store = FileReadingProgressStore(fileURL: progressFile)
        let kept = makeRecord(path: "/tmp/kept.pdf", lastPageIndex: 3)
        let removed = makeRecord(path: "/tmp/removed.pdf", lastPageIndex: 7)
        try await store.save(kept)
        try await store.save(removed)

        try await store.remove(for: URL(fileURLWithPath: "/tmp/removed.pdf"))

        let reloadedStore = FileReadingProgressStore(fileURL: progressFile)
        let records = try await reloadedStore.allRecords()
        XCTAssertEqual(records, [kept])
    }

    func testRemoveForUnknownURLIsHarmless() async throws {
        let store = FileReadingProgressStore(fileURL: progressFile)
        let kept = makeRecord(path: "/tmp/kept.pdf", lastPageIndex: 3)
        try await store.save(kept)

        try await store.remove(for: URL(fileURLWithPath: "/tmp/never-saved.pdf"))

        let records = try await store.allRecords()
        XCTAssertEqual(records, [kept])
    }

    func testRemoveMatchesRecordSavedUnderBookmarkedPath() async throws {
        let file = temporaryDirectory.appending(path: "comic.pdf")
        try Data([0]).write(to: file)
        let record = makeRecord(
            bookmarkData: try DocumentBookmarkService.makeBookmark(for: file),
            path: file.standardizedFileURL.path,
            lastPageIndex: 5
        )
        let store = FileReadingProgressStore(fileURL: progressFile)
        try await store.save(record)

        try await store.remove(for: file)

        let records = try await store.allRecords()
        XCTAssertTrue(records.isEmpty)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter ReadingProgressStoreTests`
Expected: FAIL（`value of type 'FileReadingProgressStore' has no member 'remove'` でビルドエラー）

- [ ] **Step 3: プロトコルと実装を書く**

`Sources/PDFComicViewer/Persistence/ReadingProgressStore.swift` のプロトコル定義を差し替える。

```swift
protocol ReadingProgressStoring: Sendable {
    func load(for url: URL) async throws -> DocumentRecord?
    func save(_ record: DocumentRecord) async throws
    func allRecords() async throws -> [DocumentRecord]
    func remove(for url: URL) async throws
}
```

`FileReadingProgressStore` の `allRecords()` の直後に実装を追加する。

```swift
    /// PDFを削除したときに、対応する読書位置レコードを残さないための後片付け。
    /// ゴミ箱へ移した後はブックマークが移動先を指すことがあるため、
    /// `save(_:)` と同じくパス一致でも判定する。
    func remove(for url: URL) throws {
        let target = url.standardizedFileURL
        var values = try loadRecords()
        values.removeAll { existing in
            if existing.normalizedPath == target.path {
                return true
            }
            guard let resolved = try? DocumentBookmarkService.resolve(
                existing.bookmarkData
            ).standardizedFileURL else {
                return false
            }
            return resolved == target
        }

        let data = try JSONEncoder().encode(values)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        records = values
    }
```

- [ ] **Step 4: フェイクにも追加する**

`Tests/PDFComicViewerTests/ReaderViewModelTests.swift` の `private actor FakeProgressStore` 内、`allRecords()` の直後に追加する。

```swift
    var removedURLs: [URL] = []

    func remove(for url: URL) throws {
        removedURLs.append(url)
        guard record?.normalizedPath == url.standardizedFileURL.path else { return }
        record = nil
    }
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `swift test`
Expected: PASS（既存分と合わせて全件）

- [ ] **Step 6: コミット**

```bash
git add Sources/PDFComicViewer/Persistence/ReadingProgressStore.swift Tests/PDFComicViewerTests/ReadingProgressStoreTests.swift Tests/PDFComicViewerTests/ReaderViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: let the progress store remove a record

Deleting a PDF should not leave its reading position behind. Matching
reuses save()'s rule (resolved bookmark or normalized path) so it still
finds the record after the file has been moved to the trash.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: ゴミ箱移動サービス

**Files:**
- Create: `Sources/PDFComicViewer/Persistence/FileTrashing.swift`
- Test: `Tests/PDFComicViewerTests/FileTrashServiceTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `protocol FileTrashing: Sendable { func trash(_ urls: [URL]) async -> [URL] }` — 失敗したURLだけを返す（全件成功なら空配列）
  - `struct FileTrashService: FileTrashing`

エラーの内容ではなく失敗URLだけを返す。表示に必要なのは件数だけであり、`any Error` を戻り値に含めると Swift 6 の `Sendable` 制約を満たすための包み直しが必要になるため。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/FileTrashServiceTests.swift` を新規作成する。

成功経路（実際にファイルがゴミ箱へ移る）はユーザーの実際のゴミ箱を汚すため自動テストしない。フェイクを使うViewModel側のテスト（Task 6）と手元での動作確認で担保する。

```swift
import XCTest
@testable import PDFComicViewer

final class FileTrashServiceTests: XCTestCase {
    func testMissingFileIsReportedAsFailure() async {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "FileTrashServiceTests-missing-\(UUID().uuidString).pdf")

        let failures = await FileTrashService().trash([missing])

        XCTAssertEqual(failures, [missing])
    }

    func testEmptyInputReturnsNoFailures() async {
        let failures = await FileTrashService().trash([])

        XCTAssertTrue(failures.isEmpty)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter FileTrashServiceTests`
Expected: FAIL（`cannot find 'FileTrashService' in scope` でビルドエラー）

- [ ] **Step 3: 最小限の実装を書く**

`Sources/PDFComicViewer/Persistence/FileTrashing.swift` を新規作成する。

```swift
import Foundation

protocol FileTrashing: Sendable {
    /// ゴミ箱へ移動し、失敗したURLだけを返す（全件成功なら空配列）。
    func trash(_ urls: [URL]) async -> [URL]
}

struct FileTrashService: FileTrashing {
    func trash(_ urls: [URL]) async -> [URL] {
        guard !urls.isEmpty else { return [] }
        // ファイルI/Oのため、既存の DirectoryScanner と同じく
        // バックグラウンドで実行して結果だけをメインアクターへ返す。
        return await Task.detached(priority: .userInitiated) {
            var failures: [URL] = []
            for url in urls {
                do {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(
                        at: url,
                        resultingItemURL: &resultingURL
                    )
                } catch {
                    failures.append(url)
                }
            }
            return failures
        }.value
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `swift test --filter FileTrashServiceTests`
Expected: PASS（2件）

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/Persistence/FileTrashing.swift Tests/PDFComicViewerTests/FileTrashServiceTests.swift
git commit -m "$(cat <<'EOF'
feat: add a move-to-trash service behind a protocol

Returns only the URLs that failed, which is all the UI needs for its
message and avoids carrying a non-Sendable error across actors. The
protocol lets view model tests inject a fake instead of touching the
real trash.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 読書位置ストアの共有配線

**Files:**
- Modify: `Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift`
- Modify: `Sources/PDFComicViewer/Reader/ReaderViewModel.swift`（`live()` を削除）
- Modify: `Sources/PDFComicViewer/App/PDFComicViewerApp.swift`
- Modify: `Sources/PDFComicViewer/UI/ReaderView.swift`
- Modify: `Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift`

**Interfaces:**
- Consumes: `FileTrashing`（Task 4）、`ReadingProgressStoring.remove(for:)`（Task 3）
- Produces:
  - `DirectorySidebarViewModel.init(scanner:progressStore:trashService:)` — `progressStore` と `trashService` は必須
  - `AppServices.progressStore` / `AppServices.readerModel` / `AppServices.sidebarModel`
  - `ReaderView.init(model:sidebarModel:)`

`FileReadingProgressStore` はactorでレコード全体をメモリキャッシュしている。同じJSONを指す別インスタンスを2つ作ると、サイドバー側のリセットをリーダー側の古いキャッシュが上書きして消してしまう。そのため**必ず単一インスタンスを共有する**。`progressStore` に既定値を与えない（既定値があると、うっかりこのバグを再導入できてしまう）。

- [ ] **Step 1: 依存を受け取れるようにする**

`Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift` のプロパティと `init` を差し替える。

```swift
    private let scanner: any DirectoryScanning
    private let progressStore: any ReadingProgressStoring
    private let trashService: any FileTrashing
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0

    init(
        scanner: any DirectoryScanning = DirectoryScanner(),
        progressStore: any ReadingProgressStoring,
        trashService: any FileTrashing = FileTrashService()
    ) {
        self.scanner = scanner
        self.progressStore = progressStore
        self.trashService = trashService
    }
```

- [ ] **Step 2: 既存テストの生成箇所をヘルパー経由にする**

`Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift` の末尾、`private actor FakeDirectoryScanner` の定義より前に、フェイクとヘルパーを追加する。

```swift
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
```

同ファイルの `DirectorySidebarViewModelTests` クラス内、`private func waitUntil` の直前にヘルパーを追加する。

```swift
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
```

既存の生成箇所7つを機械的に置き換える。

```bash
sed -i '' 's/DirectorySidebarViewModel(scanner: /makeModel(scanner: /g' Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift
```

`makeModel` 自身の中では `DirectorySidebarViewModel(` の直後で改行しているため、この置換に巻き込まれない。置換結果を必ず確認する。

```bash
grep -c 'makeModel(scanner: ' Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift   # 7 になること
grep -c 'DirectorySidebarViewModel(scanner: ' Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift   # 0 になること
```

- [ ] **Step 3: `AppServices` に共有インスタンスを持たせる**

`Sources/PDFComicViewer/App/PDFComicViewerApp.swift` の `AppServices` を差し替える。`private` を外し、`ReaderView` から見えるようにする。

```swift
@MainActor
enum AppServices {
    /// リーダーとサイドバーの両方が読書位置を書き換えるため、
    /// ストアは必ず1インスタンスだけを共有する。
    /// 別インスタンスにすると、actor内のキャッシュ同士が古い内容で
    /// 上書きし合い、リセットや保存が消える。
    static let progressStore: any ReadingProgressStoring = FileReadingProgressStore(
        fileURL: ReaderViewModel.progressFileURL(
            applicationSupportDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
        )
    )

    static let readerModel = ReaderViewModel(
        loader: PDFDocumentLoader(),
        progressStore: progressStore
    )

    static let sidebarModel = DirectorySidebarViewModel(progressStore: progressStore)
}
```

`import Foundation` が未追加なら足す（`FileManager` を使うため。既に `AppKit` を import しているので通常は不要）。

- [ ] **Step 4: `ReaderViewModel.live()` を削除する**

`Sources/PDFComicViewer/Reader/ReaderViewModel.swift` から `static func live(fileManager:)` を丸ごと削除する。`progressFileURL(applicationSupportDirectory:)` は `AppServices` が使うので残す。

- [ ] **Step 5: `ReaderView` がサイドバーモデルを受け取るようにする**

`Sources/PDFComicViewer/UI/ReaderView.swift` の

```swift
    @StateObject private var sidebarModel = DirectorySidebarViewModel()
```

を次に差し替える（`@ObservedObject var model` の直後へ移動する）。

```swift
    @ObservedObject var sidebarModel: DirectorySidebarViewModel
```

`Sources/PDFComicViewer/App/PDFComicViewerApp.swift` の `PDFComicViewerApp` を差し替える。

```swift
@main
struct PDFComicViewerApp: App {
    @NSApplicationDelegateAdaptor(PDFComicViewerAppDelegate.self) private var appDelegate
    @StateObject private var model: ReaderViewModel
    @StateObject private var sidebarModel: DirectorySidebarViewModel

    init() {
        _model = StateObject(wrappedValue: AppServices.readerModel)
        _sidebarModel = StateObject(wrappedValue: AppServices.sidebarModel)
    }

    var body: some Scene {
        WindowGroup(AppConfiguration.applicationName) {
            ReaderView(model: model, sidebarModel: sidebarModel)
                .frame(minWidth: 900, minHeight: 650)
                .onOpenURL { url in
                    Task { await model.openExternalURL(url) }
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            ReaderCommands(model: model)
        }
    }
}
```

- [ ] **Step 6: ビルドとテストが通ることを確認する**

Run: `swift build && swift test`
Expected: ビルド成功、テスト全件PASS（件数は変わらない）

- [ ] **Step 7: コミット**

```bash
git add Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift Sources/PDFComicViewer/Reader/ReaderViewModel.swift Sources/PDFComicViewer/App/PDFComicViewerApp.swift Sources/PDFComicViewer/UI/ReaderView.swift Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift
git commit -m "$(cat <<'EOF'
refactor: share one reading-progress store across both view models

FileReadingProgressStore caches every record in the actor, so two
instances pointing at the same JSON overwrite each other with stale
data. The sidebar is about to start writing progress, so AppServices
now owns a single store and hands it to both view models. progressStore
is deliberately left without a default so the bug cannot come back.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: サイドバーの削除と進捗リセット

**Files:**
- Modify: `Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift`
- Test: `Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift`

**Interfaces:**
- Consumes: `FileTrashing`、`ReadingProgressStoring`（Task 5 で注入済み）
- Produces:
  - `DirectorySidebarViewModel.pdfURLs(for ids: Set<String>) -> [URL]` — 選択IDのうちPDFのURLだけを返す
  - `DirectorySidebarViewModel.resetProgress(for urls: [URL]) async`
  - `DirectorySidebarViewModel.trash(urls: [URL]) async -> Int` — 失敗件数を返す

削除失敗の文言はサイドバーの `errorMessage` には入れない。`errorMessage` はツリー全体を差し替えて表示されるため、削除に失敗しただけで一覧が消えてしまう。呼び出し側（`ReaderView`）が戻り値の件数を見て、リーダーの警告バナー（`warningMessage`）に出す。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift` の `testSortedNodesReflectsSortKeyAndDirection` の直後に追加する。

```swift
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

        let reloaded = await store.load(for: pdfURL)
        XCTAssertEqual(reloaded?.preferences.lastPageIndex, 0)
    }

    func testResetProgressIgnoresURLsWithoutRecord() async throws {
        let store = FakeSidebarProgressStore()
        let model = makeModel(
            scanner: FakeDirectoryScanner(result: .success([])),
            progressStore: store
        )

        await model.resetProgress(for: [URL(fileURLWithPath: "/tmp/comics/unknown.pdf")])

        let records = await store.allRecords()
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
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `swift test --filter DirectorySidebarViewModelTests`
Expected: FAIL（`value of type 'DirectorySidebarViewModel' has no member 'pdfURLs'` でビルドエラー）

- [ ] **Step 3: 最小限の実装を書く**

`Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift` の `reload()` の直後に追加する。

```swift
    /// 選択中のIDのうち、PDFのURLだけを返す。
    /// フォルダごとの削除は誤操作の影響が大きいため対象外にしている。
    func pdfURLs(for ids: Set<String>) -> [URL] {
        ids.compactMap { nodes.firstNode(withID: $0) }
            .filter { $0.kind == .pdf }
            .map(\.url)
    }

    /// 保存済みの読書位置を先頭に戻す。記録が無いPDFは元から先頭なので何もしない。
    func resetProgress(for urls: [URL]) async {
        for url in urls {
            guard var record = try? await progressStore.load(for: url) else { continue }
            record.preferences.lastPageIndex = 0
            try? await progressStore.save(record)
        }
    }

    /// ゴミ箱へ移動し、成功した分のレコードを消してツリーを再スキャンする。
    /// 戻り値は失敗件数。文言の組み立ては呼び出し側に任せる
    /// （`errorMessage` に入れるとツリー全体が差し替わって一覧が消えるため）。
    @discardableResult
    func trash(urls: [URL]) async -> Int {
        guard !urls.isEmpty else { return 0 }
        let failures = Set(await trashService.trash(urls))
        for url in urls where !failures.contains(url) {
            try? await progressStore.remove(for: url)
        }
        // 全件失敗しても再スキャンする。実際のファイル状態に一覧を追従させるため。
        reload()
        return failures.count
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `swift test`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift Tests/PDFComicViewerTests/DirectorySidebarViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: add trash and progress-reset to the sidebar view model

trash() moves the files, drops the progress record for each one that
succeeded, rescans the tree, and returns the failure count. The count
goes back to the caller rather than into errorMessage, which would
replace the whole tree with a message on a partial failure.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: シークバーのViewと配置

**Files:**
- Create: `Sources/PDFComicViewer/UI/ReaderSeekBar.swift`
- Modify: `Sources/PDFComicViewer/UI/ReaderView.swift`

**Interfaces:**
- Consumes: `SeekBarPresentation`（Task 1）、`ReaderViewModel.jumpToUnit(index:)`（Task 2）、既存の `ReaderPresentation.pageCounterText(for:totalPages:)`
- Produces: `ReaderSeekBar(model:)`

ドラッグ中はスライダー値だけを `@State` に持ち、120ms 値が変化しなかったときに初めてジャンプする。`PagePreviewRenderer` が `@MainActor` で 1024×1024 のページ描画をメインスレッドで行うため、つまみを動かすたびにジャンプすると描画とキャンセルが連鎖してつまみ自体がカクつく。

- [ ] **Step 1: シークバーViewを作る**

`Sources/PDFComicViewer/UI/ReaderSeekBar.swift` を新規作成する。

```swift
import SwiftUI

@MainActor
struct ReaderSeekBar: View {
    @ObservedObject var model: ReaderViewModel

    /// ドラッグ中だけ値を保持する。nilならモデルの現在位置をそのまま映す。
    @State private var draggingValue: Double?
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            Slider(
                value: sliderBinding,
                in: 0...Double(max(unitCount - 1, 1)),
                step: 1,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        commitImmediately()
                    }
                }
            )
            .accessibilityLabel("ページ位置")

            Text(labelText)
                .font(.system(.callout, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(ReaderTheme.secondaryText)
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ReaderTheme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(ReaderTheme.border.opacity(0.8), lineWidth: 1)
        }
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
        }
    }

    private var unitCount: Int {
        model.displayUnits.count
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                draggingValue ?? SeekBarPresentation.sliderValue(
                    unitIndex: model.currentUnitIndex,
                    unitCount: unitCount,
                    binding: model.preferences.binding
                )
            },
            set: { newValue in
                draggingValue = newValue
                scheduleCommit()
            }
        )
    }

    private var labelText: String {
        guard let session = model.session else { return "—" }
        let index = draggingValue.map(targetUnitIndex(for:)) ?? model.currentUnitIndex
        guard model.displayUnits.indices.contains(index) else { return "—" }
        return ReaderPresentation.pageCounterText(
            for: model.displayUnits[index],
            totalPages: session.pages.count
        )
    }

    private func targetUnitIndex(for value: Double) -> Int {
        SeekBarPresentation.unitIndex(
            sliderValue: value,
            unitCount: unitCount,
            binding: model.preferences.binding
        )
    }

    /// つまみが落ち着くまでジャンプを遅らせる。
    /// 一気に振ったときに途中のページ描画をまとめて飛ばすため。
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            commitImmediately()
        }
    }

    private func commitImmediately() {
        commitTask?.cancel()
        commitTask = nil
        guard let value = draggingValue else { return }
        draggingValue = nil
        model.jumpToUnit(index: targetUnitIndex(for: value))
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認する**

Run: `swift build`
Expected: 成功

- [ ] **Step 3: `ReaderView` にホバー検出と配置を足す**

`Sources/PDFComicViewer/UI/ReaderView.swift` の `@State private var sidebarWidthAtDragStart: CGFloat?` の直後に状態を追加する。

```swift
    @State private var readerAreaHeight: CGFloat = 0
    @State private var pointerIsNearBottom = false
    @State private var hideSeekBarTask: Task<Void, Never>?
```

`readerArea` の定義の直前（`private var readerArea: some View {` の前）に、表示条件とホバー処理を追加する。

```swift
    /// シークバーを実際に出してよいか。飛ぶ先が無いときは出さない。
    private var seekBarIsShown: Bool {
        pointerIsNearBottom
            && model.session != nil
            && model.displayUnits.count > 1
    }

    /// 下端から80pt以内にポインタがあるかどうかで表示を切り替える。
    /// 出したまま消えるとつまみを掴めないので、離れてから0.4秒待って隠す。
    private func updateSeekBarVisibility(isNearBottom: Bool) {
        if isNearBottom {
            hideSeekBarTask?.cancel()
            hideSeekBarTask = nil
            if !pointerIsNearBottom {
                pointerIsNearBottom = true
            }
        } else if pointerIsNearBottom, hideSeekBarTask == nil {
            hideSeekBarTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                pointerIsNearBottom = false
                hideSeekBarTask = nil
            }
        }
    }
```

`readerArea` の `.contextMenu { pageOverrideMenu }` の直後に、以下を追加する。

```swift
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            readerAreaHeight = height
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                updateSeekBarVisibility(
                    isNearBottom: readerAreaHeight > 0
                        && location.y > readerAreaHeight - 80
                )
            case .ended:
                updateSeekBarVisibility(isNearBottom: false)
            }
        }
        .overlay(alignment: .bottom) {
            if seekBarIsShown {
                ReaderSeekBar(model: model)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: seekBarIsShown)
```

- [ ] **Step 4: クリックの二重反応を防ぐ**

同ファイルの `ReaderInputMonitor` に渡している `excludedBottomHeight` を差し替える。

```swift
                excludedBottomHeight: max(
                    model.warningMessage == nil ? 0 : 52,
                    seekBarIsShown ? 64 : 0
                ),
```

`ReaderInputMonitor` はAppKitのローカルイベントモニタで、SwiftUIのヒットテストと無関係にクリックを拾う。除外しないとシークバー上のクリックがページめくりも起こす。隠れている間は0なので、通常の左右クリックめくりは画面全体で従来どおり効く。

`.onDisappear` に後片付けを足す。

```swift
        .onDisappear {
            hideControlsTask?.cancel()
            hideSeekBarTask?.cancel()
        }
```

- [ ] **Step 5: ビルドとテストを確認する**

Run: `swift build && swift test`
Expected: ビルド成功、テスト全件PASS

- [ ] **Step 6: 手元で動作確認する**

Run: `scripts/install-app.sh`

確認項目:
- PDFを開き、ポインタを本文下端に寄せるとシークバーが現れる
- ポインタをバーの上に置いても消えない。離れると0.4秒ほどで消える
- 右綴じで、1ページ目のときつまみが右端にある
- つまみをゆっくり動かすとページが追従し、一気に振ってもカクつかない
- バーの上をクリックしてもページがめくれない
- バーが消えている状態では、画面下部のクリックでページがめくれる

- [ ] **Step 7: コミット**

```bash
git add Sources/PDFComicViewer/UI/ReaderSeekBar.swift Sources/PDFComicViewer/UI/ReaderView.swift
git commit -m "$(cat <<'EOF'
feat: add a hover-revealed seek bar to the reader

The bar fades in when the pointer comes within 80pt of the bottom and
runs right-to-left for right-bound manga. Dragging debounces for 120ms
before jumping, because preview rendering is main-actor bound and
re-rendering on every thumb movement makes the drag itself stutter.
While the bar is up its height feeds excludedBottomHeight so clicks on
it do not also turn the page.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: サイドバーの複数選択

**Files:**
- Modify: `Sources/PDFComicViewer/UI/DirectorySidebarView.swift`

**Interfaces:**
- Consumes: なし
- Produces: `DirectorySidebarView` 内の `selectedNodeIDs: Set<String>`（次タスクの右クリックメニューが使う）

- [ ] **Step 1: 選択状態を集合に変える**

`Sources/PDFComicViewer/UI/DirectorySidebarView.swift` の

```swift
    @State private var selectedNodeID: String?
```

を差し替える。

```swift
    @State private var selectedNodeIDs: Set<String> = []
```

`content` 内の `List` を差し替える。

```swift
            List(model.sortedNodes, children: \.children, selection: $selectedNodeIDs) { node in
                row(for: node)
            }
```

`openSelectedPDF()` を差し替える。複数選択できるようになったため、Returnキーは「PDFがちょうど1つだけ選ばれている」ときにのみ開く。

```swift
    /// 選択中のノードがPDF1つだけなら開く。矢印キーで選んだ後にリターンキーで決定する導線。
    /// 複数選択中は、どれを開くべきか決められないので何もしない。
    private func openSelectedPDF() {
        guard selectedNodeIDs.count == 1,
              let id = selectedNodeIDs.first,
              let node = model.nodes.firstNode(withID: id),
              node.kind == .pdf else { return }
        openPDF(node.url)
    }
```

- [ ] **Step 2: ビルドとテストを確認する**

Run: `swift build && swift test`
Expected: ビルド成功、テスト全件PASS

- [ ] **Step 3: 手元で動作確認する**

Run: `scripts/install-app.sh`

確認項目:
- ⌘クリック・⇧クリックで複数のPDFを選択できる
- 1つだけ選んで `Return` を押すと開く
- 複数選んで `Return` を押しても何も起きない
- PDFをクリックして開く従来動作が変わっていない

- [ ] **Step 4: コミット**

```bash
git add Sources/PDFComicViewer/UI/DirectorySidebarView.swift
git commit -m "$(cat <<'EOF'
feat: allow multi-selection in the directory sidebar

Command- and shift-click now select several rows, which the upcoming
bulk delete needs. Return still opens a PDF, but only when exactly one
is selected.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: 右クリックメニューと削除確認ダイアログ

**Files:**
- Modify: `Sources/PDFComicViewer/UI/DirectorySidebarView.swift`
- Modify: `Sources/PDFComicViewer/UI/ReaderView.swift`

**Interfaces:**
- Consumes: `DirectorySidebarViewModel.pdfURLs(for:)` / `resetProgress(for:)` / `trash(urls:)`（Task 6）、`ReaderViewModel.goToFirstPage()`（Task 2）
- Produces:
  - `DirectorySidebarView` の新しいクロージャ引数 `resetProgress: ([URL]) -> Void` と `requestDelete: ([URL]) -> Void`
  - `ReaderView` 内の `PendingDeletion` 状態

`.contextMenu(forSelectionType:)` を使うと、SwiftUIがmacOS標準の作法（選択済み行の右クリックは選択全体、選択外の行の右クリックはその1件）を担ってくれる。

- [ ] **Step 1: サイドバーに右クリックメニューを足す**

`Sources/PDFComicViewer/UI/DirectorySidebarView.swift` のプロパティ宣言に2つ追加する（`hideSidebar` の直後）。

```swift
    let resetProgress: ([URL]) -> Void
    let requestDelete: ([URL]) -> Void
```

`content` 内の `List` に `.contextMenu(forSelectionType:)` を足す。`.onKeyPress(.return)` の直後に置く。

```swift
            .contextMenu(forSelectionType: String.self) { ids in
                contextMenuItems(for: ids)
            }
```

`openSelectedPDF()` の直前にメニュー本体を追加する。

```swift
    @ViewBuilder
    private func contextMenuItems(for ids: Set<String>) -> some View {
        let urls = model.pdfURLs(for: ids)
        if !urls.isEmpty {
            Button("最初に戻る") {
                resetProgress(urls)
            }
            Divider()
            Button("ゴミ箱に入れる", role: .destructive) {
                requestDelete(urls)
            }
        }
    }
```

- [ ] **Step 2: `ReaderView` に確認ダイアログと配線を足す**

`Sources/PDFComicViewer/UI/ReaderView.swift` のファイル先頭、`private enum FileImportKind` の直後に型を追加する。

```swift
/// 削除確認ダイアログの対象。ダイアログは `ReaderView` に1つだけ置き、
/// サイドバーの右クリックとツールバーのボタンの両方から使う。
private struct PendingDeletion: Identifiable {
    let id = UUID()
    let urls: [URL]
}
```

状態を追加する（`@State private var hideSeekBarTask` の直後）。

```swift
    @State private var pendingDeletion: PendingDeletion?
```

`DirectorySidebarView(...)` の生成に2つの引数を足す。

```swift
                DirectorySidebarView(
                    model: sidebarModel,
                    currentFileURL: model.session?.url,
                    chooseFolder: { fileImportKind = .folder },
                    openPDF: { url in Task { await model.open(url: url) } },
                    hideSidebar: { model.sidebarIsVisible = false },
                    resetProgress: resetProgress(for:),
                    requestDelete: { urls in pendingDeletion = PendingDeletion(urls: urls) }
                )
```

`.alert("PDFを開けません", ...)` の直後に確認ダイアログを追加する。

```swift
        .alert(
            deleteConfirmationTitle(for: pendingDeletion?.urls ?? []),
            isPresented: deleteConfirmationIsPresented,
            presenting: pendingDeletion
        ) { deletion in
            Button("ゴミ箱に入れる", role: .destructive) {
                performDeletion(of: deletion.urls)
            }
            Button("キャンセル", role: .cancel) {}
        } message: { deletion in
            Text(deleteConfirmationMessage(for: deletion.urls))
        }
```

`Alert(primaryButton:secondaryButton:)` を返す古い形は非推奨のため使わない。表示状態のBindingは、同ファイルの `passwordSheetIsPresented` / `errorAlertIsPresented` と同じ書式で `errorAlertIsPresented` の直後に足す。

```swift
    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }
```

`handleInput(_:)` の直前に処理を追加する。

```swift
    private func resetProgress(for urls: [URL]) {
        let openURL = model.session?.url.standardizedFileURL
        let storedURLs = urls.filter { $0.standardizedFileURL != openURL }
        if urls.contains(where: { $0.standardizedFileURL == openURL }) {
            model.goToFirstPage()
        }
        guard !storedURLs.isEmpty else { return }
        Task { await sidebarModel.resetProgress(for: storedURLs) }
    }

    private func deleteConfirmationTitle(for urls: [URL]) -> String {
        urls.count == 1
            ? "「\(urls[0].lastPathComponent)」をゴミ箱に入れますか？"
            : "\(urls.count)個のPDFをゴミ箱に入れますか？"
    }

    private func deleteConfirmationMessage(for urls: [URL]) -> String {
        let listed = urls.prefix(5).map(\.lastPathComponent)
        let remainder = urls.count - listed.count
        let names = listed.joined(separator: "\n")
        return remainder > 0 ? "\(names)\nほか\(remainder)件" : names
    }

    private func performDeletion(of urls: [URL]) {
        Task {
            // PDFKitがファイルを掴んだままにしないよう、
            // 開いているPDFが対象なら先に閉じる。
            let openURL = model.session?.url.standardizedFileURL
            if urls.contains(where: { $0.standardizedFileURL == openURL }) {
                await model.closeDocument()
            }
            let failureCount = await sidebarModel.trash(urls: urls)
            if failureCount > 0 {
                model.warningMessage = "\(failureCount)件を削除できませんでした。"
            }
        }
    }
```

- [ ] **Step 3: ビルドとテストを確認する**

Run: `swift build && swift test`
Expected: ビルド成功、テスト全件PASS

- [ ] **Step 4: 手元で動作確認する**

Run: `scripts/install-app.sh`

確認項目:
- PDF行を右クリックすると「最初に戻る」「ゴミ箱に入れる」が出る
- フォルダ行だけを右クリックしてもメニュー項目が出ない
- 複数選択した状態で選択内の行を右クリックすると、選択全体が対象になる
- 選択外の行を右クリックすると、その1件だけが対象になる
- 確認ダイアログのタイトルが1件と複数で切り替わる
- 削除するとファイルがゴミ箱に入り、一覧から消える
- 開いているPDFを削除すると、表示が空状態に戻る
- 別のPDFで途中まで読み、右クリックで「最初に戻る」→ 開き直すと1ページ目から始まる
- サイドバーで「最初に戻る」した後にリーダーでページを送っても、リセットが取り消されない（ストア共有の確認）

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/UI/DirectorySidebarView.swift Sources/PDFComicViewer/UI/ReaderView.swift
git commit -m "$(cat <<'EOF'
feat: add sidebar context menu for reset and move-to-trash

contextMenu(forSelectionType:) gives the standard macOS behaviour where
right-clicking inside the selection acts on all of it and right-clicking
outside acts on that row alone. Deleting closes the document first when
it is one of the targets, so PDFKit is not holding the file.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: ツールバーのボタン

**Files:**
- Modify: `Sources/PDFComicViewer/UI/ReaderToolbar.swift`
- Modify: `Sources/PDFComicViewer/UI/ReaderView.swift`

**Interfaces:**
- Consumes: `ReaderViewModel.goToFirstPage()`（Task 2）、`ReaderView` の `pendingDeletion`（Task 9）
- Produces: `ReaderToolbar.init(model:sidebarIsVisible:requestDelete:keyboardFocusChange:)`

削除は確認ダイアログを `ReaderView` に置いているため、ツールバーからはクロージャで依頼する。

- [ ] **Step 1: ツールバーにボタンを足す**

`Sources/PDFComicViewer/UI/ReaderToolbar.swift` の `FocusedReaderControl` に2つ追加する。

```swift
private enum FocusedReaderControl: Hashable {
    case open
    case binding
    case displayMode
    case alignment
    case firstPage
    case zoomOut
    case fit
    case zoomIn
    case close
    case delete
    case sidebar
    case fullScreen
}
```

`ReaderToolbar` のプロパティと `init` を差し替える。

```swift
    @ObservedObject var model: ReaderViewModel
    @Binding var sidebarIsVisible: Bool
    @FocusState private var focusedControl: FocusedReaderControl?

    let requestDelete: ([URL]) -> Void
    let keyboardFocusChange: (Bool) -> Void

    init(
        model: ReaderViewModel,
        sidebarIsVisible: Binding<Bool>,
        requestDelete: @escaping ([URL]) -> Void,
        keyboardFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self._sidebarIsVisible = sidebarIsVisible
        self.requestDelete = requestDelete
        self.keyboardFocusChange = keyboardFocusChange
    }
```

`body` 内、「見開き位置を1ページずらす」ボタンの直後に「最初に戻る」を追加する。

```swift
            iconButton(
                "最初に戻る",
                systemImage: "backward.end",
                action: model.goToFirstPage
            )
            .disabled(model.session == nil)
            .focused($focusedControl, equals: .firstPage)
```

「PDFを閉じる」ボタンの直後に「削除」を追加する。

```swift
            iconButton(
                "このPDFをゴミ箱に入れる",
                systemImage: "trash",
                action: {
                    guard let url = model.session?.url else { return }
                    requestDelete([url])
                }
            )
            .disabled(model.session == nil)
            .focused($focusedControl, equals: .delete)
```

- [ ] **Step 2: 呼び出し側を直す**

`Sources/PDFComicViewer/UI/ReaderView.swift` にある `ReaderToolbar(...)` の生成2箇所（全画面時のオーバーレイと `.toolbar` 内）の両方に引数を足す。

```swift
                        ReaderToolbar(
                            model: model,
                            sidebarIsVisible: $model.sidebarIsVisible,
                            requestDelete: { urls in
                                pendingDeletion = PendingDeletion(urls: urls)
                            },
                            keyboardFocusChange: { focused in
                                toolbarControlHasKeyboardFocus = focused
                            }
                        )
```

- [ ] **Step 3: ビルドとテストを確認する**

Run: `swift build && swift test`
Expected: ビルド成功、テスト全件PASS

- [ ] **Step 4: 手元で動作確認する**

Run: `scripts/install-app.sh`

確認項目:
- PDF未読込のとき、両ボタンが無効化されている
- 「最初に戻る」で1ページ目へ戻る
- ゴミ箱ボタンで確認ダイアログが出て、削除すると表示が空状態に戻り、サイドバーからも消える
- 両ボタンにマウスを乗せるとツールチップが出る

- [ ] **Step 5: コミット**

```bash
git add Sources/PDFComicViewer/UI/ReaderToolbar.swift Sources/PDFComicViewer/UI/ReaderView.swift
git commit -m "$(cat <<'EOF'
feat: add first-page and trash buttons to the toolbar

Both act on the open document. Delete goes through the same
confirmation dialog the sidebar uses, so ReaderView keeps a single
place that owns it. No keyboard shortcuts, to avoid colliding with the
existing bindings.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: READMEの更新

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: 主な特徴に1行足す**

`README.md` の「## 主な特徴」の最後の項目（`- 左側のディレクトリサイドバーからPDFを選んで開く（開閉可能）`）の直後に追加する。

```markdown
- シークバーによるページ移動、読書位置のリセット、PDFのゴミ箱移動
```

- [ ] **Step 2: 基本操作に説明を足す**

「## 基本操作」の箇条書きの最後（`- ディレクトリサイドバーの表示切り替え: ...` の行）の直後に追加する。

```markdown
- ページを大きく飛ばす: 本文の下端にマウスカーソルを近づけるとシークバーが現れます
- 最初に戻る: ツールバーの「最初に戻る」、またはサイドバーで右クリックして「最初に戻る」
- PDFを削除する: ツールバーのゴミ箱ボタン、またはサイドバーで右クリックして「ゴミ箱に入れる」
```

- [ ] **Step 3: サイドバーの段落の後に新しい段落を足す**

「サイドバーヘッダーには3つのボタンがあります。…」で始まる段落の直後に追加する。

```markdown
シークバーは本文の下端にマウスカーソルを近づけると現れ、離れると消えます。右綴じでは右端が1ページ目で、読み進むほどつまみが左へ動きます。つまみをゆっくり動かすとページが追従し、一気に振ったときは指を離した位置へ飛びます。

サイドバーではPDFを `Command` クリック・`Shift` クリックで複数選択できます。選択したPDFを右クリックすると「最初に戻る」（保存された読書位置を先頭に戻す）と「ゴミ箱に入れる」が選べます。削除はmacOSのゴミ箱へ移動するので、Finderから元に戻せます。フォルダは削除の対象になりません。
```

- [ ] **Step 4: 表示を確認する**

Run: `grep -n "シークバー\|ゴミ箱\|最初に戻る" README.md`
Expected: 追加した6箇所が出力される

- [ ] **Step 5: コミット**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs: document the seek bar, reset-to-first, and delete

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
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

`swift test` は着手前の135件から、本計画で追加した分だけ増えている（Task 1で6件、Task 2で5件、Task 3で3件、Task 4で2件、Task 6で6件の計22件増、合計157件）。
