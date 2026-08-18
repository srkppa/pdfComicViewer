# シークバー・最初に戻る・削除 設計

## 背景・目的

現在のPDF漫画ビューアーには、ページを大きく飛ばす手段が「次へ／前へ」の逐次移動しかない。また、読み終えたPDFを最初から読み直したり、不要になったPDFを整理したりする導線がアプリ内に存在せず、Finderへ切り替える必要がある。

本フェーズでは次の3機能を追加する。

1. **シークバー** — 本文下端にスライダーを出し、任意のページへ一気に飛べるようにする
2. **最初に戻る** — PDFの読書位置を先頭に戻す（サイドバーの右クリックとツールバーのボタン）
3. **削除** — 不要なPDFを複数選択してゴミ箱へ送る（サイドバーの右クリックとツールバーのボタン）

## スコープ

- 対象は macOS ネイティブアプリ（非サンドボックス、ローカルビルド）の既存 SwiftUI コードベース。
- 以下は本フェーズの対象外とし、別の仕様書で扱う。
  - フェーズ2「シリーズを読み進める」— 次の巻へ自動遷移、サイドバーへの読書進捗表示、絞り込み検索
    （2026-08-13の仕様書で実装済み）
  - フェーズ3「ページサムネイル一覧」— 全ページのグリッド表示とジャンプ
    （2026-08-18に取りやめ。シークバーでのページ移動で足りているため、実装しない）
- シークバーの表示状態（表示中かどうか）はアプリ再起動をまたいで永続化しない。ポインタ位置から毎回導出する。
- 削除はゴミ箱への移動のみとし、完全削除は提供しない。

## 全体構成

既存の「純粋ロジックは独立した型に切り出してテストし、SwiftUIのView本体はテストしない」という方針を踏襲する。

### 新規ファイル

- `Sources/PDFComicViewer/Domain/SeekBarPresentation.swift` — 表示単位インデックスとスライダー値の相互変換（綴じ方向の反転を含む純粋関数）
- `Sources/PDFComicViewer/UI/ReaderSeekBar.swift` — シークバーのSwiftUI View
- `Sources/PDFComicViewer/Persistence/FileTrashing.swift` — ゴミ箱移動のプロトコルとライブ実装（`DirectoryScanning` と同じDIパターン）

### 変更ファイル

- `ReaderViewModel.swift` — `goToFirstPage()` と `jumpToUnit(index:)` を追加。`live()` が読書位置ストアを受け取る形に変更
- `ReadingProgressStore.swift` — `ReadingProgressStoring` に `remove(for:)` を追加
- `DirectorySidebarViewModel.swift` — `progressStore` と `trashService` を注入し、削除・進捗リセットのメソッドを追加
- `DirectorySidebarView.swift` — 複数選択、右クリックメニュー
- `ReaderView.swift` — シークバーの配置とホバー検出、削除確認ダイアログ、各種配線
- `ReaderToolbar.swift` — 「最初に戻る」「削除」ボタンを追加
- `PDFComicViewerApp.swift` — `AppServices` に読書位置ストアの共有インスタンスを持たせ、両ViewModelへ配る

### 責務の配置

削除と進捗リセットは「サイドバーの右クリック」と「ツールバーのボタン」の両方から呼ばれる。実装は **`DirectorySidebarViewModel` に集約**し、ツールバー側も `ReaderView` を経由して同じメソッドを呼ぶ。

理由は、削除後には必ずツリーの再スキャンが必要であり、ツリーを保持している `DirectorySidebarViewModel` に置くのが最も配線が短いため。独立したサービス層を新設して両ViewModelから使う構成も検討したが、再スキャンの通知経路を別途用意する必要があり、この規模では複雑さに見合わない。

`ReaderViewModel` は引き続き「今開いているPDFを表示する」責務に閉じ、ファイルシステム操作は持たない。

### 読書位置ストアの共有（重要）

`DirectorySidebarViewModel` が読書位置を書き換えるようになるため、**`ReaderViewModel` と `DirectorySidebarViewModel` は同一の `ReadingProgressStoring` インスタンスを共有しなければならない**。

`FileReadingProgressStore` はactorであり、`records` にレコード全体をメモリキャッシュしている。同じJSONファイルを指す別インスタンスを2つ作ると、次の順序で書き込みが失われる。

1. サイドバー側のインスタンスが「最初に戻る」でレコードを書き換え、ファイルへ保存する
2. リーダー側のインスタンスは古いキャッシュを保持したまま
3. リーダー側がページ送りで `save(_:)` を呼ぶと、古いキャッシュを基に全レコードを書き戻し、1のリセットを消す

