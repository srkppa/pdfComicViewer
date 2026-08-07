import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ReaderView: View {
    @ObservedObject var model: ReaderViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var fileImporterIsPresented = false
    @State private var replacementPromptIsPresented = false
    @State private var isDropTargeted = false
    @State private var isFullScreen = false
    @State private var controlsVisible = true
    @State private var toolbarControlHasKeyboardFocus = false
    @State private var contextPageIndex: Int?
    @State private var hideControlsTask: Task<Void, Never>?
    @StateObject private var sidebarModel = DirectorySidebarViewModel()
    @State private var sidebarIsVisible = false
    @State private var folderImporterIsPresented = false

    var body: some View {
        HStack(spacing: 0) {
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
                            sidebarIsVisible: $sidebarIsVisible,
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

            if sidebarIsVisible, !isFullScreen {
                Divider()
                DirectorySidebarView(
                    model: sidebarModel,
                    currentFileURL: model.session?.url,
                    chooseFolder: { folderImporterIsPresented = true },
                    openPDF: { url in Task { await model.open(url: url) } }
                )
                .frame(width: 260)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: sidebarIsVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ReaderTheme.canvas)
        .preferredColorScheme(.dark)
        .tint(ReaderTheme.accent)
        .toolbar {
            if !isFullScreen {
                ToolbarItem(placement: .principal) {
                    ReaderToolbar(
                        model: model,
                        sidebarIsVisible: $sidebarIsVisible,
                        keyboardFocusChange: { focused in
                            toolbarControlHasKeyboardFocus = focused
                        }
                    )
                }
            }
        }
        .toolbarVisibility(isFullScreen ? .hidden : .visible, for: .windowToolbar)
        .fileImporter(
            isPresented: $fileImporterIsPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .fileImporter(
            isPresented: $folderImporterIsPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFolderImport
        )
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
                fileImporterIsPresented = true
            }
            Button("閉じる", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "別のPDFを選んでください。")
        }
        .onChange(of: model.fileOpenRequestSequence) { _, _ in
            fileImporterIsPresented = true
        }
        .onChange(of: model.replacementConfirmation != nil, initial: true) { _, pending in
            if pending {
                replacementPromptIsPresented = true
            }
        }
        .onChange(of: model.session?.url) { _, newURL in
            guard let newURL else { return }
            sidebarModel.setRoot(newURL.deletingLastPathComponent())
        }
        .onChange(of: sidebarModel.rootURL) { oldValue, newValue in
            guard oldValue == nil, newValue != nil else { return }
            sidebarIsVisible = true
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await model.flushPendingSaves() }
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
                excludedBottomHeight: model.warningMessage == nil ? 0 : 52,
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
                fileImporterIsPresented = true
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
            sidebarModel.setRoot(url)
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
