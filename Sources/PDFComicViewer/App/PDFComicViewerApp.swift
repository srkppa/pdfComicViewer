import SwiftUI

@main
struct PDFComicViewerApp: App {
    @StateObject private var model = ReaderViewModel.live()

    var body: some Scene {
        WindowGroup(AppConfiguration.applicationName) {
            ReaderView(model: model)
                .frame(minWidth: 900, minHeight: 650)
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
