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

    /// `unitIndex` の単位が属する「見開きが連続している区間」の先頭ページ。
    ///
    /// 組み合わせをずらすには、いま見ているページ自身を単独にするのではなく、
    /// その区間の先頭に空きを入れる必要がある。自分を単独にすると、そのページが
    /// 孤立するだけで、見えている組み合わせは変わらないため。
    static func pairRunStartPage(units: [DisplayUnit], unitIndex: Int) -> Int? {
        guard units.indices.contains(unitIndex) else { return nil }
        var index = unitIndex
        while index > 0, units[index].isPair, units[index - 1].isPair {
            index -= 1
        }
        return units[index].anchorPage
    }

    /// 見開き位置のずらしが、実際に組み合わせを変えられるかどうか。
    ///
    /// ずらしは起点ページを単独にするかどうかの切り替えでしかないので、
    /// その起点に組む相手がいなければ、切り替えても結果は同じになる
    /// （相手が横長だったり「単独」指定されていたりする場合）。
    /// 押しても何も起きない操作を押させないための判定。
    static func alignmentToggleChangesLayout(
        pages: [PageGeometry],
        overrides: [Int: PageLayoutOverride]
    ) -> Bool {
        guard let anchor = firstPairableIndex(pages: pages, overrides: overrides),
              pages.indices.contains(anchor + 1) else { return false }
        return canPair(index: anchor + 1, pages: pages, overrides: overrides)
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
        pages.indices.first { canPair(index: $0, pages: pages, overrides: overrides) }
    }

    /// そのページを隣と対にできるか。「単独」指定と横長ページは対にできない。
    private static func canPair(
        index: Int,
        pages: [PageGeometry],
        overrides: [Int: PageLayoutOverride]
    ) -> Bool {
        switch overrides[index] ?? .automatic {
        case .single:
            false
        case .pairable:
            true
        case .automatic:
            pages[index].width <= pages[index].height
        }
    }
}
