import Foundation
import PDFKit

@MainActor
protocol PDFDocumentLoading {
    func open(url: URL) async throws -> PDFOpenResult
    func unlock(_ locked: LockedPDFDocument, password: String) throws -> DocumentSession
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
    let document: PDFDocument
    let url: URL
    let metadata: FileMetadata
}

@MainActor
enum PDFOpenResult {
    case ready(DocumentSession)
    case passwordRequired(LockedPDFDocument)
}

@MainActor
struct PDFDocumentLoader: PDFDocumentLoading {
    func open(url: URL) async throws -> PDFOpenResult {
        let loadedFile = try await Task.detached(priority: .userInitiated) {
            try LoadedPDFFile.read(from: url)
        }.value

        guard let document = PDFDocument(data: loadedFile.data) else {
            throw PDFLoaderError.invalidPDF
        }
        if document.isLocked {
            return .passwordRequired(
                LockedPDFDocument(
                    document: document,
                    url: url,
                    metadata: loadedFile.metadata
                )
            )
        }
        guard document.pageCount > 0 else {
            throw PDFLoaderError.invalidPDF
        }

        let pages = try await pageGeometries(in: document)
        return .ready(
            DocumentSession(
                document: document,
                url: url,
                pages: pages,
                metadata: loadedFile.metadata
            )
        )
    }

    func unlock(_ locked: LockedPDFDocument, password: String) throws -> DocumentSession {
        guard locked.document.unlock(withPassword: password) else {
            throw PDFLoaderError.incorrectPassword
        }
        guard locked.document.pageCount > 0 else {
            throw PDFLoaderError.invalidPDF
        }

        return DocumentSession(
            document: locked.document,
            url: locked.url,
            pages: try pageGeometriesSynchronously(in: locked.document),
            metadata: locked.metadata
        )
    }

    private func pageGeometries(in document: PDFDocument) async throws -> [PageGeometry] {
        var pages: [PageGeometry] = []
        pages.reserveCapacity(document.pageCount)

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                throw PDFLoaderError.invalidPDF
            }
            let bounds = page.bounds(for: .cropBox)
            pages.append(PageGeometry(width: bounds.width, height: bounds.height))

            if (index + 1).isMultiple(of: 32) {
                await Task.yield()
            }
        }
        return pages
    }

    private func pageGeometriesSynchronously(
        in document: PDFDocument
    ) throws -> [PageGeometry] {
        try (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else {
                throw PDFLoaderError.invalidPDF
            }
            let bounds = page.bounds(for: .cropBox)
            return PageGeometry(width: bounds.width, height: bounds.height)
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
