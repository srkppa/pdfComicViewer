import AppKit
import SwiftUI

@MainActor
final class ApplicationTerminationCoordinator {
    enum Decision: Equatable {
        case later
    }

    private var terminationTask: Task<Void, Never>?

    func requestTermination(
        flush: @escaping @MainActor () async -> Void,
        reply: @escaping @MainActor (Bool) -> Void
    ) -> Decision {
        guard terminationTask == nil else { return .later }
        terminationTask = Task { @MainActor [weak self] in
            await flush()
            guard let self, self.terminationTask != nil else { return }
            self.terminationTask = nil
            reply(true)
        }
        return .later
    }
}

@MainActor
enum AppServices {
    /// リーダーとサイドバーの両方が読書位置を書き換えるため、
    /// ストアは必ず1インスタンスだけを共有する。
    /// 別インスタンスにすると、actor内のキャッシュ同士が古い内容で
    /// 上書きし合い、リセットや保存が消える。
    static let progressStore: any ReadingProgressStoring = FileReadingProgressStore(
        fileURL: ReaderViewModel.progressFileURL(
            applicationSupportDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
        )
    )

    static let readerModel = ReaderViewModel(
        loader: PDFDocumentLoader(),
        progressStore: progressStore
    )

    static let sidebarModel = DirectorySidebarViewModel(progressStore: progressStore)
}

@MainActor
final class PDFComicViewerAppDelegate: NSObject, NSApplicationDelegate {
    private let terminationCoordinator = ApplicationTerminationCoordinator()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        _ = terminationCoordinator.requestTermination(
            flush: {
                await AppServices.readerModel.flushPendingSaves()
            },
            reply: { shouldTerminate in
                sender.reply(toApplicationShouldTerminate: shouldTerminate)
            }
        )
        return .terminateLater
    }
}

@main
struct PDFComicViewerApp: App {
    @NSApplicationDelegateAdaptor(PDFComicViewerAppDelegate.self) private var appDelegate
    @StateObject private var model: ReaderViewModel
    @StateObject private var sidebarModel: DirectorySidebarViewModel

    init() {
        _model = StateObject(wrappedValue: AppServices.readerModel)
        _sidebarModel = StateObject(wrappedValue: AppServices.sidebarModel)
    }

    var body: some Scene {
        WindowGroup(AppConfiguration.applicationName) {
            ReaderView(model: model, sidebarModel: sidebarModel)
                .frame(minWidth: 900, minHeight: 650)
                .onOpenURL { url in
                    Task { await model.openExternalURL(url) }
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            ReaderCommands(model: model)
        }
    }
}

@MainActor
struct ReaderCommands: Commands {
    @ObservedObject var model: ReaderViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("PDFを開く…") {
                model.requestFileOpen()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("PDFを閉じる") {
                Task { await model.closeDocument() }
            }
            .disabled(model.session == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("拡大") {
                model.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(model.session == nil)

            Button("縮小") {
                model.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(model.session == nil)

            Button("ウインドウに合わせる") {
                model.fitToWindow()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(model.session == nil)

            Divider()

            Button(model.sidebarIsVisible ? "サイドバーを隠す" : "サイドバーを表示") {
                model.sidebarIsVisible.toggle()
            }
            .keyboardShortcut("b", modifiers: .command)

            Divider()

            Button("全画面表示を切り替える") {
                model.requestFullScreenToggle()
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
}
