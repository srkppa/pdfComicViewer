import CoreGraphics
import XCTest
@testable import PDFComicViewer

final class PagePreviewCacheTests: XCTestCase {
    func testRetainsOnlyRequestedNeighborPages() async {
        let cache = PagePreviewCache()
        let generation = makeGeneration(sequence: 1)
        await cache.beginGeneration(generation, allowedIndexes: [1, 2])
        _ = await cache.insert(makeImage(gray: 0), for: 0, generation: generation)
        _ = await cache.insert(makeImage(gray: 1), for: 1, generation: generation)
        _ = await cache.insert(makeImage(gray: 2), for: 2, generation: generation)

        let removedImage = await cache.image(for: 0, generation: generation)
        let firstRetainedImage = await cache.image(for: 1, generation: generation)
        let secondRetainedImage = await cache.image(for: 2, generation: generation)

        XCTAssertNil(removedImage)
        XCTAssertNotNil(firstRetainedImage)
        XCTAssertNotNil(secondRetainedImage)
    }

    func testInsertReplacesExistingPagePreview() async {
        let cache = PagePreviewCache()
        let generation = makeGeneration(sequence: 1)
        await cache.beginGeneration(generation, allowedIndexes: [1])
        _ = await cache.insert(makeImage(gray: 0), for: 1, generation: generation)
        _ = await cache.insert(makeImage(gray: 255), for: 1, generation: generation)

        let image = await cache.image(for: 1, generation: generation)

        XCTAssertEqual(try? XCTUnwrap(image).grayValue, 255)
    }

    func testRetainingNoPagesEmptiesCache() async {
        let cache = PagePreviewCache()
        let documentID = UUID()
        let firstGeneration = makeGeneration(documentID: documentID, sequence: 1)
        let emptyGeneration = makeGeneration(documentID: documentID, sequence: 2)
        await cache.beginGeneration(firstGeneration, allowedIndexes: [0, 1])
        _ = await cache.insert(makeImage(gray: 0), for: 0, generation: firstGeneration)
        _ = await cache.insert(makeImage(gray: 1), for: 1, generation: firstGeneration)
        await cache.beginGeneration(emptyGeneration, allowedIndexes: [])

        let firstImage = await cache.image(for: 0, generation: emptyGeneration)
        let secondImage = await cache.image(for: 1, generation: emptyGeneration)
        XCTAssertNil(firstImage)
        XCTAssertNil(secondImage)
    }

    func testStaleGenerationInsertIsRejected() async {
        let cache = PagePreviewCache()
        let documentID = UUID()
        let staleGeneration = makeGeneration(documentID: documentID, sequence: 1)
        let currentGeneration = makeGeneration(documentID: documentID, sequence: 2)
        await cache.beginGeneration(staleGeneration, allowedIndexes: [0, 1])
        await cache.beginGeneration(currentGeneration, allowedIndexes: [1, 2])

        let wasInserted = await cache.insert(
            makeImage(gray: 0),
            for: 1,
            generation: staleGeneration
        )

        XCTAssertFalse(wasInserted)
        let staleImage = await cache.image(for: 1, generation: currentGeneration)
        XCTAssertNil(staleImage)
    }

    func testStaleGenerationBeginDoesNotDiscardCurrentImages() async {
        let cache = PagePreviewCache()
        let documentID = UUID()
        let staleGeneration = makeGeneration(documentID: documentID, sequence: 1)
        let currentGeneration = makeGeneration(documentID: documentID, sequence: 2)
        await cache.beginGeneration(staleGeneration, allowedIndexes: [0, 1])
        await cache.beginGeneration(currentGeneration, allowedIndexes: [1, 2])
        _ = await cache.insert(makeImage(gray: 255), for: 1, generation: currentGeneration)

        await cache.beginGeneration(staleGeneration, allowedIndexes: [])

        let currentImage = await cache.image(for: 1, generation: currentGeneration)
        XCTAssertEqual(try? XCTUnwrap(currentImage).grayValue, 255)
    }

    func testDocumentSwitchDoesNotReuseSameIndexImage() async {
        let cache = PagePreviewCache()
        let oldGeneration = makeGeneration(documentID: UUID(), sequence: 1)
        let newGeneration = makeGeneration(documentID: UUID(), sequence: 2)
        await cache.beginGeneration(oldGeneration, allowedIndexes: [0])
        _ = await cache.insert(makeImage(gray: 0), for: 0, generation: oldGeneration)

        await cache.beginGeneration(newGeneration, allowedIndexes: [0])

        let newDocumentImage = await cache.image(for: 0, generation: newGeneration)
        XCTAssertNil(newDocumentImage)
    }

    private func makeImage(gray: UInt8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 1,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: CGFloat(gray) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }

    private func makeGeneration(
        documentID: UUID = UUID(),
        sequence: Int
    ) -> PagePreviewGeneration {
        PagePreviewGeneration(documentID: documentID, sequence: sequence)
    }
}

private extension CGImage {
    var grayValue: UInt8? {
        guard let data = dataProvider?.data else { return nil }
        return CFDataGetBytePtr(data)?[0]
    }
}
