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

    /// クエリで絞り込んだコピーを返す。空文字（前後の空白を除去した上で）なら全件そのまま。
    /// フォルダ名・ファイル名が部分一致（大小文字を無視）したノードを残す。
    /// フォルダ自体がマッチしたら中身は絞らず全部残し、マッチしなければ子を
    /// 再帰的に絞り込んで、何か残るフォルダだけを残す
    /// （マッチしたファイルまでの経路を保つため）。
    func filtered(byQuery query: String) -> [DirectoryTreeNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return compactMap { node -> DirectoryTreeNode? in
            if node.name.localizedCaseInsensitiveContains(trimmed) {
                return node
            }
            guard node.kind == .folder, let children = node.children else { return nil }
            let filteredChildren = children.filtered(byQuery: trimmed)
            guard !filteredChildren.isEmpty else { return nil }
            var copy = node
            copy.children = filteredChildren
            return copy
        }
    }

    /// クエリに一致したPDFだけを、フォルダ階層を畳んで一列にして返す。
    /// 空クエリなら空配列（呼び出し側が絞り込み前のツリーを使う想定）。
    ///
    /// SwiftUIの`List(children:)`は折りたたみ状態を外から開けないため、
    /// 階層を保ったまま絞り込むと、一致したPDFが閉じた三角の中に隠れて
    /// 見えない。検索中だけ階層を畳んで、結果を直接並べる。
    func flattenedPDFMatches(byQuery query: String) -> [DirectoryTreeNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return filtered(byQuery: trimmed).flattenedPDFs()
    }

    /// ツリーを深さ優先でたどり、PDFノードだけを集める。
    /// `children`は必ず`nil`にして、Listに折りたたみ三角を描かせない。
    private func flattenedPDFs() -> [DirectoryTreeNode] {
        flatMap { node -> [DirectoryTreeNode] in
            switch node.kind {
            case .pdf:
                var leaf = node
                leaf.children = nil
                return [leaf]
            case .folder:
                return node.children?.flattenedPDFs() ?? []
            }
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
