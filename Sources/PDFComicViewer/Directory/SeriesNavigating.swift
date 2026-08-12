import Foundation

/// ソート済みURL配列から「次」を選ぶ純粋ロジック。
/// ディレクトリの読み込み（I/O）とは切り離してテストできるようにする。
enum SeriesNavigation {
    /// `sortedURLs`の中から`current`の次のURLを返す。
    /// `current`が含まれていない、または既に最後なら`nil`。
    static func nextURL(after current: URL, in sortedURLs: [URL]) -> URL? {
        let target = current.standardizedFileURL
        guard let index = sortedURLs.firstIndex(where: { $0.standardizedFileURL == target }) else {
            return nil
        }
        let nextIndex = index + 1
        guard sortedURLs.indices.contains(nextIndex) else { return nil }
        return sortedURLs[nextIndex]
    }
}

protocol SeriesNavigating: Sendable {
    /// 開いているPDFと同じフォルダ直下から、ファイル名順で次のPDFを探す。
    /// サブフォルダはまたがない。見つからなければ`nil`。
    func nextVolumeURL(after url: URL) async -> URL?
}

struct SeriesNavigator: SeriesNavigating {
    func nextVolumeURL(after url: URL) async -> URL? {
        let target = url.standardizedFileURL
        let parent = target.deletingLastPathComponent()
        let siblings = await Task.detached(priority: .userInitiated) {
            Self.pdfSiblings(in: parent)
        }.value
        return SeriesNavigation.nextURL(after: target, in: siblings)
    }

    private static func pdfSiblings(in folder: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let pdfs = contents.filter { childURL in
            guard let resourceValues = try? childURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ), resourceValues.isSymbolicLink != true, resourceValues.isDirectory != true else {
                return false
            }
            return childURL.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame
        }
        return pdfs.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
