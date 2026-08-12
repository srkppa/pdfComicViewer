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

/// フォルダ一覧の並べ替えの基準。
enum DirectorySortKey: String, CaseIterable, Equatable, Sendable {
    case name
    case modificationDate
}

/// フォルダ一覧の並べ替えの向き。
enum DirectorySortDirection: String, CaseIterable, Equatable, Sendable {
    case ascending
    case descending

    /// 現在の向きを反転させたもの。
    var toggled: DirectorySortDirection {
        self == .ascending ? .descending : .ascending
    }
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

    /// フォルダを先頭に保ったまま、各階層を指定した基準・向きで並べ替えたコピーを返す。
    func sorted(by key: DirectorySortKey, direction: DirectorySortDirection) -> [DirectoryTreeNode] {
        let folders = filter { $0.kind == .folder }.sortedByKey(key, direction: direction)
        let files = filter { $0.kind == .pdf }.sortedByKey(key, direction: direction)
        return (folders + files).map { node in
            var node = node
            node.children = node.children?.sorted(by: key, direction: direction)
            return node
        }
    }

    private func sortedByKey(
        _ key: DirectorySortKey,
        direction: DirectorySortDirection
    ) -> [DirectoryTreeNode] {
        let isOrderedBefore: (DirectoryTreeNode, DirectoryTreeNode) -> Bool
        switch key {
        case .name:
            isOrderedBefore = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .modificationDate:
            isOrderedBefore = {
                ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast)
            }
        }
        switch direction {
        case .ascending:
            return sorted(by: isOrderedBefore)
        case .descending:
            return sorted { isOrderedBefore($1, $0) }
        }
    }
}
