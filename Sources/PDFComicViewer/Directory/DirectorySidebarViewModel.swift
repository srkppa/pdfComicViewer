import Foundation

@MainActor
final class DirectorySidebarViewModel: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var nodes: [DirectoryTreeNode] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// 各行に最終更新日を表示するかどうか。常時表示ではなく、ヘッダーのメニューから切り替える。
    @Published var showsModificationDate = false
    /// フォルダ一覧の並べ替え条件。フォルダは常に先頭にまとまる。
    @Published var sortOrder: DirectorySortOrder = .nameAscending

    /// `sortOrder` を適用した表示用のツリー。
    var sortedNodes: [DirectoryTreeNode] {
        nodes.sorted(by: sortOrder)
    }

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
}