現在は `ReaderViewModel.live()` が内部でストアを生成しており、`ReaderView` も `@StateObject private var sidebarModel = DirectorySidebarViewModel()` と引数なしで生成している。これを次のように改める。

- `AppServices` に共有インスタンスを1つ持たせる（`readerModel` と同じ場所）
- `ReaderViewModel.live()` はそのインスタンスを受け取る形に変え、内部生成をやめる
- `DirectorySidebarViewModel` も同じインスタンスを受け取る。`ReaderView` は引数なしで生成できなくなるため、`PDFComicViewerApp` 側で生成して `ReaderView` に渡すか、`AppServices` 経由で取得する

テストでは従来どおりフェイクを注入するため、この共有はライブ構成（`AppServices`）にのみ適用する。

## シークバー

### 表示・非表示

- 本文エリアに `.onContinuousHover` を付け、ポインタが**下端から80pt以内**にある間だけシークバーを表示する。
- ポインタがシークバー本体の上にある間も、その位置は下端80pt以内に収まるため表示は維持される。
- 帯から出たら **0.4秒後**に非表示にする（`Task` によるディレイ。再入場時はキャンセル）。既存の全画面ツールバー自動非表示（`revealControls`）と同じ考え方。
- 本文エリアの高さは `.onGeometryChange` で取得する。
- ドキュメント未読込時、および表示単位が1個以下のときは表示しない（飛ぶ先がないため）。
- 全画面表示中も同じ挙動で動作する。

### 値の変換

綴じ方向による反転は、View側に条件分岐を散らさず純粋関数に閉じ込める。

```swift
enum SeekBarPresentation {
    /// 表示単位インデックス → スライダー値。右綴じでは左右を反転する。
    static func sliderValue(
        unitIndex: Int,
        unitCount: Int,
        binding: BindingDirection
    ) -> Double {
        guard unitCount > 1 else { return 0 }
        let clamped = min(max(unitIndex, 0), unitCount - 1)
        return binding == .right
            ? Double(unitCount - 1 - clamped)
            : Double(clamped)
    }

    /// スライダー値 → 表示単位インデックス。`sliderValue` の逆変換。
    static func unitIndex(
        sliderValue: Double,
        unitCount: Int,
        binding: BindingDirection
    ) -> Int {
        guard unitCount > 0 else { return 0 }
        let rounded = min(max(Int(sliderValue.rounded()), 0), unitCount - 1)
        return binding == .right
            ? unitCount - 1 - rounded
            : rounded
    }
}
```

右綴じでは表示単位0（1ページ目）がスライダーの右端に対応し、読み進むほどつまみが左へ動く。既存の矢印キー・クリック領域が綴じ方向で反転する仕様と揃う。

`Slider(value:in:step:)` に `0...Double(unitCount - 1)`、`step: 1` を渡し、離散的に動かす。

### ドラッグ中の追従（間引き）

つまみを動かすたびにページを切り替えると重い。`PagePreviewRenderer` は `@MainActor` であり、`schedulePagePreviews()` が生成する `Task` もMainActor継承のため、**1024×1024のページ描画がメインスレッドで走る**。さらにシークバーは遠くへ飛ぶ操作なので、`PagePreviewCache.beginGeneration` のキャッシュ絞り込みによって移動先では最大6ページ（3表示単位×2ページ）を新規描画することになる。キャンセル判定はページ描画の合間にしか入らないため、高速にドラッグすると描画とキャンセルが連鎖してつまみ自体がカクつく。

そのため**デバウンスして追従**する。

- ドラッグ中はスライダー値だけをView側の `@State` に持ち、ラベル表示を即座に更新する。
- 値が **120ms** 変化しなかったときに初めて `model.jumpToUnit(index:)` を呼ぶ。
- ドラッグ終了時（`onEditingChanged` が `false`）はデバウンスをキャンセルし、即座にジャンプする。

ゆっくり動かせばページが追従し、一気に振れば途中の描画をまとめて飛ばせる。

### ラベル

既存の `ReaderPresentation.pageCounterText(for:totalPages:)` をそのまま使い、`12–13 / 180` の形式で物理ページを表示する。ドラッグ中はジャンプ先の表示単位に対応するテキストを出す。

### クリック競合の回避

`ReaderInputMonitor` はAppKitのローカルイベントモニタで、SwiftUIのヒットテストとは無関係にクリックを拾う。そのため、シークバーの上をクリックすると「つまみ操作」と「ページめくり」が二重に走る。

