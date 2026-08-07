# ディレクトリサイドバー設計

## 背景・目的

現在のPDF漫画ビューアーは、1つのPDFを開くと表示を置き換える単一ドキュメントモデルであり、フォルダ内の他のPDFへ切り替える手段や、開いたファイルを閉じて空の状態へ戻す手段がない。以下の3機能を追加する。

1. ウインドウ右側にディレクトリ（フォルダ）をツリー表示し、そこからPDFを選んで開ける
2. そのツリー表示（サイドバー）は開閉可能とする
3. 開いているPDFを閉じて空の状態に戻す機能を追加する

## スコープ

- 対象は macOS ネイティブアプリ（非サンドボックス、ローカルビルド）の既存 SwiftUI コードベース。
- 複数PDFの同時タブ表示は対象外。表示は引き続き「1つのPDFを表示する」単一ドキュメントモデルを維持し、サイドバーは「次に開くPDFを選ぶための一覧」という位置づけ。
- サイドバーの状態（選択中ルートフォルダ、開閉状態、展開ノード）はアプリ再起動をまたいで永続化しない（毎回初期状態）。
- サイドバー幅のユーザーによるリサイズは対象外（固定幅）。

## 全体構成

新規に「ディレクトリサイドバー」機能を独立したモジュールとして追加し、既存の単一ドキュメント表示ロジック（`ReaderViewModel`）への変更は最小限（`closeDocument()` の追加のみ）に留める。

### 新規ファイル

- `Sources/PDFComicViewer/Directory/DirectoryTreeNode.swift` — ツリーのデータモデル
- `Sources/PDFComicViewer/Directory/DirectoryScanning.swift` — フォルダ走査のプロトコルとライブ実装（`PDFDocumentLoading` と同じDIパターン）
- `Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift` — サイドバー専用の状態管理（`ObservableObject`）
- `Sources/PDFComicViewer/UI/DirectorySidebarView.swift` — ツリー表示のSwiftUI View

### 変更ファイル

- `ReaderViewModel.swift` — `closeDocument()` を追加
- `ReaderView.swift` — 右側にサイドバーを配置するレイアウト変更、開閉状態、ルート自動追従の配線
- `ReaderToolbar.swift` — 「サイドバー切り替え」「閉じる」ボタンを追加
- `PDFComicViewerApp.swift` — File メニューに「PDFを閉じる」項目を追加

`ReaderViewModel` は「今開いているPDFを表示する」責務に閉じたままにし、「フォルダツリーの走査・保持」は `DirectorySidebarViewModel` が担当する。両者は `ReaderView` が仲介し、`model.session?.url` の変化を監視してサイドバーのルートフォルダを自動更新する。

## データモデルとフォルダ走査

```swift
struct DirectoryTreeNode: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case folder, pdf }
    let id: String   // 正規化パス
    let url: URL
    let name: String
    let kind: Kind
    var children: [DirectoryTreeNode]?  // folderのみ非nil（空配列もあり得る）
}

protocol DirectoryScanning: Sendable {
    func scan(rootURL: URL) async throws -> [DirectoryTreeNode]
}

struct DirectoryScanner: DirectoryScanning {
    func scan(rootURL: URL) async throws -> [DirectoryTreeNode] {
        try await Task.detached(priority: .userInitiated) {
            try Self.scanChildren(of: rootURL)
        }.value
    }
}
```

走査ルール:

- `FileManager.contentsOfDirectory` で1階層ずつ再帰する。
- 隠しファイル・フォルダ（`.` で始まる名前）とシンボリックリンクは除外する（無限ループ防止）。
- フォルダは中身に関わらずすべて残す（PDFを含まない空フォルダも表示する）。
- ファイルは拡張子が `.pdf`（大文字小文字を無視）のもののみ残す。
- 各階層でフォルダ→PDFファイルの順に、`localizedStandardCompare` でソートする。
- 再帰の節目で `Task.isCancelled` をチェックし、ルート切り替え時に走査を素早く打ち切れるようにする。
- `PDFDocumentLoader` と同様に `Task.detached(priority: .userInitiated)` でバックグラウンド走査し、結果のみをメインアクターへ戻す。

## サイドバーの状態管理

```swift
@MainActor
final class DirectorySidebarViewModel: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var nodes: [DirectoryTreeNode] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let scanner: any DirectoryScanning
    private var scanTask: Task<Void, Never>?

    func setRoot(_ url: URL) {
        // 同じ正規化パスなら何もしない。
        // 異なる場合は scanTask をキャンセルして差し替え、再走査する。
    }
}
```

