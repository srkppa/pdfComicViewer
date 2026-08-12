# 次の巻へ自動遷移・絞り込み検索 設計

## 背景・目的

フェーズ1（シークバー・最初に戻る・削除）に続く、フェーズ2「シリーズを読み進める」の実装。当初の3案（次の巻へ自動遷移、サイドバーに読書進捗表示、絞り込み検索）のうち、サイドバーへの読書進捗表示は今回のスコープから外す（下記「スコープ外」参照）。本フェーズで実装するのは次の2機能。

1. **次の巻へ自動遷移** — シリーズ物のPDFを最後まで読んだとき、「次へ」操作で自動的に同じフォルダの次のPDFを開く
2. **絞り込み検索** — サイドバーのPDF一覧をファイル名・フォルダ名で絞り込む

## スコープ外

- **サイドバーへの読書進捗表示**：当初案にあったが、シークバーが既にページ番号（例: `12–13 / 180`）で読書位置を示しており、読んでいる最中の進捗把握はそちらで足りると判断し、今回は実装しない。将来的に必要になった場合は別途仕様化する。
- 次の巻の判定はサブフォルダをまたがない（同じフォルダ直下のPDFのみが対象）。
- 検索はサイドバーの一覧絞り込みに限定し、PDF本文の全文検索は対象外。

## 全体構成

既存の「純粋ロジックは独立した型に切り出してテストし、SwiftUIのView本体はテストしない」という方針を踏襲する。

### 新規ファイル

- `Sources/PDFComicViewer/Directory/SeriesNavigating.swift` — 「次のPDF」を選ぶ純粋関数（`SeriesNavigation`）と、それを使うディレクトリ読み込みのプロトコル・ライブ実装（`SeriesNavigating` / `SeriesNavigator`。`DirectoryScanning`と同じDIパターン）
- `Tests/PDFComicViewerTests/SeriesNavigationTests.swift` — 純粋関数`SeriesNavigation.nextURL(after:in:)`のテスト（I/Oなし）
- `Tests/PDFComicViewerTests/SeriesNavigatingTests.swift` — ライブ実装`SeriesNavigator`のテスト（一時ディレクトリを使うI/Oあり）

### 変更ファイル

- `Sources/PDFComicViewer/Directory/DirectoryTreeNode.swift` — `[DirectoryTreeNode].filtered(byQuery:)` を追加
- `Sources/PDFComicViewer/Directory/DirectorySidebarViewModel.swift` — `searchQuery`・`displayedNodes` を追加、`setRoot`で`searchQuery`をリセット
- `Sources/PDFComicViewer/UI/DirectorySidebarView.swift` — 検索欄の追加、一覧表示を`sortedNodes`から`displayedNodes`へ
- `Sources/PDFComicViewer/Reader/ReaderViewModel.swift` — `SeriesNavigating`を注入、`next()`に自動遷移の分岐を追加
- `Sources/PDFComicViewer/App/PDFComicViewerApp.swift` — `AppServices`に`SeriesNavigating`のライブ実装を追加
- `Tests/PDFComicViewerTests/DirectoryTreeNodeTests.swift`、`DirectorySidebarViewModelTests.swift`、`ReaderViewModelTests.swift` — 追加テスト

## 次の巻へ自動遷移

### 判定範囲

「次の巻」は**開いているPDFと同じフォルダ直下**にあるPDFに限定する。サブフォルダをまたいだ探索はしない（例: `シリーズA/上巻/1.pdf` と `シリーズA/下巻/1.pdf` は別フォルダなので次の巻とはみなさない）。順序は常にファイル名の昇順（`localizedStandardCompare`）。サイドバーの現在の並べ替え設定（更新日順など）には影響されない。

### 責務の分離

I/Oを伴うディレクトリ読み込みと、並べ替え済みURL配列から次を選ぶ純粋ロジックを分離する。後者はテストで境界条件（末尾・現在位置が見つからない・空配列）を確認しやすくするため。

```swift
enum SeriesNavigation {
    /// ソート済みURL配列の中から、`current`の次のURLを返す。
    /// `current`が含まれていなければ`nil`。
    static func nextURL(after current: URL, in sortedURLs: [URL]) -> URL?
}

protocol SeriesNavigating: Sendable {
    func nextVolumeURL(after url: URL) async -> URL?
}

struct SeriesNavigator: SeriesNavigating {
    func nextVolumeURL(after url: URL) async -> URL? {
        // Task.detached(priority: .userInitiated) でurlの親フォルダのみを読み直す。
        // サイドバーの走査状態には依存しない。
        // 隠しファイル除外・拡張子.pdfのみ・localizedStandardCompareで並べ替え
        // という判定基準は DirectoryScanner と同じにする。
        // 並べ替え後、SeriesNavigation.nextURL(after:in:) に委譲する。
    }
}
```

### `ReaderViewModel`への組み込み

`next()`の「既に最後の表示単位にいる」分岐（現状は無条件でno-op）に、自動遷移の試行を追加する。

```swift
func next() {
    guard !displayUnits.isEmpty else { return }
    let nextIndex = min(currentUnitIndex + 1, displayUnits.count - 1)
    guard nextIndex != currentUnitIndex else {
        advanceToNextVolumeIfPossible()
        return
    }
    currentUnitIndex = nextIndex
    updateCurrentPageFromUnit()
    schedulePagePreviews()
    fitToWindow()
    scheduleSave()
}

private func advanceToNextVolumeIfPossible() {
    guard nextVolumeTask == nil, let session else { return }
    nextVolumeTask = Task { [weak self] in
        defer { self?.nextVolumeTask = nil }
        guard let self,
              let nextURL = await self.seriesNavigator.nextVolumeURL(after: session.url) else {
            return
        }
        await self.open(url: nextURL)
    }
}
```

