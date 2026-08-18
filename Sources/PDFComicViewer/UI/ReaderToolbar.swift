import SwiftUI

enum ReaderPresentation {
    static func pageCounterText(for unit: DisplayUnit, totalPages: Int) -> String {
        let displayedPages = unit.pageIndexes.map { String($0 + 1) }.joined(separator: "–")
        return "\(displayedPages) / \(totalPages)"
    }

    static func pageIndex(
        atHorizontalPosition position: CGFloat,
        viewerWidth: CGFloat,
        placement: PagePlacement
    ) -> Int? {
        if let centered = placement.centered {
            return centered
        }
        guard viewerWidth > 0 else { return nil }
        return position < viewerWidth / 2 ? placement.left : placement.right
    }
}

enum ReaderTheme {
    static let canvasNSColor = NSColor(
        srgbRed: 11 / 255,
        green: 12 / 255,
        blue: 14 / 255,
        alpha: 1
    )
    static let canvas = Color(nsColor: canvasNSColor)
    static let surface = Color(.sRGB, red: 23 / 255, green: 25 / 255, blue: 29 / 255)
    static let primaryText = Color(.sRGB, red: 242 / 255, green: 243 / 255, blue: 245 / 255)
    static let secondaryText = Color(.sRGB, red: 155 / 255, green: 163 / 255, blue: 174 / 255)
    static let accent = Color(.sRGB, red: 94 / 255, green: 145 / 255, blue: 209 / 255)
    static let border = Color(.sRGB, red: 58 / 255, green: 63 / 255, blue: 71 / 255)
}

@MainActor
struct ReaderToolbar: View {
    @ObservedObject var model: ReaderViewModel
    @Binding var sidebarIsVisible: Bool
    @FocusState private var focusedControl: FocusedReaderControl?

    let targetURLs: [URL]
    let requestDelete: ([URL]) -> Void
    let resetProgress: ([URL]) -> Void
    let keyboardFocusChange: (Bool) -> Void

    init(
        model: ReaderViewModel,
        sidebarIsVisible: Binding<Bool>,
        targetURLs: [URL],
        requestDelete: @escaping ([URL]) -> Void,
        resetProgress: @escaping ([URL]) -> Void,
        keyboardFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self._sidebarIsVisible = sidebarIsVisible
        self.targetURLs = targetURLs
        self.requestDelete = requestDelete
        self.resetProgress = resetProgress
        self.keyboardFocusChange = keyboardFocusChange
    }

