import Foundation

protocol DirectoryScanning: Sendable {
    func scan(rootURL: URL) async throws -> [DirectoryTreeNode]
}

enum DirectoryScanError: LocalizedError {
    case unreadableFolder

    var errorDescription: String? {
        switch self {
        case .unreadableFolder:
            "フォルダを読み込めません。"
        }
    }
}

struct DirectoryScanner: DirectoryScanning {
    func scan(rootURL: URL) async throws -> [DirectoryTreeNode] {
        let task = Task.detached(priority: .userInitiated) {
            try Self.scanChildren(of: rootURL)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func scanChildren(of url: URL) throws -> [DirectoryTreeNode] {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw DirectoryScanError.unreadableFolder
        }

        var folderNodes: [DirectoryTreeNode] = []
        var pdfNodes: [DirectoryTreeNode] = []

        for childURL in contents {
            guard let resourceValues = try? childURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ), resourceValues.isSymbolicLink != true else {
                continue
            }

            if resourceValues.isDirectory == true {
                let children = (try? scanChildren(of: childURL)) ?? []
                folderNodes.append(
                    DirectoryTreeNode(url: childURL, kind: .folder, children: children)
                )
            } else if childURL.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
                pdfNodes.append(DirectoryTreeNode(url: childURL, kind: .pdf))
            }
        }

        folderNodes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        pdfNodes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return folderNodes + pdfNodes
    }
}
