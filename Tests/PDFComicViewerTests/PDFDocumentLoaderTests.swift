import CoreGraphics
import PDFKit
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

    func testEmptyPDFIsRejected() async throws {
        let url = try PDFFixtureFactory.makePDF(pageSizes: [])
        defer { try? FileManager.default.removeItem(at: url) }
        let loader = PDFDocumentLoader(documentFactory: { _ in PDFDocument() })

        do {
            _ = try await loader.open(url: url)
            XCTFail("emptyPDFを期待")
        } catch PDFLoaderError.emptyPDF {
        } catch {
            XCTFail("emptyPDFを期待、実際は\(error)")
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

        let session = try PDFDocumentLoader().unlock(locked, password: "secret")

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
            _ = try PDFDocumentLoader().unlock(locked, password: "wrong")
            XCTFail("incorrectPasswordを期待")
        } catch PDFLoaderError.incorrectPassword {
        } catch {
            XCTFail("incorrectPasswordを期待、実際は\(error)")
        }
    }
}
