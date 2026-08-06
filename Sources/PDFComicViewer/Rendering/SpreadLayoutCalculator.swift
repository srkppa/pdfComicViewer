import CoreGraphics

enum SpreadLayoutCalculator {
    static func frames(
        pageSizes: [CGSize],
        viewport: CGSize,
        gutter: CGFloat
    ) -> [CGRect] {
        guard !pageSizes.isEmpty else { return [] }

        let totalGutter = gutter * CGFloat(max(0, pageSizes.count - 1))
        let totalNaturalWidth = pageSizes.reduce(0) { $0 + $1.width }
        let maximumNaturalHeight = pageSizes.map(\.height).max() ?? 1
        let scale = min(
            (viewport.width - totalGutter) / totalNaturalWidth,
            viewport.height / maximumNaturalHeight
        )
        let totalWidth = pageSizes.reduce(0) { $0 + $1.width * scale }
            + totalGutter

        var x = (viewport.width - totalWidth) / 2
        return pageSizes.map { pageSize in
            let scaledSize = CGSize(
                width: pageSize.width * scale,
                height: pageSize.height * scale
            )
            defer { x += scaledSize.width + gutter }
            return CGRect(
                x: x,
                y: (viewport.height - scaledSize.height) / 2,
                width: scaledSize.width,
                height: scaledSize.height
            )
        }
    }
}
