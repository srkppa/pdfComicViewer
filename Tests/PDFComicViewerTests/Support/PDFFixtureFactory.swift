import CoreGraphics
import Foundation

enum PDFFixtureFactoryError: Error {
    case couldNotCreateConsumer
    case couldNotCreateContext
}

enum PDFFixtureFactory {
    static func makePDF(
        pageSizes: [CGSize],
        cropBoxes: [CGRect]? = nil,
        password: String? = nil
    ) throws -> URL {
        let url = temporaryURL()
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw PDFFixtureFactoryError.couldNotCreateConsumer
        }

        var auxiliaryInfo: [CFString: Any] = [:]
        if let password {
            auxiliaryInfo[kCGPDFContextUserPassword] = password as CFString
            auxiliaryInfo[kCGPDFContextOwnerPassword] = "owner-\(password)" as CFString
        }

        guard let context = CGContext(
            consumer: consumer,
            mediaBox: nil,
            auxiliaryInfo as CFDictionary
        ) else {
            throw PDFFixtureFactoryError.couldNotCreateContext
        }

        for (index, pageSize) in pageSizes.enumerated() {
            var mediaBox = CGRect(origin: .zero, size: pageSize)
            var pageInfo: [CFString: Any] = [
                kCGPDFContextMediaBox: Data(
                    bytes: &mediaBox,
                    count: MemoryLayout<CGRect>.size
                ) as CFData
            ]
            if let cropBox = cropBoxes?[index] {
                var cropBox = cropBox
                pageInfo[kCGPDFContextCropBox] = Data(
                    bytes: &cropBox,
                    count: MemoryLayout<CGRect>.size
                ) as CFData
            }
            context.beginPDFPage(pageInfo as CFDictionary)
            context.endPDFPage()
        }

        context.closePDF()
        return url
    }

    static func makeEncryptedPDF(password: String) throws -> URL {
        try makePDF(
            pageSizes: [CGSize(width: 600, height: 900)],
            password: password
        )
    }

    static func makeCorruptFile() throws -> URL {
        let url = temporaryURL()
        try Data("not a PDF".utf8).write(to: url)
        return url
    }

    static func makeEmptyFile() throws -> URL {
        let url = temporaryURL()
        try Data().write(to: url)
        return url
    }

    private static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "PDFDocumentLoaderTests-\(UUID().uuidString).pdf")
    }
}
