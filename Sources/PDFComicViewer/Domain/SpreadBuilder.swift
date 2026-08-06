enum SpreadBuilder {
    static func build(
        pages: [PageGeometry],
        mode: DisplayMode,
        alignment: PairingAlignment,
        overrides: [Int: PageLayoutOverride]
    ) -> [DisplayUnit] {
        guard mode == .spread else {
            return pages.indices.map(DisplayUnit.single)
        }

        var result: [DisplayUnit] = []
        var pending: Int?

        for index in pages.indices {
            let override = overrides[index] ?? .automatic
            let automaticSingle =
                (index == 0 && alignment == .coverSingle) ||
                pages[index].width > pages[index].height
            let mustBeSingle = override == .single ||
                (override == .automatic && automaticSingle)

            if mustBeSingle {
                if let pending {
                    result.append(.single(pending))
                }
                pending = nil
                result.append(.single(index))
            } else if let first = pending {
                result.append(.pair(first, index))
                pending = nil
            } else {
                pending = index
            }
        }

        if let pending {
            result.append(.single(pending))
        }

        return result
    }
}
