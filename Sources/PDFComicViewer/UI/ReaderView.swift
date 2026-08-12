import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// ルートビューに付ける `.fileImporter` がPDF用かフォルダ用かを表す。
private enum FileImportKind: Equatable {
    case pdf
    case folder
}

/// 削除確認ダイアログの対象。ダイアログは `ReaderView` に1つだけ置き、
/// サイドバーの右クリックとツールバーのボタンの両方から使う。
private struct PendingDeletion: Identifiable {
    let id = UUID()
    let urls: [URL]
}

@MainActor
struct ReaderView: View {
    @ObservedObject var model: ReaderViewModel
    @ObservedObject var sidebarModel: DirectorySidebarViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var fileImportKind: FileImportKind?
    @State private var replacementPromptIsPresented = false
    @State private var isDropTargeted = false
    @State private var isFullScreen = false
    @State private var controlsVisible = true
    @State private var toolbarControlHasKeyboardFocus = false
    @State private var contextPageIndex: Int?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var sidebarWidth: CGFloat = 260
    @State private var sidebarWidthAtDragStart: CGFloat?
    @State private var readerAreaHeight: CGFloat = 0
    @State private var pointerIsNearBottom = false
    @State private var hideSeekBarTask: Task<Void, Never>?
    @State private var pendingDeletion: PendingDeletion?

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarIsVisible, !isFullScreen {
                DirectorySidebarView(
                    model: sidebarModel,
                    currentFileURL: model.session?.url,
                    chooseFolder: { fileImportKind = .folder },
                    openPDF: { url in Task { await model.open(url: url) } },
                    hideSidebar: { model.sidebarIsVisible = false },
                    resetProgress: resetProgress(for:),
                    requestDelete: { urls in pendingDeletion = PendingDeletion(urls: urls) }
                )
                .frame(width: sidebarWidth)
                .transition(.move(edge: .leading).combined(with: .opacity))
                sidebarResizeHandle
            }