- `ReaderView` は `model.session?.url` の変化を `onChange` で監視し、変化するたびに `sidebarModel.setRoot(url.deletingLastPathComponent())` を呼ぶ（開いたPDFの親フォルダに常に追従する）。
- 「フォルダを開く」導線はサイドバーの先頭行に置く。ルート未選択時は大きめのボタン、選択済みならフォルダアイコンの小ボタンで選び直せる。`.fileImporter(allowedContentTypes: [.folder])` で選ぶと `sidebarModel.setRoot(url)` を直接呼ぶ。これにより、PDFを開かなくても最初からフォルダを選べる。
- ツリー表示は `List(nodes, children: \.children, selection:)` を使い、フォルダの開閉はSwiftUI標準のディスクロージャに任せる（＝ノード単位の折りたたみ）。PDF行をタップすると `Task { await model.open(url:) }` を呼び、既存のパスワード入力・置き換え確認フローがそのまま使われる。
- ルート＝開いているPDFの親フォルダという設計上、現在開いているファイルは常にルート直下に存在する。したがって選択中PDFのハイライトに自動展開ロジックは不要で、`node.url == model.session?.url` の一致だけで判定できる。

## サイドバー全体の開閉

- `ReaderView` 側の `@State private var sidebarIsVisible = false` で管理し、`ReaderToolbar` に追加するトグルボタンで切り替える。
- ルートが `nil` から非`nil` になった最初の瞬間だけ自動的に `true` にする。以後はユーザー操作を優先する（ユーザーが閉じたら、別のPDFを開いても閉じたままにする）。
- レイアウトは `HStack { readerArea; if sidebarIsVisible { Divider(); DirectorySidebarView(...).frame(width: 260) } }` とし、開閉に `.transition` を付ける。
- 全画面表示中はツールバーと同様にサイドバーも隠す。

## 「開いたファイルを閉じる」機能

`ReaderViewModel` に1メソッドだけ追加する。既存の `flushPendingSaves()` を再利用するため、保存ロジックの重複はない。

```swift
func closeDocument() async {
    guard session != nil else { return }
    await flushPendingSaves()          // 閉じる直前のページ位置・設定を保存
    session = nil
    passwordRequest = nil
    replacementConfirmation = nil
    errorMessage = nil
    warningMessage = nil
    pagePreviewTask?.cancel()
    pagePreviewDocumentID = UUID()
    pagePreviewSnapshot = .empty
    rebuildKeepingCurrentPage()        // session==nil分岐でdisplayUnits等を空にする（既存実装）
}
```

- 呼び出し元は `ReaderToolbar` に追加する「閉じる」アイコンボタン（`model.session == nil` の間は無効化）と、`PDFComicViewerApp.swift` の File メニュー「PDFを閉じる」（既存の `PDFを開く` の下に配置。ショートカットは割り当てない。システム標準の `Cmd+W`＝ウインドウを閉じる、と衝突させないため）。
- 閉じてもサイドバーのルートフォルダ・ツリー展開状態はそのまま維持する（ブラウズを継続できるように）。表示は空状態（ドロップ待ち画面）に戻る。

## エラー処理・エッジケース

- フォルダ走査中に権限エラー等が起きたサブフォルダは、その配下だけスキップしてツリー構築を継続する（アプリ全体を落とさない）。
- ルート自体が読めない場合は `sidebarModel.errorMessage` に日本語メッセージを設定し、サイドバーにインラインで表示する。
- ルート切り替え中に前回の走査が終わっていない場合は `scanTask` をキャンセルしてから新しい走査を開始する（既存の `loadGeneration` 方式と同じ「後勝ち」思想）。
- サイドバーで選んだPDFを開いている最中に別の操作（ツールバーから別PDFを開く等）が来ても、既存の `open(url:)` の世代管理（`loadGeneration`）がそのまま面倒を見る。

## テスト方針

- `DirectoryScannerTests`: 一時ディレクトリを作り、隠しファイル除外・PDF以外除外・空フォルダ保持・ソート順を検証する。
- `DirectorySidebarViewModelTests`: フェイクの `DirectoryScanning` を注入し、ルート切り替え時の再走査・キャンセル・エラー伝搬を検証する（既存 `ReaderViewModelTests` のフェイク注入パターンを踏襲）。
- `ReaderViewModelTests` に `closeDocument()` のケースを追加する（保存が呼ばれること、状態がリセットされること）。
- UIレイアウト自体（サイドバー幅・アニメーション）は既存方針同様、手動確認とし自動テスト対象外とする。
