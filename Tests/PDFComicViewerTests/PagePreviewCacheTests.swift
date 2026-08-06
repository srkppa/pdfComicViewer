import CoreGraphics
import XCTest
@testable import PDFComicViewer

final class PagePreviewCacheTests: XCTestCase {
    func testRetainsOnlyRequestedNeighborPages() async {
        let cache = PagePreviewCache()
        await cache.insert(makeImage(gray: 0), for: 0)
        await cache.insert(makeImage(gray: 1), for: 1)
        await cache.insert(makeImage(gray: 2), for: 2)

        await cache.retainOnly([1, 2])

        let removedImage = await cache.image(for: 0)
        let firstRetainedImage = await cache.image(for: 1)
        let secondRetainedImage = await cache.image(for: 2)

        XCTAssertNil(removedImage)
        XCTAssertNotNil(firstRetainedImage)
        XCTAssertNotNil(secondRetainedImage)
    }

    func testInsertReplacesExistingPagePreview() async {
        let cache = PagePreviewCache()
        await cache.insert(makeImage(gray: 0), for: 1)
        await cache.insert(makeImage(gray: 255), for: 1)

        let image = await cache.image(for: 1)

        XCTAssertEqual(try? XCTUnwrap(image).grayValue, 255)
    }

    func testRetainingNoPagesEmptiesCache() async {
        let cache = PagePreviewCache()
        await cache.insert(makeImage(gray: 0), for: 0)
        await cache.insert(makeImage(gray: 1), for: 1)

        await cache.retainOnly([])

        let firstImage = await cache.image(for: 0)
        let secondImage = await cache.image(for: 1)
        XCTAssertNil(firstImage)
        XCTAssertNil(secondImage)
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
}

private extension CGImage {
    var grayValue: UInt8? {
        guard let data = dataProvider?.data else { return nil }
        return CFDataGetBytePtr(data)?[0]
    }
}
