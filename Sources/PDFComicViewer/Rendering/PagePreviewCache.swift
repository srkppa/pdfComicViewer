import AppKit
import PDFKit

struct PagePreviewGeneration: Equatable, Sendable {
    let documentID: UUID
    let sequence: Int
}

struct PagePreviewSnapshot {
    let generation: PagePreviewGeneration?
    let revision: Int
    let images: [Int: CGImage]

    var pageIndexes: [Int] {
        images.keys.sorted()
    }

    static let empty = Self(generation: nil, revision: 0, images: [:])
}

actor PagePreviewCache {
    private var images: [Int: CGImage] = [:]
    private var currentGeneration: PagePreviewGeneration?
    private var allowedIndexes: Set<Int> = []

    func beginGeneration(
        _ generation: PagePreviewGeneration,
        allowedIndexes: Set<Int>
    ) {
        guard currentGeneration.map({ generation.sequence > $0.sequence }) ?? true else {
            return
        }
        if currentGeneration?.documentID != generation.documentID {
            images = [:]
        }
        currentGeneration = generation
        self.allowedIndexes = allowedIndexes
        images = images.filter { allowedIndexes.contains($0.key) }
    }

    func insert(
        _ image: CGImage,
        for pageIndex: Int,
        generation: PagePreviewGeneration
    ) -> Bool {
        guard generation == currentGeneration,
              allowedIndexes.contains(pageIndex) else {
            return false
        }
        images[pageIndex] = image
        return true
    }

    func image(
        for pageIndex: Int,
        generation: PagePreviewGeneration
    ) -> CGImage? {
        guard generation == currentGeneration,
              allowedIndexes.contains(pageIndex) else {
            return nil
        }
        return images[pageIndex]
    }

    func snapshot(
        for pageIndexes: Set<Int>,
        generation: PagePreviewGeneration
    ) -> [Int: CGImage] {
        guard generation == currentGeneration else { return [:] }
        return images.filter { pageIndexes.contains($0.key) }
    }
}

@MainActor
enum PagePreviewRenderer {
    static func render(page: PDFPage, maxSize: CGSize) -> CGImage? {
        let thumbnail = page.thumbnail(of: maxSize, for: .cropBox)
        return thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
