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
    /// ツールバーからも選択対象を参照するため、Viewの`@State`ではなくここで持つ。
    @Published var selectedNodeIDs: Set<String> = []
    /// 検索欄の入力。空ならフィルタなし。フォルダを切り替えたら空に戻す。
    @Published var searchQuery: String = ""

    /// `sortKey` と `sortDirection` を適用した表示用のツリー。
    var sortedNodes: [DirectoryTreeNode] {
        nodes.sorted(by: sortKey, direction: sortDirection)
    }

    /// 実際にサイドバーへ渡す表示用のツリー。
    ///
    /// 検索していないときは階層をそのまま見せる。検索中は階層を畳んで、
    /// 一致したPDFを一列に並べる——SwiftUIの`List(children:)`は折りたたみ
    /// 状態を外から開けないため、階層を保つと一致したPDFが閉じた三角の
    /// 中に隠れて見えないまま終わってしまうため。
    var displayedNodes: [DirectoryTreeNode] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nodes.sorted(by: sortKey, direction: sortDirection)
        }
        return nodes.flattenedPDFMatches(byQuery: trimmed)
            .sorted(by: sortKey, direction: sortDirection)
    }

    /// 手動の再読み込みを受け付けられるか。
    /// フォルダ未選択のときは走査対象が無く、スキャン中は連打しただけ
    /// 走査が積み上がるだけなので、どちらもボタンを無効にする。
    var canReload: Bool { rootURL != nil && !isLoading }

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
        searchQuery = ""
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

    /// 選択を指定のPDF1件だけに置き換える。
    ///
    /// ツールバーの操作は選択中のPDFを対象にするため、こちらが操作せずに
    /// 開いているPDFが変わったとき（最終ページからの自動遷移など）に
    /// 選択を追従させないと、操作が前のPDFに向かってしまう。
    func selectOnly(_ url: URL) {
        selectedNodeIDs = [url.standardizedFileURL.path]
    }

    /// 選択中のIDのうち、PDFのURLだけを返す。
    /// フォルダごとの削除は誤操作の影響が大きいため対象外にしている。
    func pdfURLs(for ids: Set<String>) -> [URL] {
        // idsはSetなので走査順が不定。削除確認ダイアログはこの結果から
        // 先頭数件だけを見せるため、順序をファイル名で固定しておく。
        ids.compactMap { nodes.firstNode(withID: $0) }
            .filter { $0.kind == .pdf }
            .map(\.url)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
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
        // ゴミ箱へ移動できたファイルはもう存在しないので選択から外す。
        // 失敗したファイルは操作をやり直せるよう選択状態を保つ。
        let trashedIDs = Set(
            urls.filter { !failures.contains($0) }.map { $0.standardizedFileURL.path }
        )
        selectedNodeIDs.subtract(trashedIDs)
        // 全件失敗しても再スキャンする。実際のファイル状態に一覧を追従させるため。
        reload()
        return failures.count
    }
}
