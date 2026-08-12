import Foundation

struct DirectoryTreeNode: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case folder
        case pdf
    }

    let id: String
    let url: URL
    let name: String
    let kind: Kind
    /// ファイルシステム上の最終更新日時。取得できなかった場合は`nil`。
    let modificationDate: Date?
    var children: [DirectoryTreeNode]?

    init(
        url: URL,
        kind: Kind,
        modificationDate: Date? = nil,
        children: [DirectoryTreeNode]? = nil
    ) {
        self.id = url.standardizedFileURL.path
        self.url = url
        self.name = url.lastPathComponent
        self.kind = kind
        self.modificationDate = modificationDate
        self.children = children
    }
}

/// フォルダ一覧の並べ替え条件。
enum DirectorySortOrder: String, CaseIterable, Equatable, Sendable {
    case nameAscending
    case nameDescending
    case modificationDateAscending
    case modificationDateDescending
}

extension [DirectoryTreeNode] {
    /// ツリーを深さ優先で探索し、`id` が一致する最初のノードを返す。
    func firstNode(withID id: String) -> DirectoryTreeNode? {
        for node in self {
            if node.id == id { return node }
            if let match = node.children?.firstNode(withID: id) {
                return match
            }
        }
        return nil
    }

    /// フォルダを先頭に保ったまま、各階層を指定した条件で並べ替えたコピーを返す。
    func sorted(by order: DirectorySortOrder) -> [DirectoryTreeNode] {
        let folders = filter { $0.kind == .folder }.sortedByOrder(order)
        let files = filter { $0.kind == .pdf }.sortedByOrder(order)
        return (folders + files).map { node in
            var node = node
            node.children = node.children?.sorted(by: order)
            return node
        }
    }

    private func sortedByOrder(_ order: DirectorySortOrder) -> [DirectoryTreeNode] {
        switch order {
        case .nameAscending:
            return sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDescending:
            return sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .modificationDateAscending:
            return sorted { lhs, rhs in
                (lhs.modificationDate ?? .distantPast) < (rhs.modificationDate ?? .distantPast)
            }
        case .modificationDateDescending:
            return sorted { lhs, rhs in
                (lhs.modificationDate ?? .distantPast) > (rhs.modificationDate ?? .distantPast)
            }
        }
    }
}
