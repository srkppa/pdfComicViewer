import PDFKit
import XCTest
@testable import PDFComicViewer

@MainActor
final class ReaderViewModelTests: XCTestCase {
    func testReaderCommandRequestsAdvanceTheirSequences() {
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(.fixture(pageCount: 1))),
            progressStore: FakeProgressStore()
        )

        model.requestFileOpen()
        model.zoomIn()
        model.zoomOut()
        model.fitToWindow()
        model.requestFullScreenToggle()

        XCTAssertEqual(model.fileOpenRequestSequence, 1)
        XCTAssertEqual(model.zoomCommand, ZoomCommand(action: .fit, sequence: 3))
        XCTAssertEqual(model.fullScreenRequestSequence, 1)
    }

    func testTurningPageReturnsZoomToFit() async {
        let (model, _) = await makeOpenedModel(pageCount: 4)
        model.zoomIn()

        model.next()

        XCTAssertEqual(model.zoomCommand, ZoomCommand(action: .fit, sequence: 3))
    }

    func testOpeningAndRebuildingPresentationReturnZoomToFit() async {
        let (model, _) = await makeOpenedModel(pageCount: 6, lastPageIndex: 2)
        XCTAssertEqual(model.zoomCommand, ZoomCommand(action: .fit, sequence: 1))

        model.zoomIn()
        model.setDisplayMode(.single)
        XCTAssertEqual(model.zoomCommand, ZoomCommand(action: .fit, sequence: 3))

        model.zoomIn()
        model.toggleAlignment()
        XCTAssertEqual(model.zoomCommand, ZoomCommand(action: .fit, sequence: 5))

        model.zoomIn()
        model.setPageOverride(.single, for: 2)
        XCTAssertEqual(model.zoomCommand, ZoomCommand(action: .fit, sequence: 7))
    }

    func testActivatingAnotherDocumentReturnsZoomToFit() async {
        let first = DocumentSession.fixture(pageCount: 2)
        let secondURL = URL(fileURLWithPath: "/tmp/second-comic.pdf")
        let second = DocumentSession.fixture(pageCount: 2, url: secondURL)
        let loader = FakePDFLoader(result: .ready(first))
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())
        await model.open(url: first.url)
        model.zoomIn()
        loader.result = .ready(second)

        await model.open(url: secondURL)

        XCTAssertTrue(model.session === second)
        XCTAssertEqual(model.zoomCommand, ZoomCommand(action: .fit, sequence: 3))
    }

    func testOpeningAndTurningPagePublishCurrentPlacementPreviewSnapshot() async throws {
        let url = try PDFFixtureFactory.makePDF(pageSizes: Array(
            repeating: CGSize(width: 600, height: 900),
            count: 5
        ))
        defer { try? FileManager.default.removeItem(at: url) }
        let model = ReaderViewModel(
            loader: PDFDocumentLoader(),
            progressStore: FakeProgressStore()
        )

        await model.open(url: url)
        try await waitUntil {
            model.pagePreviewSnapshot.images[0] != nil
        }

        XCTAssertEqual(model.pagePreviewSnapshot.pageIndexes, [0])

        model.next()
        try await waitUntil {
            model.pagePreviewSnapshot.images[1] != nil
                && model.pagePreviewSnapshot.images[2] != nil
        }

        XCTAssertEqual(model.pagePreviewSnapshot.pageIndexes, [1, 2])
    }

    func testOpenBuildsSpreadsAndRestoresSavedPage() async {
        let session = DocumentSession.fixture(pageCount: 6)
        let loader = FakePDFLoader(result: .ready(session))
        let store = FakeProgressStore(
            record: .fixture(
                url: session.url,
                metadata: session.metadata,
                lastPageIndex: 4
            )
        )
        let model = ReaderViewModel(loader: loader, progressStore: store)

        await model.open(url: session.url)

        XCTAssertEqual(model.currentPhysicalPage, 4)
        XCTAssertEqual(model.currentUnit, .pair(3, 4))
    }

    func testChangingModeKeepsCurrentPhysicalPage() async {
        let session = DocumentSession.fixture(pageCount: 6)
        let loader = FakePDFLoader(result: .ready(session))
        let store = FakeProgressStore(
            record: .fixture(
                url: session.url,
                metadata: session.metadata,
                lastPageIndex: 2
            )
        )
        let model = ReaderViewModel(loader: loader, progressStore: store)
        await model.open(url: session.url)

        model.setDisplayMode(.single)

        XCTAssertEqual(model.currentPhysicalPage, 2)
        XCTAssertEqual(model.currentUnit, .single(2))
    }

    func testFailedOpenKeepsCurrentDocument() async {
        let readable = DocumentSession.fixture(pageCount: 4)
        let loader = FakePDFLoader(result: .ready(readable))
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())
        await model.open(url: readable.url)
        loader.error = PDFLoaderError.invalidPDF

        await model.open(url: URL(fileURLWithPath: "/tmp/broken.pdf"))

        XCTAssertTrue(model.session === readable)
        XCTAssertNotNil(model.errorMessage)
    }

    func testExternalFilePDFIsRoutedThroughDocumentLoader() async {
        let url = URL(fileURLWithPath: "/tmp/external-comic.PDF")
        let session = DocumentSession.fixture(pageCount: 3, url: url)
        let loader = FakePDFLoader(result: .ready(session))
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())

        let wasAccepted = await model.openExternalURL(url)

        XCTAssertTrue(wasAccepted)
        XCTAssertEqual(loader.openedURLs, [url])
        XCTAssertTrue(model.session === session)
    }

    func testExternalNonFileURLIsRejectedBeforeDocumentLoader() async {
        let url = URL(string: "https://example.com/comic.pdf")!
        let loader = FakePDFLoader(result: .ready(.fixture(pageCount: 1)))
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())

        let wasAccepted = await model.openExternalURL(url)

        XCTAssertFalse(wasAccepted)
        XCTAssertTrue(loader.openedURLs.isEmpty)
        XCTAssertNil(model.session)
        XCTAssertNotNil(model.errorMessage)
    }

    func testExternalNonPDFFileIsRejectedBeforeDocumentLoader() async {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        let loader = FakePDFLoader(result: .ready(.fixture(pageCount: 1)))
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())

        let wasAccepted = await model.openExternalURL(url)

        XCTAssertFalse(wasAccepted)
        XCTAssertTrue(loader.openedURLs.isEmpty)
        XCTAssertNil(model.session)
        XCTAssertNotNil(model.errorMessage)
    }

    func testPreviousAtFirstUnitStaysAtFirstPage() async {
        let (model, _) = await makeOpenedModel(pageCount: 4)

        model.previous()

        XCTAssertEqual(model.currentUnitIndex, 0)
        XCTAssertEqual(model.currentPhysicalPage, 0)
    }

    func testNextAtLastUnitStaysAtLastUnit() async {
        let (model, _) = await makeOpenedModel(pageCount: 4)
        model.next()
        model.next()

        model.next()

        XCTAssertEqual(model.currentUnitIndex, 2)
        XCTAssertEqual(model.currentUnit, .single(3))
        XCTAssertEqual(model.currentPhysicalPage, 3)
    }

    func testTogglingAlignmentKeepsCurrentPhysicalPage() async {
        let (model, _) = await makeOpenedModel(pageCount: 6, lastPageIndex: 2)

        model.toggleAlignment()

        XCTAssertEqual(model.preferences.alignment, .shifted)
        XCTAssertEqual(model.currentPhysicalPage, 2)
        XCTAssertEqual(model.currentUnit, .pair(2, 3))
    }

    func testPageOverrideRebuildsAroundCurrentPhysicalPage() async {
        let (model, _) = await makeOpenedModel(pageCount: 6, lastPageIndex: 2)

        model.setPageOverride(.single, for: 2)

        XCTAssertEqual(model.preferences.pageOverrides[2], .single)
        XCTAssertEqual(model.currentPhysicalPage, 2)
        XCTAssertEqual(model.currentUnit, .single(2))
    }

    func testSettingLeftBindingKeepsCurrentDisplayUnit() async {
        let (model, _) = await makeOpenedModel(pageCount: 6, lastPageIndex: 2)
        let originalUnit = model.currentUnit

        model.setBinding(.left)

        XCTAssertEqual(model.preferences.binding, .left)
        XCTAssertEqual(model.currentPhysicalPage, 2)
        XCTAssertEqual(model.currentUnit, originalUnit)
    }

    func testRapidChangesSaveOnlyLatestRecord() async throws {
        let url = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, store) = await makeOpenedModel(pageCount: 6, url: url)

        model.next()
        model.next()
        try await waitUntil { await store.savedRecords.count == 1 }

        let savedRecords = await store.savedRecords
        XCTAssertEqual(savedRecords.count, 1)
        XCTAssertEqual(savedRecords[0].preferences.lastPageIndex, 3)
        XCTAssertEqual(savedRecords[0].normalizedPath, url.standardizedFileURL.path)
    }

    func testSettingChangesSaveOnlyLatestPreferences() async throws {
        let url = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, store) = await makeOpenedModel(pageCount: 6, url: url)

        model.setDisplayMode(.single)
        model.toggleAlignment()
        model.setBinding(.left)
        model.setPageOverride(.single, for: 2)
        try await waitUntil { await store.savedRecords.count == 1 }

        let savedRecords = await store.savedRecords
        XCTAssertEqual(savedRecords.count, 1)
        XCTAssertEqual(savedRecords[0].preferences.displayMode, .single)
        XCTAssertEqual(savedRecords[0].preferences.alignment, .shifted)
        XCTAssertEqual(savedRecords[0].preferences.binding, .left)
        XCTAssertEqual(savedRecords[0].preferences.pageOverrides, [2: .single])
    }

    func testSuccessfulOpenFlushesPendingSaveForPreviousDocument() async throws {
        let firstURL = try makeTemporaryFileURL()
        let secondURL = try makeTemporaryFileURL()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let first = DocumentSession.fixture(pageCount: 4, url: firstURL)
        let second = DocumentSession.fixture(pageCount: 4, url: secondURL)
        let loader = FakePDFLoader(result: .ready(first))
        let store = FakeProgressStore(
            record: .fixture(url: firstURL, metadata: first.metadata)
        )
        let model = ReaderViewModel(loader: loader, progressStore: store)
        await model.open(url: firstURL)
        model.next()
        await store.setRecord(nil)
        loader.result = .ready(second)

        await model.open(url: secondURL)

        XCTAssertTrue(model.session === second)
        let savedRecords = await store.savedRecords
        XCTAssertEqual(savedRecords.count, 1)
        let savedRecord = try XCTUnwrap(savedRecords.first)
        XCTAssertEqual(savedRecord.normalizedPath, firstURL.standardizedFileURL.path)
        XCTAssertEqual(savedRecord.preferences.lastPageIndex, 1)
    }

    func testFailedSwitchSaveDoesNotBlockNewDocumentAndRetriesBothDocuments() async throws {
        let firstURL = try makeTemporaryFileURL()
        let secondURL = try makeTemporaryFileURL()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let first = DocumentSession.fixture(pageCount: 4, url: firstURL)
        let second = DocumentSession.fixture(pageCount: 4, url: secondURL)
        let loader = FakePDFLoader(result: .ready(first))
        let store = FakeProgressStore(
            record: .fixture(url: firstURL, metadata: first.metadata)
        )
        let model = ReaderViewModel(loader: loader, progressStore: store)
        await model.open(url: firstURL)
        model.next()
        await store.setSaveError(TestError.saveFailed)
        loader.result = .ready(second)

        await model.open(url: secondURL)

        XCTAssertTrue(model.session === second)
        XCTAssertNotNil(model.warningMessage)

        model.next()
        await store.setSaveError(nil)
        await model.flushPendingSaves()

        let savedRecords = await store.savedRecords
        XCTAssertEqual(Set(savedRecords.map(\.normalizedPath)), Set([
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ]))
        XCTAssertEqual(
            savedRecords.first { $0.normalizedPath == firstURL.standardizedFileURL.path }?
                .preferences.lastPageIndex,
            1
        )
        XCTAssertEqual(
            savedRecords.first { $0.normalizedPath == secondURL.standardizedFileURL.path }?
                .preferences.lastPageIndex,
            1
        )
    }

    func testOlderOpenCompletionCannotReplaceNewerDocument() async throws {
        let olderURL = URL(fileURLWithPath: "/tmp/older.pdf")
        let newerURL = URL(fileURLWithPath: "/tmp/newer.pdf")
        let older = DocumentSession.fixture(pageCount: 2, url: olderURL)
        let newer = DocumentSession.fixture(pageCount: 4, url: newerURL)
        let loader = FakePDFLoader(result: .ready(older))
        loader.resultsByURL = [olderURL: .ready(older), newerURL: .ready(newer)]
        loader.delaysByURL = [olderURL: .milliseconds(100)]
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())

        let olderOpen = Task { await model.open(url: olderURL) }
        try await Task.sleep(for: .milliseconds(10))
        await model.open(url: newerURL)
        await olderOpen.value

        XCTAssertTrue(model.session === newer)
        XCTAssertFalse(model.isLoading)
    }

    func testSaveFailureWarnsWithoutChangingReadingState() async throws {
        let url = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, store) = await makeOpenedModel(pageCount: 4, url: url)
        await store.setSaveError(TestError.saveFailed)

        model.next()
        try await waitUntil { model.warningMessage != nil }

        XCTAssertEqual(model.currentPhysicalPage, 1)
        XCTAssertEqual(model.currentUnit, .pair(1, 2))
        XCTAssertNotNil(model.warningMessage)
        let savedRecords = await store.savedRecords
        XCTAssertTrue(savedRecords.isEmpty)
    }

    func testUnlockActivatesDocumentAndRestoresProgress() async {
        let unlocked = DocumentSession.fixture(pageCount: 6)
        let locked = LockedPDFDocument.fixture(url: unlocked.url, metadata: unlocked.metadata)
        let loader = FakePDFLoader(result: .passwordRequired(locked))
        loader.unlockResult = unlocked
        let store = FakeProgressStore(
            record: .fixture(
                url: unlocked.url,
                metadata: unlocked.metadata,
                lastPageIndex: 4
            )
        )
        let model = ReaderViewModel(loader: loader, progressStore: store)
        await model.open(url: unlocked.url)

        await model.unlock(password: "secret")

        XCTAssertTrue(model.session === unlocked)
        XCTAssertNil(model.passwordRequest)
        XCTAssertEqual(model.currentPhysicalPage, 4)
        XCTAssertEqual(model.currentUnit, .pair(3, 4))
    }

    func testUnlockFailureKeepsPasswordRequestAndCurrentDocument() async {
        let current = DocumentSession.fixture(pageCount: 4)
        let lockedURL = URL(fileURLWithPath: "/tmp/locked.pdf")
        let locked = LockedPDFDocument.fixture(url: lockedURL)
        let loader = FakePDFLoader(result: .ready(current))
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())
        await model.open(url: current.url)
        loader.result = .passwordRequired(locked)
        await model.open(url: lockedURL)
        loader.unlockError = PDFLoaderError.incorrectPassword

        await model.unlock(password: "wrong")

        XCTAssertTrue(model.session === current)
        XCTAssertNotNil(model.passwordRequest)
        XCTAssertNotNil(model.errorMessage)
    }

    func testPasswordResultClearsOlderReplacementConfirmation() async throws {
        let replacementURL = try makeTemporaryFileURL()
        let lockedURL = try makeTemporaryFileURL()
        defer {
            try? FileManager.default.removeItem(at: replacementURL)
            try? FileManager.default.removeItem(at: lockedURL)
        }
        let replacement = DocumentSession.fixture(
            pageCount: 2,
            url: replacementURL,
            metadata: FileMetadata(size: 2_048, modificationDate: .fixtureDate)
        )
        let locked = LockedPDFDocument.fixture(url: lockedURL)
        let loader = FakePDFLoader(result: .ready(replacement))
        let store = FakeProgressStore(
            record: .fixture(url: replacementURL, metadata: .fixture)
        )
        let model = ReaderViewModel(loader: loader, progressStore: store)
        await model.open(url: replacementURL)
        XCTAssertNotNil(model.replacementConfirmation)
        loader.result = .passwordRequired(locked)

        await model.open(url: lockedURL)

        XCTAssertNil(model.replacementConfirmation)
        XCTAssertEqual(model.passwordRequest?.url, lockedURL)
        await model.confirmReplacement(keepPreferences: true)
        XCTAssertNil(model.session)
    }

    func testReplacementResultClearsOlderPasswordRequest() async throws {
        let lockedURL = try makeTemporaryFileURL()
        let replacementURL = try makeTemporaryFileURL()
        defer {
            try? FileManager.default.removeItem(at: lockedURL)
            try? FileManager.default.removeItem(at: replacementURL)
        }
        let locked = LockedPDFDocument.fixture(url: lockedURL)
        let unlocked = DocumentSession.fixture(pageCount: 2, url: lockedURL)
        let replacement = DocumentSession.fixture(
            pageCount: 4,
            url: replacementURL,
            metadata: FileMetadata(size: 2_048, modificationDate: .fixtureDate)
        )
        let loader = FakePDFLoader(result: .passwordRequired(locked))
        loader.unlockResult = unlocked
        let store = FakeProgressStore()
        let model = ReaderViewModel(loader: loader, progressStore: store)
        await model.open(url: lockedURL)
        XCTAssertNotNil(model.passwordRequest)
        await store.setRecord(.fixture(url: replacementURL, metadata: .fixture))
        loader.result = .ready(replacement)

        await model.open(url: replacementURL)

        XCTAssertNil(model.passwordRequest)
        XCTAssertTrue(model.replacementConfirmation?.session === replacement)
        await model.unlock(password: "stale")
        XCTAssertNil(model.session)
    }

    func testCancelUnlockKeepsCurrentDocument() async {
        let current = DocumentSession.fixture(pageCount: 4)
        let lockedURL = URL(fileURLWithPath: "/tmp/locked.pdf")
        let locked = LockedPDFDocument.fixture(url: lockedURL)
        let loader = FakePDFLoader(result: .ready(current))
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())
        await model.open(url: current.url)
        loader.result = .passwordRequired(locked)
        await model.open(url: lockedURL)

        model.cancelUnlock()

        XCTAssertTrue(model.session === current)
        XCTAssertNil(model.passwordRequest)
    }

    func testUnlockDuringOpenEventuallyClearsLoading() async throws {
        let lockedURL = URL(fileURLWithPath: "/tmp/unlock-loading.pdf")
        let slowURL = URL(fileURLWithPath: "/tmp/slow-after-unlock.pdf")
        let locked = LockedPDFDocument.fixture(url: lockedURL)
        let unlocked = DocumentSession.fixture(pageCount: 2, url: lockedURL)
        let slow = DocumentSession.fixture(pageCount: 2, url: slowURL)
        let loader = FakePDFLoader(result: .passwordRequired(locked))
        loader.unlockResult = unlocked
        loader.resultsByURL[slowURL] = .ready(slow)
        loader.delaysByURL[slowURL] = .milliseconds(100)
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())
        await model.open(url: lockedURL)

        let slowOpen = Task { await model.open(url: slowURL) }
        try await waitUntil { model.isLoading }
        await model.unlock(password: "secret")
        await slowOpen.value

        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.session === unlocked)
    }

    func testCancelUnlockDuringOpenEventuallyClearsLoading() async throws {
        let lockedURL = URL(fileURLWithPath: "/tmp/cancel-loading.pdf")
        let slowURL = URL(fileURLWithPath: "/tmp/slow-after-cancel.pdf")
        let locked = LockedPDFDocument.fixture(url: lockedURL)
        let slow = DocumentSession.fixture(pageCount: 2, url: slowURL)
        let loader = FakePDFLoader(result: .passwordRequired(locked))
        loader.resultsByURL[slowURL] = .ready(slow)
        loader.delaysByURL[slowURL] = .milliseconds(100)
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())
        await model.open(url: lockedURL)

        let slowOpen = Task { await model.open(url: slowURL) }
        try await waitUntil { model.isLoading }
        model.cancelUnlock()
        await slowOpen.value

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.passwordRequest)
        XCTAssertNil(model.session)
    }

    func testConfirmReplacementDuringOpenEventuallyClearsLoading() async throws {
        let replacementURL = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: replacementURL) }
        let slowURL = URL(fileURLWithPath: "/tmp/slow-after-confirm.pdf")
        let replacement = DocumentSession.fixture(
            pageCount: 2,
            url: replacementURL,
            metadata: FileMetadata(size: 2_048, modificationDate: .fixtureDate)
        )
        let slow = DocumentSession.fixture(pageCount: 2, url: slowURL)
        let loader = FakePDFLoader(result: .ready(replacement))
        loader.resultsByURL[slowURL] = .ready(slow)
        loader.delaysByURL[slowURL] = .milliseconds(100)
        let store = FakeProgressStore(
            record: .fixture(url: replacementURL, metadata: .fixture)
        )
        let model = ReaderViewModel(loader: loader, progressStore: store)
        await model.open(url: replacementURL)

        let slowOpen = Task { await model.open(url: slowURL) }
        try await waitUntil { model.isLoading }
        await model.confirmReplacement(keepPreferences: true)
        await slowOpen.value

        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.session === replacement)
    }

    func testMetadataSizeMismatchDefersReplacementAndKeepsCurrentDocument() async throws {
        let replacementURL = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: replacementURL) }
        let current = DocumentSession.fixture(pageCount: 2)
        let replacement = DocumentSession.fixture(
            pageCount: 6,
            url: replacementURL,
            metadata: FileMetadata(size: 2_048, modificationDate: .fixtureDate)
        )
        let loader = FakePDFLoader(result: .ready(current))
        let store = FakeProgressStore()
        let model = ReaderViewModel(loader: loader, progressStore: store)
        await model.open(url: current.url)
        await store.setRecord(
            .fixture(
                url: replacementURL,
                metadata: FileMetadata(size: 1_024, modificationDate: .fixtureDate),
                lastPageIndex: 4
            )
        )
        loader.result = .ready(replacement)

        await model.open(url: replacementURL)

        XCTAssertTrue(model.session === current)
        XCTAssertTrue(model.replacementConfirmation?.session === replacement)
    }

    func testMetadataDateMismatchDefersReplacement() async throws {
        let replacementURL = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: replacementURL) }
        let replacement = DocumentSession.fixture(
            pageCount: 2,
            url: replacementURL,
            metadata: FileMetadata(size: 1_024, modificationDate: .fixtureDate.addingTimeInterval(60))
        )
        let record = DocumentRecord.fixture(
            url: replacementURL,
            metadata: .fixture
        )
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(replacement)),
            progressStore: FakeProgressStore(record: record)
        )

        await model.open(url: replacementURL)

        XCTAssertNil(model.session)
        XCTAssertNotNil(model.replacementConfirmation)
    }

    func testConfirmReplacementKeepsSavedPreferencesAndUpdatesFileIdentity() async throws {
        let replacementURL = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: replacementURL) }
        let oldMetadata = FileMetadata(size: 1_024, modificationDate: .fixtureDate)
        let newMetadata = FileMetadata(size: 2_048, modificationDate: .fixtureDate)
        let replacement = DocumentSession.fixture(
            pageCount: 6,
            url: replacementURL,
            metadata: newMetadata
        )
        var savedPreferences = DocumentPreferences.defaults
        savedPreferences.lastPageIndex = 4
        savedPreferences.binding = .left
        savedPreferences.displayMode = .single
        let store = FakeProgressStore(
            record: .fixture(
                url: replacementURL,
                metadata: oldMetadata,
                preferences: savedPreferences
            )
        )
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(replacement)),
            progressStore: store
        )
        await model.open(url: replacementURL)

        await model.confirmReplacement(keepPreferences: true)
        try await waitUntil { await store.savedRecords.count == 1 }

        XCTAssertTrue(model.session === replacement)
        XCTAssertEqual(model.preferences, savedPreferences)
        XCTAssertEqual(model.currentUnit, .single(4))
        let savedRecords = await store.savedRecords
        let saved = try XCTUnwrap(savedRecords.last)
        XCTAssertEqual(saved.metadata, newMetadata)
        XCTAssertEqual(saved.normalizedPath, replacementURL.standardizedFileURL.path)
        XCTAssertFalse(saved.bookmarkData.isEmpty)
    }

    func testConfirmReplacementDiscardsSavedPreferences() async throws {
        let replacementURL = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: replacementURL) }
        let replacement = DocumentSession.fixture(
            pageCount: 6,
            url: replacementURL,
            metadata: FileMetadata(size: 2_048, modificationDate: .fixtureDate)
        )
        var savedPreferences = DocumentPreferences.defaults
        savedPreferences.lastPageIndex = 4
        savedPreferences.binding = .left
        let store = FakeProgressStore(
            record: .fixture(
                url: replacementURL,
                metadata: .fixture,
                preferences: savedPreferences
            )
        )
        let model = ReaderViewModel(
            loader: FakePDFLoader(result: .ready(replacement)),
            progressStore: store
        )
        await model.open(url: replacementURL)

        await model.confirmReplacement(keepPreferences: false)
        try await waitUntil { await store.savedRecords.count == 1 }

        XCTAssertTrue(model.session === replacement)
        XCTAssertEqual(model.preferences, .defaults)
        XCTAssertEqual(model.currentPhysicalPage, 0)
        let savedRecords = await store.savedRecords
        let saved = try XCTUnwrap(savedRecords.last)
        XCTAssertEqual(saved.preferences, .defaults)
        XCTAssertEqual(saved.metadata, replacement.metadata)
    }

    private func makeOpenedModel(
        pageCount: Int,
        url: URL = URL(fileURLWithPath: "/tmp/comic.pdf"),
        lastPageIndex: Int = 0
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
            progressStore: store
        )
        await model.open(url: url)
        return (model, store)
    }

    private func makeTemporaryFileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ReaderViewModelTests-\(UUID().uuidString).pdf")
        try Data("fixture".utf8).write(to: url)
        return url
    }

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

    func testClosingDocumentDuringInFlightOpenPreventsStaleActivation() async throws {
        let firstURL = try makeTemporaryFileURL()
        let secondURL = try makeTemporaryFileURL()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let first = DocumentSession.fixture(pageCount: 2, url: firstURL)
        let second = DocumentSession.fixture(pageCount: 2, url: secondURL)
        let loader = FakePDFLoader(result: .ready(first))
        loader.resultsByURL = [firstURL: .ready(first), secondURL: .ready(second)]
        loader.delaysByURL = [secondURL: .milliseconds(100)]
        let model = ReaderViewModel(loader: loader, progressStore: FakeProgressStore())
        await model.open(url: firstURL)

        let secondOpen = Task { await model.open(url: secondURL) }
        try await Task.sleep(for: .milliseconds(10))
        await model.closeDocument()
        await secondOpen.value

        XCTAssertNil(model.session)
    }

    func testCloseDocumentPreservesSaveFailureWarning() async throws {
        let url = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, store) = await makeOpenedModel(pageCount: 4, url: url)
        model.next()
        await store.setSaveError(TestError.saveFailed)

        await model.closeDocument()

        XCTAssertNotNil(model.warningMessage)
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
}

