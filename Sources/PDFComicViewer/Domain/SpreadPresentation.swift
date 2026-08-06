enum SpreadPresentation {
    static func placement(for unit: DisplayUnit, binding: BindingDirection) -> PagePlacement {
        switch unit {
        case .single(let page):
            .init(left: nil, right: nil, centered: page)
        case .pair(let earlier, let later):
            binding == .right
                ? .init(left: later, right: earlier, centered: nil)
                : .init(left: earlier, right: later, centered: nil)
        }
    }

    static func unitIndex(containing page: Int, in units: [DisplayUnit]) -> Int? {
        units.firstIndex { unit in
            switch unit {
            case .single(let value):
                value == page
            case .pair(let first, let second):
                first == page || second == page
            }
        }
    }
}