            ZStack {
                ReaderTheme.canvas.ignoresSafeArea()

                readerArea

                if model.isLoading {
                    loadingOverlay
                }

                if let warningMessage = model.warningMessage {
                    warningBanner(warningMessage)
                }

                if isFullScreen, controlsVisible {
                    VStack {
                        ReaderToolbar(
                            model: model,
                            sidebarIsVisible: $model.sidebarIsVisible,
                            keyboardFocusChange: { focused in
                                toolbarControlHasKeyboardFocus = focused
                            }
                        )
                            .padding(.top, 12)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.18), value: model.sidebarIsVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ReaderTheme.canvas)
        .preferredColorScheme(.dark)
        .tint(ReaderTheme.accent)
        .toolbar {
            if !isFullScreen {
                ToolbarItem(placement: .principal) {
                    ReaderToolbar(
                        model: model,
                        sidebarIsVisible: $model.sidebarIsVisible,
                        keyboardFocusChange: { focused in
                            toolbarControlHasKeyboardFocus = focused
                        }
                    )
                }
            }
        }
        .toolbarVisibility(isFullScreen ? .hidden : .visible, for: .windowToolbar)
        .fileImporter(
            isPresented: fileImportKindIsPresented,
            allowedContentTypes: fileImportKind == .folder ? [.folder] : [.pdf],
            allowsMultipleSelection: false
        ) { [kind = fileImportKind] result in
            switch kind {
            case .pdf:
                handleFileImport(result)
            case .folder:
                handleFolderImport(result)
            case nil:
                break
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            openDroppedPDF(from: urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .sheet(isPresented: passwordSheetIsPresented) {
            PasswordSheet(
                errorMessage: model.errorMessage,
                submit: { password in
                    Task { await model.unlock(password: password) }
                },
                cancel: model.cancelUnlock
            )
            .interactiveDismissDisabled()
        }
        .alert("PDFが置き換えられています", isPresented: $replacementPromptIsPresented) {
            Button("読書位置と設定を引き継ぐ") {
                confirmReplacement(keepPreferences: true)
            }
            Button("新しいPDFとして開く") {
                confirmReplacement(keepPreferences: false)
            }
        } message: {
            Text("以前の読書位置と設定を引き継ぎますか？")
        }
        .alert("PDFを開けません", isPresented: errorAlertIsPresented) {
            Button("別のPDFを選ぶ") {
                model.errorMessage = nil
                fileImportKind = .pdf
            }
            Button("閉じる", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "別のPDFを選んでください。")
        }
        .alert(
            deleteConfirmationTitle(for: pendingDeletion?.urls ?? []),
            isPresented: deleteConfirmationIsPresented,
            presenting: pendingDeletion
        ) { deletion in
            Button("ゴミ箱に入れる", role: .destructive) {
                performDeletion(of: deletion.urls)
            }
            Button("キャンセル", role: .cancel) {}
        } message: { deletion in
            Text(deleteConfirmationMessage(for: deletion.urls))
        }
        .onChange(of: model.fileOpenRequestSequence) { _, _ in
            fileImportKind = .pdf
        }
        .onChange(of: model.replacementConfirmation != nil, initial: true) { _, pending in
            if pending {
                replacementPromptIsPresented = true
            }
        }
        .onChange(of: model.session?.url) { _, newURL in
            guard let newURL else { return }
            let parent = newURL.deletingLastPathComponent().standardizedFileURL
            if let root = sidebarModel.rootURL,
               parent.path == root.path || parent.path.hasPrefix(root.path + "/") {
                return
            }
            sidebarModel.setRoot(parent)
        }
        .onChange(of: sidebarModel.rootURL) { oldValue, newValue in
            guard oldValue == nil, newValue != nil else { return }
            model.sidebarIsVisible = true
        }
        .onDisappear {
            hideControlsTask?.cancel()
            hideSeekBarTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await model.flushPendingSaves() }
        }
    }

    private var sidebarResizeHandle: some View {
        ZStack {
            Divider()
            Color.clear.contentShape(Rectangle())
        }
        .frame(width: 8)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let startingWidth = sidebarWidthAtDragStart ?? sidebarWidth
                    sidebarWidthAtDragStart = startingWidth
                    sidebarWidth = SidebarResizing.width(
                        startingWidth: startingWidth,
                        translation: value.translation.width
                    )
                }
                .onEnded { _ in
                    sidebarWidthAtDragStart = nil
                }
        )
    }

    /// シークバーを実際に出してよいか。飛ぶ先が無いときは出さない。
    private var seekBarIsShown: Bool {
        pointerIsNearBottom
            && model.session != nil
            && model.displayUnits.count > 1
    }

