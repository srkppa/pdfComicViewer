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

        let anchorIndex = firstPairableIndex(pages: pages, overrides: overrides)
        var result: [DisplayUnit] = []
        var pending: Int?

        for index in pages.indices {
            let override = overrides[index] ?? .automatic
            let automaticSingle =
                (index == anchorIndex && alignment == .coverSingle) ||
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

    /// ずらしの起点になるページ。
    ///
    /// 見開き位置のずらしは「対にできるページ列の先頭を単独にするかどうか」で
    /// 表現している。これを物理的な1ページ目に固定すると、表紙が横長だったり
    /// 「単独」指定されていたりするPDFでは、そのページが先に単独へ確定して
    /// しまい、切り替えても組み合わせが一切変わらなくなる。そのため、実際に
    /// 対にできる最初のページを起点にする。対にできるページが1つも無ければ
    /// `nil`（どのみち全ページ単独なのでずらす余地が無い）。
    private static func firstPairableIndex(
        pages: [PageGeometry],
        overrides: [Int: PageLayoutOverride]
    ) -> Int? {
        pages.indices.first { index in
            switch overrides[index] ?? .automatic {
            case .single:
                return false
            case .pairable:
                return true
            case .automatic:
                return pages[index].width <= pages[index].height
            }
        }
    }
}
