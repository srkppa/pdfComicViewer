import Foundation

/// 検索結果の行に添える補足情報を決める純粋ロジック。
enum SearchResultPresentation {
    /// 検索結果の行に添える親フォルダ名。添えるものが無ければ`nil`。
    ///
    /// 検索中はフォルダ階層を畳んで一列に並べるため、行だけを見ても
    /// どのシリーズの本なのか分からなくなる。そこを親フォルダ名で補う。
    /// 検索していないときは階層がそのまま見えており、ルート直下のPDFは
    /// 親が表示中のフォルダ自身なので、どちらも添えない。
    static func parentFolderName(
        nodeURL: URL,
        rootURL: URL?,
        searchQuery: String
    ) -> String? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // `deletingLastPathComponent()`は末尾にスラッシュを残すため、
        // URL同士の比較ではルートと一致しない。コードベース内の他の場所と
        // 同じく、正規化したパス文字列で突き合わせる。
        let parent = nodeURL.deletingLastPathComponent().standardizedFileURL
        guard parent.path != rootURL?.standardizedFileURL.path else { return nil }
        return parent.lastPathComponent
    }
}
