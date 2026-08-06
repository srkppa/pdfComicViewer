import Foundation
import PDFKit

@MainActor
final class DocumentSession {
    let document: PDFDocument
    let url: URL
    let pages: [PageGeometry]
    let metadata: FileMetadata

    init(document: PDFDocument, url: URL, pages: [PageGeometry], metadata: FileMetadata) {
        self.document = document
        self.url = url
        self.pages = pages
        self.metadata = metadata
    }
}
