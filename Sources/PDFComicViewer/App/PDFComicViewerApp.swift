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
private enum AppServices {
    static let readerModel = ReaderViewModel.live()
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

    init() {
        _model = StateObject(wrappedValue: AppServices.readerModel)
    }

    var body: some Scene {
        WindowGroup(AppConfiguration.applicationName) {
            ReaderView(model: model)
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

            Button("全画面表示を切り替える") {
                model.requestFullScreenToggle()
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
}