既存の `excludedBottomHeight` がこの用途にそのまま使えるので、現在の警告バナー用の値と合成する。

```swift
excludedBottomHeight: max(
    model.warningMessage == nil ? 0 : 52,
    seekBarIsVisible ? 64 : 0
)
```

シークバーが隠れている間は0なので、通常の左右クリックめくりは画面全体で従来どおり効く。

## 最初に戻る

### 開いているPDF

`ReaderViewModel` にメソッドを追加する。既存の `next()` / `previous()` と同じ後処理を踏む。

```swift
func goToFirstPage() {
    jumpToUnit(index: 0)
}

func jumpToUnit(index: Int) {
    guard !displayUnits.isEmpty else { return }
    let target = min(max(index, 0), displayUnits.count - 1)
    guard target != currentUnitIndex else { return }
    currentUnitIndex = target
    updateCurrentPageFromUnit()
    schedulePagePreviews()
    fitToWindow()
    scheduleSave()
}
```

`scheduleSave()` を通るため、保存済みの読書位置も先頭に更新される。

### 開いていないPDF

保存済みレコードを読み、`lastPageIndex` を0にして書き戻す。次に開いたとき1ページ目から始まる。

```swift
// DirectorySidebarViewModel
func resetProgress(for urls: [URL]) async {
    for url in urls {
        guard var record = try? await progressStore.load(for: url) else { continue }
        record.preferences.lastPageIndex = 0
        try? await progressStore.save(record)
    }
}
```

記録が存在しないPDFは元から先頭のため、何もせず次へ進む（no-op）。

メニュー項目の有効・無効を記録の有無で切り替えることはしない。行ごとに非同期のストア照会が必要になり、一覧の描画に見合わないため、**常に項目を表示し、記録が無ければ何もしない**方針とする。フェーズ2でサイドバーに読書進捗を表示する際に全レコードをまとめて読むようになるので、その時点で正確な有効・無効判定へ改善できる。

### 導線

- ツールバー：`backward.end` アイコンのボタン。見開き位置ボタンの直後（ページ移動系のまとまり）に置く。`model.session == nil` の間は無効化。キーボードショートカットは割り当てない。
- サイドバー：行の右クリックメニュー「最初に戻る」。
- `ReaderView` が振り分ける。対象URLが `model.session?.url` と一致する場合は `model.goToFirstPage()` を呼び、それ以外は `sidebarModel.resetProgress(for:)` を呼ぶ。複数選択されている場合は両方が走り得る。

## 削除

### 選択

`DirectorySidebarView` の `List` を複数選択に変更する。

```swift
@State private var selectedNodeIDs: Set<String> = []
```

- ⌘クリック・⇧クリックで複数選択できる。
- `Return` キーでPDFを開く既存動作は、**PDFがちょうど1つだけ選択されている**ときに限定する。
- 削除対象はPDFのみ。選択にフォルダ行が混ざっていても除外する。選択にPDFが1つも無い場合は削除項目を表示しない。

```swift
// DirectorySidebarViewModel
func deletablePDFURLs(for ids: Set<String>) -> [URL] {
    ids.compactMap { nodes.firstNode(withID: $0) }
        .filter { $0.kind == .pdf }
        .map(\.url)
}
```

### 右クリックの作法

`List` の `.contextMenu(forSelectionType: String.self)` を使う。SwiftUIがmacOS標準の作法（選択済みの行を右クリックしたら選択全体、選択外の行を右クリックしたらその1件だけ）を担ってくれるため、自前で判定しない。

### 確認ダイアログ

`ReaderView` に状態を持ち、サイドバーからもツールバーからも同じダイアログを通す。既存のアラート群と同じ場所にまとまる。

- 見出し：`2個のPDFをゴミ箱に入れますか？`（1件なら `「◯◯.pdf」をゴミ箱に入れますか？`）
- 本文：対象ファイル名を最大5件まで列挙し、超過分は `ほかN件` と付す
- ボタン：`ゴミ箱に入れる`（`role: .destructive`）と `キャンセル`（`role: .cancel`）

### 実行

```swift
protocol FileTrashing: Sendable {
    /// ゴミ箱へ移動し、失敗したURLだけを返す（全件成功なら空配列）。
    func trash(_ urls: [URL]) async -> [URL]
}
```

エラーの内容ではなく失敗したURLだけを返す。表示に必要なのは件数だけであり、`any Error` を戻り値に含めるとSendable制約（Swift 6のstrict concurrency）を満たすための余計な包み直しが必要になるため。

