import Foundation

/// シークバーのスライダー値と表示単位インデックスを相互変換する。
/// 綴じ方向による左右反転をここに閉じ込め、View側に条件分岐を散らさない。
enum SeekBarPresentation {
    /// 表示単位インデックス → スライダー値。右綴じでは左右を反転する。
    static func sliderValue(
        unitIndex: Int,
        unitCount: Int,
        binding: BindingDirection
    ) -> Double {
        guard unitCount > 1 else { return 0 }
        let clamped = min(max(unitIndex, 0), unitCount - 1)
        return binding == .right
            ? Double(unitCount - 1 - clamped)
            : Double(clamped)
    }

    /// スライダー値 → 表示単位インデックス。`sliderValue` の逆変換。
    static func unitIndex(
        sliderValue: Double,
        unitCount: Int,
        binding: BindingDirection
    ) -> Int {
        guard unitCount > 0 else { return 0 }
        let rounded = min(max(Int(sliderValue.rounded()), 0), unitCount - 1)
        return binding == .right
            ? unitCount - 1 - rounded
            : rounded
    }
}
