import Foundation

protocol ReadingProgressStoring: Sendable {
    func load(for url: URL) async throws -> DocumentRecord?
    func save(_ record: DocumentRecord) async throws
    func allRecords() async throws -> [DocumentRecord]
}

enum DocumentBookmarkService {
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) throws -> URL {
        var stale = false
        return try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}

actor FileReadingProgressStore: ReadingProgressStoring {
    private let fileURL: URL
    private var records: [DocumentRecord]?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load(for url: URL) throws -> DocumentRecord? {
        let target = url.standardizedFileURL
        return try loadRecords().first { record in
            if let resolved = try? DocumentBookmarkService.resolve(record.bookmarkData),
               resolved.standardizedFileURL == target {
                return true
            }
            return record.normalizedPath == target.path
        }
    }

    func save(_ record: DocumentRecord) throws {
        var values = try loadRecords()
        values.removeAll { $0.normalizedPath == record.normalizedPath }
        values.append(record)

        let data = try JSONEncoder().encode(values)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        records = values
    }

    func allRecords() throws -> [DocumentRecord] {
        try loadRecords()
    }

    private func loadRecords() throws -> [DocumentRecord] {
        if let records {
            return records
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return []
        }

        let decoded = try JSONDecoder().decode(
            [DocumentRecord].self,
            from: Data(contentsOf: fileURL)
        )
        records = decoded
        return decoded
    }
}
