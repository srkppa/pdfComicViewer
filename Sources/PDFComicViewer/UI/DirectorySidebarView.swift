import SwiftUI

@MainActor
struct DirectorySidebarView: View {
    @ObservedObject var model: DirectorySidebarViewModel
    let currentFileURL: URL?
    let chooseFolder: () -> Void
    let openPDF: (URL) -> Void
    let hideSidebar: () -> Void

    @State private var selectedNodeID: String?

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
            displayOptionsMenu
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

    /// 更新日の表示切り替え・並べ替え条件をまとめたメニュー。
    private var displayOptionsMenu: some View {
        Menu {
            Toggle("更新日を表示", isOn: $model.showsModificationDate)
            Divider()
            Picker("並べ替え", selection: $model.sortOrder) {
                Text("名前（昇順）").tag(DirectorySortOrder.nameAscending)
                Text("名前（降順）").tag(DirectorySortOrder.nameDescending)
                Text("更新日（新しい順）").tag(DirectorySortOrder.modificationDateDescending)
                Text("更新日（古い順）").tag(DirectorySortOrder.modificationDateAscending)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20, height: 20)
        .foregroundStyle(ReaderTheme.primaryText)
        .help("表示オプション（更新日の表示・並べ替え）")
        .nativeToolTip("表示オプション（更新日の表示・並べ替え）")
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
            List(model.sortedNodes, children: \.children, selection: $selectedNodeID) { node in
                row(for: node)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onKeyPress(.return) {
                openSelectedPDF()
                return .handled
            }
        }
    }

    /// 選択中のノードがPDFなら開く。矢印キーで選んだ後にリターンキーで決定する導線。
    private func openSelectedPDF() {
        guard let selectedNodeID,
              let node = model.nodes.firstNode(withID: selectedNodeID),
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
            if model.showsModificationDate, let modificationDate = node.modificationDate {
                Spacer(minLength: 8)
                Text(modificationDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.secondaryText)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard node.kind == .pdf else { return }
            openPDF(node.url)
        }
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