@MainActor
private final class FakePDFLoader: PDFDocumentLoading {
    var result: PDFOpenResult
    var error: Error?
    var unlockResult: DocumentSession?
    var unlockError: Error?
    var resultsByURL: [URL: PDFOpenResult] = [:]
    var delaysByURL: [URL: Duration] = [:]
    private(set) var openedURLs: [URL] = []
    private(set) var unlockedPasswords: [String] = []

    init(result: PDFOpenResult) {
        self.result = result
    }

    func open(url: URL) async throws -> PDFOpenResult {
        openedURLs.append(url)
        if let error { throw error }
        let selectedResult = resultsByURL[url] ?? result
        if let delay = delaysByURL[url] {
            try await Task.sleep(for: delay)
        }
        return selectedResult
    }

    func unlock(
        _ locked: LockedPDFDocument,
        password: String
    ) async throws -> DocumentSession {
        unlockedPasswords.append(password)
        if let unlockError { throw unlockError }
        guard let unlockResult else { throw PDFLoaderError.incorrectPassword }
        return unlockResult
    }
}

private actor FakeProgressStore: ReadingProgressStoring {
    var record: DocumentRecord?
    var savedRecords: [DocumentRecord] = []
    var loadedURLs: [URL] = []
    var loadError: Error?
    var saveError: Error?

    init(record: DocumentRecord? = nil) {
        self.record = record
    }

    func load(for url: URL) throws -> DocumentRecord? {
        loadedURLs.append(url)
        if let loadError { throw loadError }
        guard record?.normalizedPath == url.standardizedFileURL.path else { return nil }
        return record
    }

    func save(_ record: DocumentRecord) throws {
        if let saveError { throw saveError }
        savedRecords.append(record)
        self.record = record
    }

    func allRecords() throws -> [DocumentRecord] {
        record.map { [$0] } ?? []
    }

    var removedURLs: [URL] = []

    func remove(for url: URL) throws {
        removedURLs.append(url)
        guard record?.normalizedPath == url.standardizedFileURL.path else { return }
        record = nil
    }

    func setRecord(_ record: DocumentRecord?) {
        self.record = record
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }
}

