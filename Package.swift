// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PDFComicViewer",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "PDFComicViewer", targets: ["PDFComicViewer"])],
    targets: [
        .executableTarget(name: "PDFComicViewer"),
        .testTarget(name: "PDFComicViewerTests", dependencies: ["PDFComicViewer"])
    ]
)