`FileTrashService` は `FileManager.default.trashItem(at:resultingItemURL:)` を1件ずつ呼ぶ。ファイルI/Oのため `Task.detached(priority: .userInitiated)` で実行し、結果だけをメインアクターへ返す（既存の `DirectoryScanner` と同じ形）。

処理順は次のとおり。

1. **削除対象に現在開いているPDFが含まれていたら、先に `model.closeDocument()` を呼ぶ**（PDFKitがファイルを掴んだままにしないため）
2. `trashService.trash(urls)` でゴミ箱へ移動
3. 成功した各URLについて `progressStore.remove(for:)` で保存済みレコードを削除（孤児レコードを残さない）
4. `reload()` でツリーを再スキャン

### ツールバー

`trash` アイコンのボタン。「PDFを閉じる」の直後に置く。現在開いているPDF1件を対象に、サイドバーと同じ確認ダイアログを通す。`model.session == nil` の間は無効化。キーボードショートカットは割り当てない。

## 保存済みレコードの削除

`ReadingProgressStoring` にメソッドを追加する。

```swift
protocol ReadingProgressStoring: Sendable {
    func load(for url: URL) async throws -> DocumentRecord?
    func save(_ record: DocumentRecord) async throws
    func allRecords() async throws -> [DocumentRecord]
    func remove(for url: URL) async throws   // 追加
}
```

`FileReadingProgressStore.remove(for:)` は、既存の `save(_:)` が重複除去に使っている判定（ブックマーク解決結果の一致、または `normalizedPath` の一致）をそのまま流用して該当レコードを取り除き、JSONを書き戻す。

## エラー処理・エッジケース

- **ゴミ箱移動の部分失敗**：成功分はそのまま反映し、失敗件数を既存の警告バナー（`warningMessage`）に `N件を削除できませんでした。` と出す。全件失敗でもツリーの再スキャンは実行する（実際の状態に追従させるため）。
- **削除対象が既に存在しない**：`trashItem` がエラーを返すが、再スキャンで一覧からは消えるため、警告は出すが状態は正しく収束する。
- **表示単位が0個・1個**：シークバーを表示しない。`jumpToUnit(index:)` は `displayUnits.isEmpty` で早期リターンする。
- **範囲外のインデックス**：`jumpToUnit(index:)` 側でクリップする。`SeekBarPresentation` も両方向でクリップする。
- **ドラッグ中に表示方法（1ページ／見開き）が変わる**：`displayUnits` が組み直されて件数が変わるため、デバウンス中のジャンプは `jumpToUnit(index:)` のクリップに救われる。飛び先がずれる可能性はあるが、ドラッグ中に表示方法を変える操作は現実的に起きないため、追加の防御はしない。
- **削除中に別のPDFを開く**：既存の `loadGeneration` による後勝ち制御がそのまま働く。再スキャンは `scanGeneration` が面倒を見る。
- **サイドバーのルート自体を削除**：本フェーズではフォルダを削除対象にしないため発生しない。

## テスト方針

既存方針どおり、純粋ロジックとViewModelのみを対象とし、SwiftUIのView本体は手元での動作確認に委ねる。

- **`SeekBarPresentationTests`（新規）**：右綴じ・左綴じそれぞれで `sliderValue` と `unitIndex` が相互に逆変換になること、右綴じで1ページ目が右端に対応すること、`unitCount` が0・1のとき、範囲外の入力がクリップされること。
- **`DirectorySidebarViewModelTests`（追加）**：フェイクの `FileTrashing` と `ReadingProgressStoring` を注入し、削除成功時に再スキャンが走ること、部分失敗時にエラーメッセージが立つこと、`deletablePDFURLs` がフォルダを除外すること、`resetProgress` が `lastPageIndex` を0にして保存すること、記録が無いURLで落ちないこと。
- **`ReadingProgressStoreTests`（追加）**：`remove(for:)` が該当レコードだけを消し、他のレコードを残すこと。存在しないURLの削除が無害であること。
- **`ReaderViewModelTests`（追加）**：`goToFirstPage()` が先頭へ移動して保存をスケジュールすること、`jumpToUnit(index:)` が範囲外をクリップすること、ドキュメント未読込時に何も起きないこと。

シークバーの見た目・ホバーの出入り・確認ダイアログの文言表示、および右クリックメニューの挙動は自動テスト対象外とする。

読書位置ストアの共有はライブ構成（`AppServices`）の配線であり、フェイクを注入する単体テストでは検証できない。「サイドバーから最初に戻したあとページを送っても、リセットが消えない」ことを手元で確認する。
