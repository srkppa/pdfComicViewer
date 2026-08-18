import Foundation

/// ソート済みURL配列から「次」を選ぶ純粋ロジック。
/// ディレクトリの読み込み（I/O）とは切り離してテストできるようにする。
enum SeriesNavigation {
    /// `sortedURLs`の中から`current`の次のURLを返す。
    /// `current`が含まれていない、または既に最後なら`nil`。
    static func nextURL(after current: URL, in sortedURLs: [URL]) -> URL? {
        neighbour(of: current, in: sortedURLs, offset: 1)
    }

    /// `sortedURLs`の中から`current`の手前のURLを返す。
    /// `current`が含まれていない、または既に先頭なら`nil`。
    static func previousURL(before current: URL, in sortedURLs: [URL]) -> URL? {
        neighbour(of: current, in: sortedURLs, offset: -1)
    }

    private static func neighbour(of current: URL, in sortedURLs: [URL], offset: Int) -> URL? {
        let target = current.standardizedFileURL
        guard let index = sortedURLs.firstIndex(where: { $0.standardizedFileURL == target }) else {
            return nil
        }
        let neighbourIndex = index + offset
        guard sortedURLs.indices.contains(neighbourIndex) else { return nil }
        return sortedURLs[neighbourIndex]
    }
}

protocol SeriesNavigating: Sendable {
    /// 開いているPDFと同じフォルダ直下から、ファイル名順で次のPDFを探す。
    /// サブフォルダはまたがない。見つからなければ`nil`。
    func nextVolumeURL(after url: URL) async -> URL?

    /// 同じく、ファイル名順で手前のPDFを探す。
    func previousVolumeURL(before url: URL) async -> URL?

    /// 前後の巻を一度に返す。ボタンを押せるかどうかの判定用で、
    /// 移動そのものには使わない。フォルダの読み込みを1回で済ませるために分けてある。
    func adjacentVolumeURLs(of url: URL) async -> (previous: URL?, next: URL?)
}

struct SeriesNavigator: SeriesNavigating {
    func nextVolumeURL(after url: URL) async -> URL? {
        let target = url.standardizedFileURL
        return SeriesNavigation.nextURL(after: target, in: await siblings(of: target))
    }

    func previousVolumeURL(before url: URL) async -> URL? {
        let target = url.standardizedFileURL
        return SeriesNavigation.previousURL(before: target, in: await siblings(of: target))
    }

    func adjacentVolumeURLs(of url: URL) async -> (previous: URL?, next: URL?) {
        let target = url.standardizedFileURL
        let siblings = await siblings(of: target)
        return (
            SeriesNavigation.previousURL(before: target, in: siblings),
            SeriesNavigation.nextURL(after: target, in: siblings)
        )
    }

    private func siblings(of target: URL) async -> [URL] {
        let parent = target.deletingLastPathComponent()
        return await Task.detached(priority: .userInitiated) {
            Self.pdfSiblings(in: parent)
        }.value
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