- `seriesNavigator: any SeriesNavigating` を`ReaderViewModel.init(loader:progressStore:seriesNavigator:)`に追加する（既存の`loader`・`progressStore`と同じくコンストラクタ注入）。ライブ実装は`AppServices`が`SeriesNavigator()`を渡す。テストではフェイクを注入する。
- `nextVolumeTask: Task<Void, Never>?` を新設し、連打で二重に探索・オープンが走らないようにガードする（既存の`saveTask`・`pagePreviewTask`と同じパターン）。
- 次の巻が見つかれば既存の`open(url:)`をそのまま呼ぶ。パスワード保護・置き換え確認など既存のフローがそのまま効く。
- 次の巻が見つからない場合（シリーズの最後、または対象PDFが既に移動・削除されているなど）は何もしない。既存の「最後のページで次へを押しても変化なし」という体験と地続きになる。
- 常にONで、オフにする設定は設けない。

## 絞り込み検索

### 絞り込みロジック（純粋関数）

`DirectoryTreeNode.swift`に、既存の`sorted(by:direction:)`と並ぶ形で追加する。

```swift
extension [DirectoryTreeNode] {
    /// クエリが空文字（前後の空白を除去した上で）なら全件そのまま返す。
    /// そうでなければ、フォルダ名・ファイル名が部分一致（大小文字を無視）した
    /// ノードを残す。フォルダ自体がマッチしたら中身は絞らず全部残し、
    /// フォルダ名がマッチしなければ子を再帰的に絞り込み、
    /// 何か残るフォルダだけを残す（マッチしたファイルまでの経路を保つため）。
    func filtered(byQuery query: String) -> [DirectoryTreeNode]
}
```

### ViewModel側

```swift
/// 空文字なら絞り込みなし。フォルダを切り替えたら空に戻す。
@Published var searchQuery: String = ""

/// 絞り込みと並べ替えを両方適用した、実際にListへ渡す配列。
var displayedNodes: [DirectoryTreeNode] {
    nodes.filtered(byQuery: searchQuery).sorted(by: sortKey, direction: sortDirection)
}
```

- 既存の`sortedNodes`はそのまま残す（既存テストへの影響を避けるため）。`displayedNodes`を新設し、Viewの一覧表示はこちらに差し替える。
- `setRoot(_:)`の冒頭で`searchQuery = ""`にリセットする。別フォルダへ切り替えた際に前の検索語が残って一覧が空に見える、という混乱を防ぐため。

### View側

- ヘッダー（フォルダ名・並べ替えボタン群）の下に、検索欄を常時表示する。フォルダ未選択時（`rootURL == nil`）は表示しない。
- `TextField`＋虫眼鏡アイコン＋入力時のみ表示されるクリアボタン。プレースホルダは「検索...」。
- 検索で一致が0件のときは、新しい文言を追加せず既存の「PDFが見つかりません」をそのまま流用する。

## エラー処理・エッジケース

- **次の巻の探索中に別の操作が来た場合**：`open(url:)`の既存の`loadGeneration`による後勝ち制御がそのまま面倒を見る。
- **次の巻の対象PDFが探索中に削除・移動された場合**：`SeriesNavigator`が現在のファイル一覧から見つけられず`nil`を返し、何も起きない。
- **検索中にフォルダの再スキャンが走った場合**（削除やリロード）：`nodes`が更新されれば`displayedNodes`は自動的に再計算される。`searchQuery`はリロードでは消えない（`setRoot`のときだけ消す）。
- **サイドバーで検索中に選択していたPDFが絞り込みで見えなくなった場合**：`selectedNodeIDs`はそのまま保持する（絞り込みを解除すれば選択状態に戻る）。ツールバーの操作対象（`toolbarTargetURLs`）は選択IDから`pdfURLs(for:)`で解決するため、見えていない選択に対しても変わらず機能する。

## テスト方針

- **`SeriesNavigationTests`（新規）**：ソート済みURL配列と現在のURLから次を選ぶロジックの境界（末尾で`nil`、現在のURLが見つからない、空配列）。I/Oなし。
- **`SeriesNavigatingTests`（新規）**：`DirectoryScannerTests`と同じ形で一時ディレクトリを使い、隠しファイル除外・拡張子フィルタ・`localizedStandardCompare`順を検証。
- **`DirectoryTreeNodeTests`（追加）**：`filtered(byQuery:)`の名前部分一致・大小文字無視、フォルダマッチ時の全展開、ネストしたフォルダでの経路保持、空クエリ、非マッチ。
- **`DirectorySidebarViewModelTests`（追加）**：`searchQuery`の既定値、`displayedNodes`が絞り込み＋並べ替えの両方を反映すること、`setRoot`で`searchQuery`がリセットされること。
- **`ReaderViewModelTests`（追加）**：フェイクの`SeriesNavigating`を注入し、最後のページで「次へ」→次の巻が見つかれば`open`相当の状態遷移が起きること、見つからなければ何も起きないこと、連打しても二重に走らないこと。

View本体（検索欄のレイアウト、絞り込み結果の表示）は既存方針どおりテストせず、手元での動作確認に委ねる。
