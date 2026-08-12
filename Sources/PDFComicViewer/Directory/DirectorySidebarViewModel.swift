import Foundation

@MainActor
final class DirectorySidebarViewModel: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var nodes: [DirectoryTreeNode] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// 各行に最終更新日を表示するかどうか。常時表示ではなく、ヘッダーのメニューから切り替える。
    @Published var showsModificationDate = false
    /// フォルダ一覧の並べ替えの基準。フォルダは常に先頭にまとまる。
    @Published var sortKey: DirectorySortKey = .name
    /// フォルダ一覧の並べ替えの向き。
    @Published var sortDirection: DirectorySortDirection = .ascending

    /// `sortKey` と `sortDirection` を適用した表示用のツリー。
    var sortedNodes: [DirectoryTreeNode] {
        nodes.sorted(by: sortKey, direction: sortDirection)
    }

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

    func setRoot(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard rootURL != normalized else { return }
        rootURL = normalized
        reload()
    }

    func reload() {
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

    /// 選択中のIDのうち、PDFのURLだけを返す。
    /// フォルダごとの削除は誤操作の影響が大きいため対象外にしている。
    func pdfURLs(for ids: Set<String>) -> [URL] {
        ids.compactMap { nodes.firstNode(withID: $0) }
            .filter { $0.kind == .pdf }
            .map(\.url)
    }

    /// 保存済みの読書位置を先頭に戻す。戻り値は失敗件数。
    /// 記録が無いPDFは元から先頭で「何もしない」だけなので失敗として数えない。
    /// 一方 load/save が例外を投げた場合はストアのI/O障害なので失敗として数える。
    /// 件数は `trash(urls:)` と同じ理由で `errorMessage` には入れない
    /// （`errorMessage` に入れるとツリー全体が差し替わって一覧が消えるため）。
    @discardableResult
    func resetProgress(for urls: [URL]) async -> Int {
        var failureCount = 0
        for url in urls {
            let record: DocumentRecord?
            do {
                record = try await progressStore.load(for: url)
            } catch {
                failureCount += 1
                continue
            }
            guard var record else { continue }
            record.preferences.lastPageIndex = 0
            do {
                try await progressStore.save(record)
            } catch {
                failureCount += 1
            }
        }
        return failureCount
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
}
