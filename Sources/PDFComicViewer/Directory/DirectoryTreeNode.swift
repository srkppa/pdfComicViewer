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
    var children: [DirectoryTreeNode]?

    init(url: URL, kind: Kind, children: [DirectoryTreeNode]? = nil) {
        self.id = url.standardizedFileURL.path
        self.url = url
        self.name = url.lastPathComponent
        self.kind = kind
        self.children = children
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
}
