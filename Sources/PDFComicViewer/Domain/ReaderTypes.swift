import Foundation

enum AppConfiguration {
    static let applicationName = "PDF漫画ビューアー"
}

enum DisplayMode: String, Codable, Sendable {
    case single
    case spread
}

enum PairingAlignment: String, Codable, Sendable {
    case coverSingle
    case shifted
}

enum BindingDirection: String, Codable, Sendable {
    case right
    case left
}

enum PageLayoutOverride: String, Codable, Sendable {
    case automatic
    case single
    case pairable
}

struct DocumentPreferences: Codable, Equatable, Sendable {
    var lastPageIndex: Int
    var binding: BindingDirection
    var displayMode: DisplayMode
    var alignment: PairingAlignment
    var pageOverrides: [Int: PageLayoutOverride]

    static let defaults = Self(
        lastPageIndex: 0,
        binding: .right,
        displayMode: .spread,
        alignment: .coverSingle,
        pageOverrides: [:]
    )
}

struct FileMetadata: Codable, Equatable, Sendable {
    let size: Int64
    let modificationDate: Date
}

struct DocumentRecord: Codable, Equatable, Sendable {
    var bookmarkData: Data
    var normalizedPath: String
    var metadata: FileMetadata
    var preferences: DocumentPreferences
}

struct PageGeometry: Equatable, Sendable {
    let width: Double
    let height: Double
}

enum DisplayUnit: Equatable, Sendable {
    case single(Int)
    case pair(Int, Int)
}

struct PagePlacement: Equatable, Sendable {
    let left: Int?
    let right: Int?
    let centered: Int?
}

extension DisplayUnit {
    var pageIndexes: [Int] {
        switch self {
        case .single(let page):
            [page]
        case .pair(let first, let second):
            [first, second]
        }
    }

    var anchorPage: Int {
        pageIndexes[0]
    }
}
