import CoreGraphics
import Darwin
import Foundation
import PDFKit

@MainActor
protocol PDFDocumentLoading {
    func open(url: URL) async throws -> PDFOpenResult
    func unlock(_ locked: LockedPDFDocument, password: String) async throws -> DocumentSession
}

enum PDFLoaderError: LocalizedError {
    case unreadableFile
    case invalidPDF
    case incorrectPassword

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "PDFファイルを読み込めません。"
        case .invalidPDF:
            "有効なPDFファイルではありません。"
        case .incorrectPassword:
            "パスワードが正しくありません。"
        }
    }
}

@MainActor
struct LockedPDFDocument {
    fileprivate let data: Data
    let url: URL
    let metadata: FileMetadata

    init(data: Data, url: URL, metadata: FileMetadata) {
        self.data = data
        self.url = url
        self.metadata = metadata
    }
}

@MainActor
enum PDFOpenResult {
    case ready(DocumentSession)
    case passwordRequired(LockedPDFDocument)
}

enum PDFPageGeometry {
    static func displayed(cropBox: CGRect, rotation: Int) -> PageGeometry {
        let normalizedRotation = (rotation % 360 + 360) % 360
        if normalizedRotation == 90 || normalizedRotation == 270 {
            return PageGeometry(width: cropBox.height, height: cropBox.width)
        }
        return PageGeometry(width: cropBox.width, height: cropBox.height)
    }
}

@MainActor
struct PDFDocumentLoader: PDFDocumentLoading {
    private let workerExecutionObserver: (@Sendable (Bool) -> Void)?

    init(workerExecutionObserver: (@Sendable (Bool) -> Void)? = nil) {
        self.workerExecutionObserver = workerExecutionObserver
    }

    func open(url: URL) async throws -> PDFOpenResult {
        let observer = workerExecutionObserver
        let loaded = try await Task.detached(priority: .userInitiated) {
            observer?(pthread_main_np() != 0)
            let file = try LoadedPDFFile.read(from: url)
            let parsed = try PDFBackgroundParser.open(data: file.data)
            return LoadedPDF(file: file, parsed: parsed)
        }.value

        switch loaded.parsed {
        case .locked:
            return .passwordRequired(
                LockedPDFDocument(
                    data: loaded.file.data,
                    url: url,
                    metadata: loaded.file.metadata
                )
            )
        case .ready(let transferredDocument, let pages):
            return .ready(
                DocumentSession(
                    document: transferredDocument.document,
                    url: url,
                    pages: pages,
                    metadata: loaded.file.metadata
                )
            )
        }
    }

    func unlock(
        _ locked: LockedPDFDocument,
        password: String
    ) async throws -> DocumentSession {
        let data = locked.data
        let observer = workerExecutionObserver
        let parsed = try await Task.detached(priority: .userInitiated) {
            observer?(pthread_main_np() != 0)
            return try PDFBackgroundParser.unlock(data: data, password: password)
        }.value
        return DocumentSession(
            document: parsed.document.document,
            url: locked.url,
            pages: parsed.pages,
            metadata: locked.metadata
        )
    }
}

/// バックグラウンド解析完了後にPDFKit文書の所有権をMainActorへ一度だけ渡す箱。
/// 解析側はこの箱を返した後に文書へ触れず、以後は表示側だけが利用する。
private final class TransferredPDFDocument: @unchecked Sendable {
    let document: PDFDocument

    init(_ document: PDFDocument) {
        self.document = document
    }
}

private enum BackgroundPDFOpenResult: Sendable {
    case locked
    case ready(TransferredPDFDocument, [PageGeometry])
}

private struct BackgroundUnlockedPDF: Sendable {
    let document: TransferredPDFDocument
    let pages: [PageGeometry]
}

private struct LoadedPDF: Sendable {
    let file: LoadedPDFFile
    let parsed: BackgroundPDFOpenResult
}

private enum PDFBackgroundParser {
    static func open(data: Data) throws -> BackgroundPDFOpenResult {
        guard let document = PDFDocument(data: data) else {
            throw PDFLoaderError.invalidPDF
        }
        if document.isLocked {
            return .locked
        }
        let pages = try pageGeometries(data: data, password: nil)
        guard document.pageCount > 0, document.pageCount == pages.count else {
            throw PDFLoaderError.invalidPDF
        }
        return .ready(TransferredPDFDocument(document), pages)
    }

    static func unlock(data: Data, password: String) throws -> BackgroundUnlockedPDF {
        guard let document = PDFDocument(data: data),
              document.unlock(withPassword: password) else {
            throw PDFLoaderError.incorrectPassword
        }
        let pages = try pageGeometries(data: data, password: password)
        guard document.pageCount > 0, document.pageCount == pages.count else {
            throw PDFLoaderError.invalidPDF
        }
        return BackgroundUnlockedPDF(
            document: TransferredPDFDocument(document),
            pages: pages
        )
    }

    private static func pageGeometries(
        data: Data,
        password: String?
    ) throws -> [PageGeometry] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            throw PDFLoaderError.invalidPDF
        }
        if document.isEncrypted {
            guard let password, document.unlockWithPassword(password) else {
                throw PDFLoaderError.incorrectPassword
            }
        }
        guard document.isUnlocked, document.numberOfPages > 0 else {
            throw PDFLoaderError.invalidPDF
        }

        return try (1...document.numberOfPages).map { pageNumber in
            guard let page = document.page(at: pageNumber) else {
                throw PDFLoaderError.invalidPDF
            }
            return PDFPageGeometry.displayed(
                cropBox: page.getBoxRect(.cropBox),
                rotation: Int(page.rotationAngle)
            )
        }
    }
}

private struct LoadedPDFFile: Sendable {
    let data: Data
    let metadata: FileMetadata

    static func read(from url: URL) throws -> Self {
        do {
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey
            ])
            guard let fileSize = values.fileSize,
                  let modificationDate = values.contentModificationDate else {
                throw PDFLoaderError.unreadableFile
            }
            return Self(
                data: try Data(contentsOf: url, options: .mappedIfSafe),
                metadata: FileMetadata(
                    size: Int64(fileSize),
                    modificationDate: modificationDate
                )
            )
        } catch let error as PDFLoaderError {
            throw error
        } catch {
            throw PDFLoaderError.unreadableFile
        }
    }
}
