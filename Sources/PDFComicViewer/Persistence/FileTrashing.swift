import Foundation

protocol FileTrashing: Sendable {
    /// ゴミ箱へ移動し、失敗したURLだけを返す（全件成功なら空配列）。
    func trash(_ urls: [URL]) async -> [URL]
}

struct FileTrashService: FileTrashing {
    func trash(_ urls: [URL]) async -> [URL] {
        guard !urls.isEmpty else { return [] }
        // ファイルI/Oのため、既存の DirectoryScanner と同じく
        // バックグラウンドで実行して結果だけをメインアクターへ返す。
        return await Task.detached(priority: .userInitiated) {
            var failures: [URL] = []
            for url in urls {
                do {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(
                        at: url,
                        resultingItemURL: &resultingURL
                    )
                } catch {
                    failures.append(url)
                }
            }
            return failures
        }.value
    }
}