    var body: some View {
        HStack(spacing: 8) {
            iconButton(
                "PDFを開く",
                systemImage: "doc.badge.plus",
                shortcut: "⌘O",
                action: model.requestFileOpen
            )
            .focused($focusedControl, equals: .open)

            Divider().frame(height: 20)

            BindingDirectionButton(model: model)
                .disabled(model.session == nil)
                .focused($focusedControl, equals: .binding)

            Picker(
                "表示方法",
                selection: Binding(
                    get: { model.preferences.displayMode },
                    set: { newMode in model.setDisplayMode(newMode) }
                )
            ) {
                Text("1ページ").tag(DisplayMode.single)
                Text("見開き").tag(DisplayMode.spread)
            }
            .pickerStyle(.segmented)
            .frame(width: 142)
            .accessibilityLabel("ページの表示方法")
            .help("1ページ表示と見開き表示を切り替えます（1 / 2 キー）")
            .nativeToolTip("1ページ表示と見開き表示を切り替えます（1 / 2 キー）")
            .disabled(model.session == nil)
            .focused($focusedControl, equals: .displayMode)

            iconButton(
                "見開き位置を1ページずらす",
                systemImage: "rectangle.split.2x1",
                shortcut: "S",
                action: model.toggleAlignment
            )
            // 起点ページに組む相手がいないときは、押しても組み合わせが変わらない。
            // 押せてしまうと壊れたように見えるので、無効にして理由を示す。
            .disabled(!model.alignmentToggleIsEffective)
            .focused($focusedControl, equals: .alignment)

            iconButton(
                "いま見ているページから先をずらす",
                systemImage: "rectangle.split.2x1.slash",
                shortcut: "⇧S",
                action: model.shiftSpreadHere
            )
            .disabled(model.session == nil || model.preferences.displayMode == .single)
            .focused($focusedControl, equals: .localShift)

            iconButton(
                "最初に戻る",
                systemImage: "backward.end",
                action: { resetProgress(targetURLs) }
            )
            .disabled(targetURLs.isEmpty)
            .focused($focusedControl, equals: .firstPage)

            Divider().frame(height: 20)

            iconButton("縮小", systemImage: "minus.magnifyingglass", shortcut: "⌘-", action: model.zoomOut)
                .disabled(model.session == nil)
                .focused($focusedControl, equals: .zoomOut)
            iconButton("ウインドウに合わせる", systemImage: "arrow.down.right.and.arrow.up.left", shortcut: "⌘0", action: model.fitToWindow)
                .disabled(model.session == nil)
                .focused($focusedControl, equals: .fit)
            iconButton("拡大", systemImage: "plus.magnifyingglass", shortcut: "⌘+", action: model.zoomIn)
                .disabled(model.session == nil)
                .focused($focusedControl, equals: .zoomIn)

            Text(pageCounterText)
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(ReaderTheme.secondaryText)
                .frame(minWidth: 92)
                .accessibilityLabel("現在のページ \(pageCounterText)")

            Divider().frame(height: 20)

            iconButton(
                "PDFを閉じる",
                systemImage: "xmark.circle",
                action: { Task { await model.closeDocument() } }
            )
            .disabled(model.session == nil)
            .focused($focusedControl, equals: .close)

            iconButton(
                "選択中のPDFをゴミ箱に入れる",
                systemImage: "trash",
                action: { requestDelete(targetURLs) }
            )
            .disabled(targetURLs.isEmpty)
            .focused($focusedControl, equals: .delete)

            iconButton(
                sidebarIsVisible ? "フォルダ一覧を隠す" : "フォルダ一覧を表示",
                systemImage: "sidebar.left",
                shortcut: "⌘B",
                action: { sidebarIsVisible.toggle() }
            )
            .focused($focusedControl, equals: .sidebar)

            Divider().frame(height: 20)

            iconButton(
                "全画面表示を切り替える",
                systemImage: "arrow.up.left.and.arrow.down.right",
                shortcut: "⌃⌘F",
                action: model.requestFullScreenToggle
            )
            .focused($focusedControl, equals: .fullScreen)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(ReaderTheme.primaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ReaderTheme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(ReaderTheme.border.opacity(0.8), lineWidth: 1)
        }
        .onChange(of: focusedControl, initial: true) { _, control in
            keyboardFocusChange(control != nil)
        }
        .onDisappear {
            keyboardFocusChange(false)
        }
    }

    private var pageCounterText: String {
        guard let session = model.session, let unit = model.currentUnit else { return "—" }
        return ReaderPresentation.pageCounterText(for: unit, totalPages: session.pages.count)
    }

    private func iconButton(
        _ title: String,
        systemImage: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let helpText = shortcut.map { "\(title)（\($0)）" } ?? title
        return Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ReaderTheme.primaryText)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .help(helpText)
        // SwiftUIの`.help()`だけでは反映されないことがあるため、
        // AppKitの`NSView.toolTip`で補う（NativeToolTip.swift参照）。
        .nativeToolTip(helpText)
    }
}

private enum FocusedReaderControl: Hashable {
    case open
    case binding
    case displayMode
    case alignment
    case localShift
    case firstPage
    case zoomOut
    case fit
    case zoomIn
    case close
    case delete
    case sidebar
    case fullScreen
}

@MainActor
private struct BindingDirectionButton: View {
    @ObservedObject var model: ReaderViewModel

    var body: some View {
        Button {
            model.setBinding(model.preferences.binding == .right ? .left : .right)
        } label: {
            HStack(spacing: 6) {
                BindingDirectionGlyph(direction: model.preferences.binding)
                    .frame(width: 25, height: 17)
                    .accessibilityHidden(true)
                Text(model.preferences.binding == .right ? "右綴じ" : "左綴じ")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ReaderTheme.primaryText)
        .accessibilityLabel(
            model.preferences.binding == .right ? "右綴じ。左綴じに変更" : "左綴じ。右綴じに変更"
        )
        .help("漫画の綴じ方向を切り替えます")
        .nativeToolTip("漫画の綴じ方向を切り替えます")
    }
}

private struct BindingDirectionGlyph: View {
    let direction: BindingDirection

    var body: some View {
        ZStack(alignment: direction == .right ? .trailing : .leading) {
            HStack(spacing: 2) {
                page
                page
            }
            Rectangle()
                .fill(ReaderTheme.accent)
                .frame(width: 2)
        }
    }

    private var page: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(ReaderTheme.primaryText.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 1.5)
                    .stroke(ReaderTheme.secondaryText, lineWidth: 1)
            }
    }
}
