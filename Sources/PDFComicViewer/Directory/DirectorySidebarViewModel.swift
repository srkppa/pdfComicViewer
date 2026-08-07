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
