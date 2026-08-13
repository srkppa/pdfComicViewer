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
            // 綴じ方向が変わるたびにSliderを作り直す。既存のSliderへ値だけ
            // 差し替えるパスでは、AppKit側の描画更新が反映されないことがあるため、
            // ビューごと作り直して確実に正しい向きで初期化させる。
            .id(model.preferences.binding)
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
                    unitCount: unitCount,
                    binding: model.preferences.binding
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
            unitCount: unitCount,
            binding: model.preferences.binding
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
