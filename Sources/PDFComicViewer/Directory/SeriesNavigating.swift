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
