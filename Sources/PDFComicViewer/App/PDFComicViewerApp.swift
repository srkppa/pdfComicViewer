import SwiftUI

@main
struct PDFComicViewerApp: App {
    var body: some Scene {
        WindowGroup(AppConfiguration.applicationName) {
            Text("PDFを開いてください")
                .frame(minWidth: 900, minHeight: 650)
        }
    }
}
