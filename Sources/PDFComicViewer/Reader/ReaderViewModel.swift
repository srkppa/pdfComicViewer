import Foundation
import SwiftUI

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
    @Published private(set) var fileOpenRequestSequence = 0
    @Published private(set) var zoomCommand = ZoomCommand(action: .fit, sequence: 0)
    @Published private(set) var fullScreenRequestSequence = 0
    @Published private(set) var pagePreviewSnapshot = PagePreviewSnapshot.empty

    private let loader: any PDFDocumentLoading
    private let progressStore: any ReadingProgressStoring
    private let pagePreviewCache = PagePreviewCache()
    private var saveTask: Task<Void, Never>?
    private var pagePreviewTask: Task<Void, Never>?
    private var pendingSave: (generation: Int, record: DocumentRecord)?
    private var saveGeneration = 0
    private var loadGeneration = 0
    private var openGeneration = 0
    private var pagePreviewGeneration = 0
    private var pagePreviewDocumentID = UUID()
    private var pagePreviewSnapshotRevision = 0

    init(loader: any PDFDocumentLoading, progressStore: any ReadingProgressStoring) {
        self.loader = loader
        self.progressStore = progressStore
    }

    static func live(fileManager: FileManager = .default) -> ReaderViewModel {
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return ReaderViewModel(
            loader: PDFDocumentLoader(),
            progressStore: FileReadingProgressStore(
                fileURL: progressFileURL(applicationSupportDirectory: supportDirectory)
            )
        )
    }

    static func progressFileURL(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("com.srkppa.PDFComicViewer", isDirectory: true)
            .appendingPathComponent("reading-progress.json")
    }

    var currentUnit: DisplayUnit? {
        guard displayUnits.indices.contains(currentUnitIndex) else { return nil }
        return displayUnits[currentUnitIndex]
    }

    func requestFileOpen() {
        fileOpenRequestSequence += 1
    }

    func zoomIn() {
        issueZoom(.zoomIn)
    }

    func zoomOut() {
        issueZoom(.zoomOut)
    }

    func fitToWindow() {
        issueZoom(.fit)
    }

    func requestFullScreenToggle() {
        fullScreenRequestSequence += 1
    }

    func open(url: URL) async {
        loadGeneration += 1
        let generation = loadGeneration
        openGeneration += 1
        let openToken = openGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if openToken == openGeneration {
                isLoading = false
            }
        }

        do {
            let result = try await loader.open(url: url)
            guard generation == loadGeneration else { return }
            switch result {
            case .ready(let newSession):
                try await receive(newSession, generation: generation)
            case .passwordRequired(let locked):
                replacementConfirmation = nil
                passwordRequest = locked
            }
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func unlock(password: String) async {
        guard let locked = passwordRequest else { return }
        loadGeneration += 1
        let generation = loadGeneration
        errorMessage = nil

        do {
            let unlockedSession = try loader.unlock(locked, password: password)
            try await receive(unlockedSession, generation: generation)
            guard generation == loadGeneration else { return }
            passwordRequest = nil
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func cancelUnlock() {
        loadGeneration += 1
        passwordRequest = nil
        errorMessage = nil
    }

    func next() {
        guard !displayUnits.isEmpty else { return }
        let nextIndex = min(currentUnitIndex + 1, displayUnits.count - 1)
        guard nextIndex != currentUnitIndex else { return }
        currentUnitIndex = nextIndex
        updateCurrentPageFromUnit()
        schedulePagePreviews()
        fitToWindow()
        scheduleSave()
    }

    func previous() {
        guard !displayUnits.isEmpty else { return }
        let previousIndex = max(currentUnitIndex - 1, 0)
        guard previousIndex != currentUnitIndex else { return }
        currentUnitIndex = previousIndex
        updateCurrentPageFromUnit()
        schedulePagePreviews()
        fitToWindow()
        scheduleSave()
    }

    func setDisplayMode(_ mode: DisplayMode) {
        guard preferences.displayMode != mode else { return }
        preferences.displayMode = mode
        rebuildKeepingCurrentPage()
        scheduleSave()
    }

    func toggleAlignment() {
        preferences.alignment = preferences.alignment == .coverSingle
            ? .shifted
            : .coverSingle
        rebuildKeepingCurrentPage()
        scheduleSave()
    }

    func setBinding(_ binding: BindingDirection) {
        guard preferences.binding != binding else { return }
        preferences.binding = binding
        scheduleSave()
    }

    func setPageOverride(_ override: PageLayoutOverride, for pageIndex: Int) {
        guard let session, session.pages.indices.contains(pageIndex) else { return }
        preferences.pageOverrides[pageIndex] = override
        rebuildKeepingCurrentPage()
        scheduleSave()
    }

    func confirmReplacement(keepPreferences: Bool) async {
        guard let confirmation = replacementConfirmation else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let newPreferences = keepPreferences
            ? confirmation.record.preferences
            : .defaults
        guard await flushPendingSave() else { return }
        guard generation == loadGeneration else { return }
        activate(confirmation.session, preferences: newPreferences)
        scheduleSave()
    }

    private func receive(_ newSession: DocumentSession, generation: Int) async throws {
        let record = try await progressStore.load(for: newSession.url)
        guard generation == loadGeneration else { return }
        if let record, record.metadata != newSession.metadata {
            passwordRequest = nil
            replacementConfirmation = ReplacementConfirmation(
                record: record,
                session: newSession
            )
            return
        }
        guard await flushPendingSave() else { return }
        guard generation == loadGeneration else { return }
        activate(newSession, preferences: record?.preferences ?? .defaults)
    }

    private func activate(
        _ newSession: DocumentSession,
        preferences newPreferences: DocumentPreferences
    ) {
        pagePreviewDocumentID = UUID()
        pagePreviewSnapshot = .empty
        let page = clampedPage(newPreferences.lastPageIndex, in: newSession.pages)
        session = newSession
        passwordRequest = nil
        replacementConfirmation = nil
        preferences = newPreferences
        preferences.lastPageIndex = page
        currentPhysicalPage = page
        displayUnits = SpreadBuilder.build(
            pages: newSession.pages,
            mode: preferences.displayMode,
            alignment: preferences.alignment,
            overrides: preferences.pageOverrides
        )
        currentUnitIndex = SpreadPresentation.unitIndex(
            containing: page,
            in: displayUnits
        ) ?? 0
        schedulePagePreviews()
    }

    private func updateCurrentPageFromUnit() {
        currentPhysicalPage = currentUnit?.anchorPage ?? 0
        preferences.lastPageIndex = currentPhysicalPage
    }

    private func rebuildKeepingCurrentPage() {
        guard let session else {
            displayUnits = []
            currentUnitIndex = 0
            currentPhysicalPage = 0
            schedulePagePreviews()
            return
        }
        let page = clampedPage(currentPhysicalPage, in: session.pages)
        displayUnits = SpreadBuilder.build(
            pages: session.pages,
            mode: preferences.displayMode,
            alignment: preferences.alignment,
            overrides: preferences.pageOverrides
        )
        currentPhysicalPage = page
        preferences.lastPageIndex = page
        currentUnitIndex = SpreadPresentation.unitIndex(
            containing: page,
            in: displayUnits
        ) ?? 0
        schedulePagePreviews()
    }

    private func schedulePagePreviews() {
        pagePreviewTask?.cancel()
        pagePreviewGeneration += 1
        let generation = PagePreviewGeneration(
            documentID: pagePreviewDocumentID,
            sequence: pagePreviewGeneration
        )
        let retainedIndexes = previewPageIndexes()
        let visibleIndexes = Set(currentUnit?.pageIndexes ?? [])
        let cache = pagePreviewCache
        pagePreviewTask = Task { [weak self] in
            guard let self else { return }
            await cache.beginGeneration(generation, allowedIndexes: retainedIndexes)

            guard !Task.isCancelled,
                  generation == self.currentPagePreviewGeneration,
                  let session = self.session else {
                return
            }
            await self.publishPagePreviewSnapshot(
                for: generation,
                visibleIndexes: visibleIndexes,
                cache: cache
            )

            for pageIndex in retainedIndexes {
                guard !Task.isCancelled,
                      generation == self.currentPagePreviewGeneration else {
                    return
                }
                if await cache.image(for: pageIndex, generation: generation) != nil {
                    continue
                }
                guard let page = session.document.page(at: pageIndex),
                      let image = PagePreviewRenderer.render(
                          page: page,
                          maxSize: CGSize(width: 1_024, height: 1_024)
                      ) else {
                    continue
                }
                guard !Task.isCancelled,
                      generation == self.currentPagePreviewGeneration else {
                    return
                }
                let wasInserted = await cache.insert(
                    image,
                    for: pageIndex,
                    generation: generation
                )
                guard wasInserted else { return }
                await self.publishPagePreviewSnapshot(
                    for: generation,
                    visibleIndexes: visibleIndexes,
                    cache: cache
                )
            }
        }
    }

    private var currentPagePreviewGeneration: PagePreviewGeneration {
        PagePreviewGeneration(
            documentID: pagePreviewDocumentID,
            sequence: pagePreviewGeneration
        )
    }

    private func publishPagePreviewSnapshot(
        for generation: PagePreviewGeneration,
        visibleIndexes: Set<Int>,
        cache: PagePreviewCache
    ) async {
        let images = await cache.snapshot(for: visibleIndexes, generation: generation)
        guard generation == currentPagePreviewGeneration else { return }
        pagePreviewSnapshotRevision += 1
        pagePreviewSnapshot = PagePreviewSnapshot(
            generation: generation,
            revision: pagePreviewSnapshotRevision,
            images: images
        )
    }

    private func previewPageIndexes() -> Set<Int> {
        guard !displayUnits.isEmpty else { return [] }
        let firstIndex = max(currentUnitIndex - 1, 0)
        let lastIndex = min(currentUnitIndex + 1, displayUnits.count - 1)
        return Set(displayUnits[firstIndex...lastIndex].flatMap(\.pageIndexes))
    }

    private func clampedPage(_ page: Int, in pages: [PageGeometry]) -> Int {
        guard !pages.isEmpty else { return 0 }
        return min(max(page, 0), pages.count - 1)
    }

    private func issueZoom(_ action: ZoomCommand.Action) {
        zoomCommand = ZoomCommand(action: action, sequence: zoomCommand.sequence + 1)
    }

    private func scheduleSave() {
        do {
            guard let record = try currentRecord() else { return }
            saveTask?.cancel()
            saveGeneration += 1
            let generation = saveGeneration
            pendingSave = (generation, record)
            saveTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    try Task.checkCancellation()
                    await self?.persistPendingSave(generation: generation)
                } catch is CancellationError {
                    return
                } catch {
                    self?.warningMessage = "閲覧状態を保存できませんでした。"
                }
            }
        } catch {
            warningMessage = "閲覧状態を保存できませんでした。"
        }
    }

    private func currentRecord() throws -> DocumentRecord? {
        guard let session else { return nil }
        return DocumentRecord(
            bookmarkData: try DocumentBookmarkService.makeBookmark(for: session.url),
            normalizedPath: session.url.standardizedFileURL.path,
            metadata: session.metadata,
            preferences: preferences
        )
    }

    private func persistPendingSave(generation: Int) async {
        guard let pendingSave, pendingSave.generation == generation else { return }
        saveTask = nil
        let didSave = await persist(pendingSave.record)
        if didSave, self.pendingSave?.generation == generation {
            self.pendingSave = nil
        }
    }

    private func flushPendingSave() async -> Bool {
        guard let pendingSave else { return true }
        saveTask?.cancel()
        saveTask = nil
        saveGeneration += 1
        let didSave = await persist(pendingSave.record)
        if didSave, self.pendingSave?.generation == pendingSave.generation {
            self.pendingSave = nil
        }
        return didSave
    }

    private func persist(_ record: DocumentRecord) async -> Bool {
        do {
            try await progressStore.save(record)
            warningMessage = nil
            return true
        } catch is CancellationError {
            warningMessage = "閲覧状態を保存できませんでした。"
            return false
        } catch {
            warningMessage = "閲覧状態を保存できませんでした。"
            return false
        }
    }
}