@MainActor
private extension DocumentSession {
    static func fixture(
        pageCount: Int,
        url: URL = URL(fileURLWithPath: "/tmp/comic.pdf"),
        metadata: FileMetadata = .fixture
    ) -> DocumentSession {
        DocumentSession(
            document: PDFDocument(),
            url: url,
            pages: Array(
                repeating: PageGeometry(width: 600, height: 900),
                count: pageCount
            ),
            metadata: metadata
        )
    }
}

private extension DocumentRecord {
    static func fixture(
        url: URL,
        metadata: FileMetadata = .fixture,
        lastPageIndex: Int = 0
    ) -> DocumentRecord {
        var preferences = DocumentPreferences.defaults
        preferences.lastPageIndex = lastPageIndex
        return DocumentRecord(
            bookmarkData: Data("bookmark".utf8),
            normalizedPath: url.standardizedFileURL.path,
            metadata: metadata,
            preferences: preferences
        )
    }

    static func fixture(
        url: URL,
        metadata: FileMetadata,
        preferences: DocumentPreferences
    ) -> DocumentRecord {
        DocumentRecord(
            bookmarkData: Data("bookmark".utf8),
            normalizedPath: url.standardizedFileURL.path,
            metadata: metadata,
            preferences: preferences
        )
    }
}

private extension FileMetadata {
    static let fixture = FileMetadata(
        size: 1_024,
        modificationDate: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private extension Date {
    static let fixtureDate = Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
private extension LockedPDFDocument {
    static func fixture(
        url: URL,
        metadata: FileMetadata = .fixture
    ) -> LockedPDFDocument {
        LockedPDFDocument(data: Data(), url: url, metadata: metadata)
    }
}

private enum TestError: Error {
    case saveFailed
}
