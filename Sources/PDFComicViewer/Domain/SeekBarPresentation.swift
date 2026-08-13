import CoreGraphics
import Foundation

/// シークバーのスライダー値と表示単位インデックスを相互変換する。
enum SeekBarPresentation {
    /// 表示単位インデックス → スライダー値。
    static func sliderValue(unitIndex: Int, unitCount: Int) -> Double {
        guard unitCount > 1 else { return 0 }
        return Double(min(max(unitIndex, 0), unitCount - 1))
    }

    /// スライダー値 → 表示単位インデックス。`sliderValue` の逆変換。
    static func unitIndex(sliderValue: Double, unitCount: Int) -> Int {
        guard unitCount > 0 else { return 0 }
        return min(max(Int(sliderValue.rounded()), 0), unitCount - 1)
    }

    /// 綴じ方向に応じた、Sliderへ掛ける水平方向の倍率。
    ///
    /// 右綴じでは1ページ目を右端に置きたいが、macOSのSliderは常に
    /// 「左端から現在値まで」を塗りつぶす仕様で、この向きは変更できない。
    /// 値だけ反転させるとつまみの位置は正しくなるものの、塗りの向きが
    /// 逆のまま残ってしまう。そのためView自体を水平反転させ、
    /// つまみ・塗り・ドラッグ方向をまとめて綴じ方向に合わせる。
    static func horizontalScale(for binding: BindingDirection) -> CGFloat {
        binding == .right ? -1 : 1
    }
}
