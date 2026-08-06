import CoreGraphics
import XCTest
@testable import PDFComicViewer

@MainActor
final class PDFDocumentLoaderTests: XCTestCase {
    func testOpensPDFAndReadsCropBoxGeometry() async throws {
        let cropBox = CGRect(x: 10, y: 20, width: 580, height: 860)
        let url = try PDFFixtureFactory.makePDF(
            pageSizes: [CGSize(width: 600, height: 900)],
            cropBoxes: [cropBox]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await PDFDocumentLoader().open(url: url)

        guard case .ready(let session) = result else {
            return XCTFail("readyを期待")
        }
        XCTAssertEqual(session.url, url)
        XCTAssertEqual(session.pages, [.init(width: 580, height: 860)])
    }

    func testPreservesPortraitAndLandscapePageOrder() async throws {
        let url = try PDFFixtureFactory.makePDF(pageSizes: [
            CGSize(width: 600, height: 900),
            CGSize(width: 1_200, height: 800),
            CGSize(width: 700, height: 1_000)
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await PDFDocumentLoader().open(url: url)

        guard case .ready(let session) = result else {
            return XCTFail("readyを期待")
        }
        XCTAssertEqual(session.pages, [
            .init(width: 600, height: 900),
            .init(width: 1_200, height: 800),
            .init(width: 700, height: 1_000)
        ])
    }

    func testRotationSwapsDisplayedCropBoxDimensions() async throws {
        XCTAssertEqual(
            PDFPageGeometry.displayed(
                cropBox: CGRect(x: 0, y: 0, width: 600, height: 900),
                rotation: 90
            ),
            PageGeometry(width: 900, height: 600)
        )
        XCTAssertEqual(
            PDFPageGeometry.displayed(
                cropBox: CGRect(x: 0, y: 0, width: 1_200, height: 800),
                rotation: 270
            ),
            PageGeometry(width: 800, height: 1_200)
        )
    }

    func testReadsRotatedPageAsDisplayedLandscapeGeometry() async throws {
        let url = try PDFFixtureFactory.makePDF(
            pageSizes: [CGSize(width: 600, height: 900)],
            rotations: [90]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await PDFDocumentLoader().open(url: url)

        guard case .ready(let session) = result else {
            return XCTFail("readyを期待")
        }
        XCTAssertEqual(session.pages, [.init(width: 900, height: 600)])
    }

    func testCapturesFileMetadata() async throws {
        let url = try PDFFixtureFactory.makePDF(
            pageSizes: [CGSize(width: 600, height: 900)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        let result = try await PDFDocumentLoader().open(url: url)

        guard case .ready(let session) = result else {
            return XCTFail("readyを期待")
        }
        XCTAssertEqual(session.metadata.size, Int64(try XCTUnwrap(values.fileSize)))
        XCTAssertEqual(
            session.metadata.modificationDate,
            try XCTUnwrap(values.contentModificationDate)
        )
    }

    func testDocumentConstructionAndGeometryParsingRunOffMainThread() async throws {
        let url = try PDFFixtureFactory.makePDF(
            pageSizes: Array(repeating: CGSize(width: 600, height: 900), count: 40)
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = WorkerExecutionRecorder()
        let loader = PDFDocumentLoader { isMainThread in
            recorder.record(isMainThread: isMainThread)
        }

        _ = try await loader.open(url: url)

        XCTAssertEqual(recorder.values, [false])
    }

    func testEmptyFileIsRejectedAsInvalidPDF() async throws {
        let url = try PDFFixtureFactory.makeEmptyFile()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await PDFDocumentLoader().open(url: url)
            XCTFail("invalidPDFを期待")
        } catch PDFLoaderError.invalidPDF {
        } catch {
            XCTFail("invalidPDFを期待、実際は\(error)")
        }
    }

    func testCorruptFileIsRejected() async throws {
        let url = try PDFFixtureFactory.makeCorruptFile()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await PDFDocumentLoader().open(url: url)
            XCTFail("invalidPDFを期待")
        } catch PDFLoaderError.invalidPDF {
        } catch {
            XCTFail("invalidPDFを期待、実際は\(error)")
        }
    }

    func testUnreadableFileIsRejected() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).pdf")

        do {
            _ = try await PDFDocumentLoader().open(url: url)
            XCTFail("unreadableFileを期待")
        } catch PDFLoaderError.unreadableFile {
        } catch {
            XCTFail("unreadableFileを期待、実際は\(error)")
        }
    }

    func testLockedPDFRequestsPasswordAndUnlocks() async throws {
        let url = try PDFFixtureFactory.makeEncryptedPDF(password: "secret")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await PDFDocumentLoader().open(url: url)
        guard case .passwordRequired(let locked) = result else {
            return XCTFail("passwordRequiredを期待")
        }

        let session = try await PDFDocumentLoader().unlock(locked, password: "secret")

        XCTAssertEqual(session.document.pageCount, 1)
        XCTAssertEqual(session.pages, [.init(width: 600, height: 900)])
        XCTAssertEqual(session.url, url)
    }

    func testIncorrectPasswordIsRejected() async throws {
        let url = try PDFFixtureFactory.makeEncryptedPDF(password: "secret")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await PDFDocumentLoader().open(url: url)
        guard case .passwordRequired(let locked) = result else {
            return XCTFail("passwordRequiredを期待")
        }

        do {
            _ = try await PDFDocumentLoader().unlock(locked, password: "wrong")
            XCTFail("incorrectPasswordを期待")
        } catch PDFLoaderError.incorrectPassword {
        } catch {
            XCTFail("incorrectPasswordを期待、実際は\(error)")
        }
    }
}

private final class WorkerExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Bool] = []

    var values: [Bool] {
        lock.withLock { storedValues }
    }

    func record(isMainThread: Bool) {
        lock.withLock { storedValues.append(isMainThread) }
    }
}
