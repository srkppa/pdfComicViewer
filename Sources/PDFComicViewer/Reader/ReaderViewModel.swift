import Foundation
import SwiftUI

@MainActor
struct ReplacementConfirmation {
    let record: DocumentRecord
    let session: DocumentSession
}

@MainActor
final class ReaderViewModel: ObservableObject {
    /// 保存失敗の警告文言。`persistDirtyRecords` が終了時に
    /// 自分の警告だけを片付けられるよう、比較用に文言を1箇所へ集約する。
    private static let saveFailureWarning = "閲覧状態を保存できませんでした。"
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
    /// 起動直後からフォルダペインを見せておくため、既定で表示状態にする。
    @Published var sidebarIsVisible = true

    private let loader: any PDFDocumentLoading
    private let progressStore: any ReadingProgressStoring
    private let seriesNavigator: any SeriesNavigating
    private let pagePreviewCache = PagePreviewCache()
    private var nextVolumeTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var pagePreviewTask: Task<Void, Never>?
    private var dirtyRecords: [String: (generation: Int, record: DocumentRecord)] = [:]
    private var saveGeneration = 0
    private var loadGeneration = 0
    private var openGeneration = 0
    private var pagePreviewGeneration = 0
    private var pagePreviewDocumentID = UUID()
    private var pagePreviewSnapshotRevision = 0

    init(
        loader: any PDFDocumentLoading,
        progressStore: any ReadingProgressStoring,
        seriesNavigator: any SeriesNavigating = SeriesNavigator()
    ) {
        self.loader = loader
        self.progressStore = progressStore
        self.seriesNavigator = seriesNavigator
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

    @discardableResult
    func openExternalURL(_ url: URL) async -> Bool {
        guard url.isFileURL,
              url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame else {
            errorMessage = "PDFファイルを開いてください。"
            return false
        }
        await open(url: url)
        return true
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
            let unlockedSession = try await loader.unlock(locked, password: password)
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
    private func advanceToNextVolumeIfPossible() {
        guard nextVolumeTask == nil, let session else { return }
        nextVolumeTask = Task { [weak self] in
            defer { self?.nextVolumeTask = nil }
            guard let self,
                  let nextURL = await self.seriesNavigator.nextVolumeURL(after: session.url) else {
                return
            }
            await self.open(url: nextURL)
        }
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
        fitToWindow()
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
        await persistDirtyRecords()
        guard generation == loadGeneration else { return }
        activate(confirmation.session, preferences: newPreferences)
        scheduleSave()
    }

    func closeDocument() async {
        guard session != nil else { return }
        loadGeneration += 1
        errorMessage = nil
        warningMessage = nil
        await flushPendingSaves()
        session = nil
        passwordRequest = nil
        replacementConfirmation = nil
        pagePreviewTask?.cancel()
        pagePreviewDocumentID = UUID()
        pagePreviewSnapshot = .empty
        rebuildKeepingCurrentPage()
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
        await persistDirtyRecords()
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
        fitToWindow()
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
        fitToWindow()
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
            dirtyRecords[record.normalizedPath] = (generation, record)
            saveTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    try Task.checkCancellation()
                    guard let self, generation == self.saveGeneration else { return }
                    self.saveTask = nil
                    await self.persistDirtyRecords()
                } catch is CancellationError {
                    return
                } catch {
                    self?.warningMessage = Self.saveFailureWarning
                }
            }
        } catch {
            warningMessage = Self.saveFailureWarning
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

    func flushPendingSaves() async {
        saveTask?.cancel()
        saveTask = nil
        do {
            if let record = try currentRecord() {
                saveGeneration += 1
                dirtyRecords[record.normalizedPath] = (saveGeneration, record)
            }
        } catch {
            warningMessage = Self.saveFailureWarning
        }
        await persistDirtyRecords()
    }

    private func persistDirtyRecords() async {
        guard !dirtyRecords.isEmpty else { return }
        var failed = false
        let records = dirtyRecords.values.sorted {
            $0.generation < $1.generation
        }
        for pending in records {
            do {
                try await progressStore.save(pending.record)
                if dirtyRecords[pending.record.normalizedPath]?.generation == pending.generation {
                    dirtyRecords[pending.record.normalizedPath] = nil
                }
            } catch {
                failed = true
            }
        }
        // 削除やリセットが自分の警告を出している最中に、保存成功で
        // それを消してしまわないよう、自分が出した警告だけを片付ける。
        if failed {
            warningMessage = Self.saveFailureWarning
        } else if warningMessage == Self.saveFailureWarning {
            warningMessage = nil
        }
    }
}
