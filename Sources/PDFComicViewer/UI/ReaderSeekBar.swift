import SwiftUI

@MainActor
struct ReaderSeekBar: View {
    @ObservedObject var model: ReaderViewModel
    /// マウスボタンを押してつまみをドラッグしている間だけtrueになる。
    /// AppKitはドラッグ中に`.onContinuousHover`の更新配送を止めることがあり、
    /// それに引きずられてシークバーが非表示になってしまう問題への対処として、
    /// 親（`ReaderView`）へドラッグ中であることを直接伝える。
    let onDraggingChanged: (Bool) -> Void

    /// ドラッグ中だけ値を保持する。nilならモデルの現在位置をそのまま映す。
    @State private var draggingValue: Double?
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            Slider(
                value: sliderBinding,
                in: 0...Double(max(unitCount - 1, 1)),
                step: 1,
                onEditingChanged: { isEditing in
                    onDraggingChanged(isEditing)
                    if !isEditing {
                        commitImmediately()
                    }
                }
            )
            // 右綴じでは1ページ目を右端に置く。macOSのSliderは常に左端から
            // 現在値までを塗るため、値の反転だけでは塗りの向きが逆に残る。
            // Slider自体を水平反転させ、つまみ・塗り・ドラッグ方向を揃える。
            // ラベルまで反転しないよう、Sliderにだけ掛けること。
            .scaleEffect(
                x: SeekBarPresentation.horizontalScale(for: model.preferences.binding),
                y: 1
            )
            // つまみを直接掴む最初の1回は、AppKitがまだ「ドラッグ開始」と
            // 認識できず`onEditingChanged`が発火しないことがある。SwiftUI側で
            // 独立にmouseDownを検知し、その保険としてドラッグ中扱いにする
            // （`.simultaneousGesture`なのでSliderの標準動作は妨げない）。
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onDraggingChanged(true) }
                    .onEnded { _ in onDraggingChanged(false) }
            )
            .accessibilityLabel("ページ位置")

            Text(labelText)
                .font(.system(.callout, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(ReaderTheme.secondaryText)
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ReaderTheme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(ReaderTheme.border.opacity(0.8), lineWidth: 1)
        }
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
            // ドラッグ中に破棄された場合（文書を閉じる操作など）でも、
            // 親側の「ドラッグ中」フラグが立ちっぱなしにならないようにする。
            onDraggingChanged(false)
        }
    }

    private var unitCount: Int {
        model.displayUnits.count
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                draggingValue ?? SeekBarPresentation.sliderValue(
                    unitIndex: model.currentUnitIndex,
                    unitCount: unitCount
                )
            },
            set: { newValue in
                draggingValue = newValue
                scheduleCommit()
            }
        )
    }

    private var labelText: String {
        guard let session = model.session else { return "—" }
        let index = draggingValue.map(targetUnitIndex(for:)) ?? model.currentUnitIndex
        guard model.displayUnits.indices.contains(index) else { return "—" }
        return ReaderPresentation.pageCounterText(
            for: model.displayUnits[index],
            totalPages: session.pages.count
        )
    }

    private func targetUnitIndex(for value: Double) -> Int {
        SeekBarPresentation.unitIndex(
            sliderValue: value,
            unitCount: unitCount
        )
    }

    /// つまみが落ち着くまでジャンプを遅らせる。
    /// 一気に振ったときに途中のページ描画をまとめて飛ばすため。
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            commitImmediately()
        }
    }

    private func commitImmediately() {
        commitTask?.cancel()
        commitTask = nil
        guard let value = draggingValue else { return }
        draggingValue = nil
        model.jumpToUnit(index: targetUnitIndex(for: value))
    }
}
