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