    /// 下端から80pt以内にポインタがあるかどうかで表示を切り替える。
    /// 出したまま消えるとつまみを掴めないので、離れてから0.4秒待って隠す。
    private func updateSeekBarVisibility(isNearBottom: Bool) {
        if isNearBottom {
            hideSeekBarTask?.cancel()
            hideSeekBarTask = nil
            if !pointerIsNearBottom {
                pointerIsNearBottom = true
            }
        } else if pointerIsNearBottom, hideSeekBarTask == nil {
            hideSeekBarTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                pointerIsNearBottom = false
                hideSeekBarTask = nil
            }
        }
    }

    private var readerArea: some View {
        ZStack {
            if let session = model.session, let unit = model.currentUnit {
                PDFSpreadView(
                    document: session.document,
                    placement: SpreadPresentation.placement(
                        for: unit,
                        binding: model.preferences.binding
                    ),
                    zoomCommand: model.zoomCommand,
                    pagePreviewSnapshot: model.pagePreviewSnapshot
                )
            } else if !model.isLoading {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ReaderTheme.accent, lineWidth: 2)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .background {
            ReaderInputMonitor(
                binding: model.preferences.binding,
                isEnabled: model.session != nil
                    && model.passwordRequest == nil
                    && model.replacementConfirmation == nil
                    && model.errorMessage == nil,
                controlHasKeyboardFocus: toolbarControlHasKeyboardFocus,
                excludedTopHeight: isFullScreen && controlsVisible ? 64 : 0,
                excludedBottomHeight: max(
                    model.warningMessage == nil ? 0 : 52,
                    seekBarIsShown ? 64 : 0
                ),
                fullScreenRequestSequence: model.fullScreenRequestSequence,
                action: handleInput,
                interaction: revealControls,
                contextPageRequest: selectContextPage,
                fullScreenChange: handleFullScreenChange
            )
        }
        .contextMenu {
            pageOverrideMenu
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            readerAreaHeight = height
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                updateSeekBarVisibility(
                    isNearBottom: readerAreaHeight > 0
                        && location.y > readerAreaHeight - 80
                )
            case .ended:
                updateSeekBarVisibility(isNearBottom: false)
            }
        }
        .overlay(alignment: .bottom) {
            if seekBarIsShown {
                ReaderSeekBar(model: model)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: seekBarIsShown)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(ReaderTheme.secondaryText)
                .accessibilityHidden(true)

            Text("PDFをここにドロップ")
                .font(.title3.weight(.medium))
                .foregroundStyle(ReaderTheme.primaryText)

            Text("または、Mac上の漫画PDFを選びます")
                .font(.callout)
                .foregroundStyle(ReaderTheme.secondaryText)

            Button("PDFを開く") {
                fileImportKind = .pdf
            }
            .buttonStyle(.borderedProminent)
            .tint(ReaderTheme.accent)
            .controlSize(.large)
            .accessibilityHint("ファイル選択画面からPDFを開きます")
        }
        .padding(30)
        .accessibilityElement(children: .contain)
    }

    private var loadingOverlay: some View {
        ProgressView("PDFを読み込んでいます…")
            .controlSize(.large)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .foregroundStyle(ReaderTheme.primaryText)
            .background(ReaderTheme.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(ReaderTheme.border, lineWidth: 1)
            }
            .accessibilityLabel("PDFを読み込んでいます")
    }

    private func warningBanner(_ message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text(message)
                    .foregroundStyle(ReaderTheme.primaryText)
                Spacer(minLength: 12)
                Button {
                    model.warningMessage = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("警告を閉じる")
                .help("警告を閉じる")
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ReaderTheme.surface.opacity(0.96))
            .overlay(alignment: .top) {
                Rectangle().fill(ReaderTheme.border).frame(height: 1)
            }
        }
        .zIndex(2)
    }

    @ViewBuilder
    private var pageOverrideMenu: some View {
        if let pageIndex = contextPageIndex,
           model.preferences.displayMode == .spread {
            pageOverrideButton(
                "自動レイアウトを使用",
                override: .automatic,
                pageIndex: pageIndex
            )
            pageOverrideButton(
                "このPDFページを単独表示",
                override: .single,
                pageIndex: pageIndex
            )
            pageOverrideButton(
                "このPDFページを見開きへ含める",
                override: .pairable,
                pageIndex: pageIndex
            )
        } else {
            Text("見開き表示でページ設定を変更できます")
        }
    }

    private func pageOverrideButton(
        _ title: String,
        override: PageLayoutOverride,
        pageIndex: Int
    ) -> some View {
        Button {
            model.setPageOverride(override, for: pageIndex)
        } label: {
            if (model.preferences.pageOverrides[pageIndex] ?? .automatic) == override {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var passwordSheetIsPresented: Binding<Bool> {
        Binding(
            get: { model.passwordRequest != nil },
            set: { isPresented in
                if !isPresented, model.passwordRequest != nil {
                    model.cancelUnlock()
                }
            }
        )
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil && model.passwordRequest == nil },
            set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                }
            }
        )
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }

    /// PDF用・フォルダ用の `.fileImporter` を1つに統合するための表示状態。
    /// 同じビューに `.fileImporter` を複数重ねると、片方が発火しなくなることがあるため
    /// 「どちらを開こうとしているか」を単一の状態で表し、1箇所の `.fileImporter` に集約する。
    private var fileImportKindIsPresented: Binding<Bool> {
        Binding(
            get: { fileImportKind != nil },
            set: { isPresented in
                if !isPresented {
                    fileImportKind = nil
                }
            }
        )
    }

    private func handleFileImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await model.open(url: url) }
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            model.errorMessage = "PDFを選択できませんでした。もう一度「PDFを開く」から選んでください。"
        }
    }

    private func handleFolderImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if sidebarModel.rootURL == url.standardizedFileURL {
                sidebarModel.reload()
            } else {
                sidebarModel.setRoot(url)
            }
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            sidebarModel.errorMessage = "フォルダを選択できませんでした。"
        }
    }

    private func openDroppedPDF(from urls: [URL]) -> Bool {
        guard let url = urls.first,
              url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame else {
            model.errorMessage = "PDFファイルをドロップしてください。"
            return false
        }
        Task { await model.open(url: url) }
        return true
    }

    private func resetProgress(for urls: [URL]) {
        let openURL = model.session?.url.standardizedFileURL
        let storedURLs = urls.filter { $0.standardizedFileURL != openURL }
        if urls.contains(where: { $0.standardizedFileURL == openURL }) {
            model.goToFirstPage()
        }
        guard !storedURLs.isEmpty else { return }
        Task {
            let failureCount = await sidebarModel.resetProgress(for: storedURLs)
            if failureCount > 0 {
                model.warningMessage = "\(failureCount)件をリセットできませんでした。"
            }
        }
    }

    private func deleteConfirmationTitle(for urls: [URL]) -> String {
        urls.count == 1
            ? "「\(urls[0].lastPathComponent)」をゴミ箱に入れますか？"
            : "\(urls.count)個のPDFをゴミ箱に入れますか？"
    }

    private func deleteConfirmationMessage(for urls: [URL]) -> String {
        let listed = urls.prefix(5).map(\.lastPathComponent)
        let remainder = urls.count - listed.count
        let names = listed.joined(separator: "\n")
        return remainder > 0 ? "\(names)\nほか\(remainder)件" : names
    }

    private func performDeletion(of urls: [URL]) {
        Task {
            // PDFKitがファイルを掴んだままにしないよう、
            // 開いているPDFが対象なら先に閉じる。
            let openURL = model.session?.url.standardizedFileURL
            if urls.contains(where: { $0.standardizedFileURL == openURL }) {
                await model.closeDocument()
            }
            let failureCount = await sidebarModel.trash(urls: urls)
            if failureCount > 0 {
                model.warningMessage = "\(failureCount)件を削除できませんでした。"
            }
        }
    }

    private func handleInput(_ action: ReaderInputAction) {
        switch action {
        case .next:
            model.next()
        case .previous:
            model.previous()
        case .singlePage:
            model.setDisplayMode(.single)
        case .spread:
            model.setDisplayMode(.spread)
        case .toggleAlignment:
            model.toggleAlignment()
        }
    }

    private func confirmReplacement(keepPreferences: Bool) {
        Task {
            await model.confirmReplacement(keepPreferences: keepPreferences)
            if model.replacementConfirmation != nil {
                replacementPromptIsPresented = true
            }
        }
    }

    private func selectContextPage(horizontalPosition: CGFloat, viewerWidth: CGFloat) {
        guard let unit = model.currentUnit else {
            contextPageIndex = nil
            return
        }
        contextPageIndex = ReaderPresentation.pageIndex(
            atHorizontalPosition: horizontalPosition,
            viewerWidth: viewerWidth,
            placement: SpreadPresentation.placement(
                for: unit,
                binding: model.preferences.binding
            )
        )
    }

    private func handleFullScreenChange(_ fullScreen: Bool) {
        isFullScreen = fullScreen
        hideControlsTask?.cancel()
        if fullScreen {
            revealControls()
        } else {
            controlsVisible = true
        }
    }

    private func revealControls() {
        guard isFullScreen else { return }
        controlsVisible = true
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }
}
