import AppKit
import SwiftUI

/// クリックを妨げずにAppKitの`NSView.toolTip`を重ねるための透明なオーバーレイ。
private final class PassthroughToolTipView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct ToolTipOverlay: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughToolTipView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

extension View {
    /// SwiftUIの`.help()`が反映されないことがある箇所（カスタムツールバー内など）向けに、
    /// AppKitのツールチップ機構を直接使ってホバー時の説明文を表示する。
    func nativeToolTip(_ text: String) -> some View {
        overlay(ToolTipOverlay(text: text))
    }
}
