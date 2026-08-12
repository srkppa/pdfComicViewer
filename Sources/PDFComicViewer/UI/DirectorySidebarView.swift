import SwiftUI

@MainActor
struct DirectorySidebarView: View {
    @ObservedObject var model: DirectorySidebarViewModel
    let currentFileURL: URL?
    let chooseFolder: () -> Void
    let openPDF: (URL) -> Void
    let hideSidebar: () -> Void
    let resetProgress: ([URL]) -> Void
    let requestDelete: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxHeight: .infinity)
        .background(ReaderTheme.surface)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: hideSidebar) {
                Image(systemName: "sidebar.left")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ReaderTheme.primaryText)
            .contentShape(Rectangle())
            .accessibilityLabel("サイドバーを隠す")
            .help("サイドバーを隠す（⌘B）")
            .nativeToolTip("サイドバーを隠す（⌘B）")

            Text(model.rootURL?.lastPathComponent ?? "フォルダ未選択")
                .font(.callout.weight(.medium))
                .foregroundStyle(ReaderTheme.primaryText)
                .lineLimit(1)
            Spacer()
            sortKeyButton
            sortDirectionButton
            modificationDateToggleButton
            Button(action: chooseFolder) {
                Image(systemName: "folder")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ReaderTheme.primaryText)
            .contentShape(Rectangle())
            .accessibilityLabel("フォルダを選択")
            .help("表示するフォルダを選び直す（新規フォルダの作成ではありません）")
            .nativeToolTip("表示するフォルダを選び直す（新規フォルダの作成ではありません）")
        }
        .padding(10)
    }

    /// 並べ替えの基準（名前・更新日）をワンクリックで切り替えるボタン。
    private var sortKeyButton: some View {
        let isName = model.sortKey == .name
        let helpText = "並べ替えの基準: \(isName ? "名前" : "更新日")"
            + "（クリックで\(isName ? "更新日" : "名前")順に切替）"
        return Button {
            model.sortKey = isName ? .modificationDate : .name
        } label: {
            Image(systemName: isName ? "textformat" : "clock")
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ReaderTheme.primaryText)
        .contentShape(Rectangle())
        .accessibilityLabel(helpText)
        .help(helpText)
        .nativeToolTip(helpText)
    }

    /// 並べ替えの向き（昇順・降順）をワンクリックで反転させるボタン。
    private var sortDirectionButton: some View {
        let isAscending = model.sortDirection == .ascending
        let helpText = "並べ替えの向きを反転（現在: \(isAscending ? "昇順" : "降順")）"
        return Button {
            model.sortDirection = model.sortDirection.toggled
        } label: {
            Image(systemName: isAscending ? "arrow.up" : "arrow.down")
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ReaderTheme.primaryText)
        .contentShape(Rectangle())
        .accessibilityLabel(isAscending ? "昇順で並べ替え中" : "降順で並べ替え中")
        .help(helpText)
        .nativeToolTip(helpText)
    }

    /// 更新日の表示・非表示だけを独立して切り替えるボタン。
    private var modificationDateToggleButton: some View {
        let isOn = model.showsModificationDate
        let helpText = isOn ? "更新日を非表示にする" : "更新日を表示する"
        return Button {
            model.showsModificationDate.toggle()
        } label: {
            Image(systemName: "calendar")
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? ReaderTheme.accent : ReaderTheme.primaryText)
        .contentShape(Rectangle())
        .accessibilityLabel(helpText)
        .help(helpText)
        .nativeToolTip(helpText)
    }

    @ViewBuilder
    private var content: some View {
        if model.rootURL == nil {
            emptyRootState
        } else if model.isLoading && model.nodes.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(ReaderTheme.secondaryText)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if model.nodes.isEmpty {
            Text("PDFが見つかりません")
                .font(.callout)
                .foregroundStyle(ReaderTheme.secondaryText)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List(model.sortedNodes, children: \.children, selection: $model.selectedNodeIDs) { node in
                row(for: node)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onKeyPress(.return) {
                openSelectedPDF()
                return .handled
            }
            .contextMenu(forSelectionType: String.self) { ids in
                contextMenuItems(for: ids)
            } primaryAction: { ids in
                openPDF(forSelection: ids)
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for ids: Set<String>) -> some View {
        let urls = model.pdfURLs(for: ids)
        if !urls.isEmpty {
            Button("最初に戻る") {
                resetProgress(urls)
            }
            Divider()
            Button("ゴミ箱に入れる", role: .destructive) {
                requestDelete(urls)
            }
        }
    }

    /// 選択中のノードがPDF1つだけなら開く。矢印キーで選んだ後にリターンキーで決定する導線。
    /// 複数選択中は、どれを開くべきか決められないので何もしない。
    private func openSelectedPDF() {
        guard model.selectedNodeIDs.count == 1,
              let id = model.selectedNodeIDs.first,
              let node = model.nodes.firstNode(withID: id),
              node.kind == .pdf else { return }
        openPDF(node.url)
    }

    /// ダブルクリックで開く。`List` の `primaryAction` から呼ばれるため、
    /// 行にジェスチャを貼らずに済み、シングルクリックの選択と競合しない。
    private func openPDF(forSelection ids: Set<String>) {
        guard ids.count == 1,
              let id = ids.first,
              let node = model.nodes.firstNode(withID: id),
              node.kind == .pdf else { return }
        openPDF(node.url)
    }

    private func row(for node: DirectoryTreeNode) -> some View {
        let isCurrent = node.kind == .pdf
            && node.url.standardizedFileURL == currentFileURL?.standardizedFileURL
        return HStack(spacing: 6) {
            Image(systemName: node.kind == .folder ? "folder" : "doc.richtext")
                .foregroundStyle(isCurrent ? ReaderTheme.accent : ReaderTheme.secondaryText)
                .accessibilityHidden(true)
            Text(node.name)
                .foregroundStyle(isCurrent ? ReaderTheme.accent : ReaderTheme.primaryText)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                // 更新日の表示幅を確保するため、名前側を優先的に省略させる。
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.showsModificationDate, let modificationDate = node.modificationDate {
                Text(modificationDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.secondaryText)
                    .lineLimit(1)
                    // 更新日自体は省略させず、常に全体を表示する。
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(node.name)
        .accessibilityAddTraits(node.kind == .pdf ? .isButton : [])
    }

    private var emptyRootState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ReaderTheme.secondaryText)
                .accessibilityHidden(true)
            Text("フォルダを選ぶと\nPDFの一覧を表示します")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(ReaderTheme.secondaryText)
            Button("フォルダを選択…", action: chooseFolder)
                .buttonStyle(.bordered)
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundStyle(ReaderTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
