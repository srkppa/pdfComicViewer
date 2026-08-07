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
