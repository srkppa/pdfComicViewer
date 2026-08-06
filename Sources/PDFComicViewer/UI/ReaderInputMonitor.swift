import AppKit
import SwiftUI

enum ReaderKey {
    case leftArrow
    case rightArrow
    case space
    case one
    case two
    case toggleAlignment
}

enum ReaderInputAction: Equatable {
    case next
    case previous
    case singlePage
    case spread
    case toggleAlignment
}

enum ReaderInputMapping {
    static func shouldConsumeUnhandledKey(
        keyCode: UInt16,
        hasCommandOrControlOrOption: Bool
    ) -> Bool {
        !hasCommandOrControlOrOption && [123, 124, 49].contains(keyCode)
    }

    static func shouldHandleReaderKey(
        readerIsEnabled: Bool,
        textIsEditing: Bool,
        controlHasFocus: Bool
    ) -> Bool {
        readerIsEnabled && !textIsEditing && !controlHasFocus
    }

    static func action(
        for key: ReaderKey,
        shiftPressed: Bool = false,
        binding: BindingDirection
    ) -> ReaderInputAction {
        switch key {
        case .leftArrow:
            binding == .right ? .next : .previous
        case .rightArrow:
            binding == .right ? .previous : .next
        case .space:
            shiftPressed ? .previous : .next
        case .one:
            .singlePage
        case .two:
            .spread
        case .toggleAlignment:
            .toggleAlignment
        }
    }

    static func clickAction(
        start: CGPoint,
        end: CGPoint,
        viewerWidth: CGFloat,
        binding: BindingDirection
    ) -> ReaderInputAction? {
        guard viewerWidth > 0, hypot(end.x - start.x, end.y - start.y) <= 3 else {
            return nil
        }
        let clickedLeftHalf = end.x < viewerWidth / 2
        switch (binding, clickedLeftHalf) {
        case (.right, true), (.left, false):
            return .next
        case (.right, false), (.left, true):
            return .previous
        }
    }
}

enum ReaderDragPan {
    static let activationDistance: CGFloat = 3

    static func origin(
        startPointer: CGPoint,
        currentPointer: CGPoint,
        startOrigin: CGPoint,
        maximumOrigin: CGPoint,
        magnification: CGFloat
    ) -> CGPoint {
        let distance = hypot(
            currentPointer.x - startPointer.x,
            currentPointer.y - startPointer.y
        )
        guard distance > activationDistance else { return startOrigin }
        let scale = max(magnification, 1)
        let proposed = CGPoint(
            x: startOrigin.x - (currentPointer.x - startPointer.x) / scale,
            y: startOrigin.y - (currentPointer.y - startPointer.y) / scale
        )
        return CGPoint(
            x: min(max(proposed.x, 0), max(maximumOrigin.x, 0)),
            y: min(max(proposed.y, 0), max(maximumOrigin.y, 0))
        )
    }
}

@MainActor
struct ReaderInputMonitor: NSViewRepresentable {
    let binding: BindingDirection
    let isEnabled: Bool
    let controlHasKeyboardFocus: Bool
    let excludedTopHeight: CGFloat
    let excludedBottomHeight: CGFloat
    let fullScreenRequestSequence: Int
    let action: (ReaderInputAction) -> Void
    let interaction: () -> Void
    let contextPageRequest: (CGFloat, CGFloat) -> Void
    let fullScreenChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(monitor: self)
    }

    func makeNSView(context: Context) -> MonitorHostView {
        let view = MonitorHostView()
        view.coordinator = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: MonitorHostView, context: Context) {
        context.coordinator.update(from: self)
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: MonitorHostView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.coordinator = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var hostView: MonitorHostView?
        private weak var window: NSWindow?
        private var eventMonitor: Any?
        private var previousAcceptsMouseMovedEvents = false
        private var mouseDownLocation: CGPoint?
        private var maximumDragDistance: CGFloat = 0
        private var binding: BindingDirection
        private var isEnabled: Bool
        private var controlHasKeyboardFocus: Bool
        private var excludedTopHeight: CGFloat
        private var excludedBottomHeight: CGFloat
        private var lastFullScreenRequestSequence: Int
        private var hasPendingFullScreenRequest = false
        private var action: (ReaderInputAction) -> Void
        private var interaction: () -> Void
        private var contextPageRequest: (CGFloat, CGFloat) -> Void
        private var fullScreenChange: (Bool) -> Void

        init(monitor: ReaderInputMonitor) {
            binding = monitor.binding
            isEnabled = monitor.isEnabled
            controlHasKeyboardFocus = monitor.controlHasKeyboardFocus
            excludedTopHeight = monitor.excludedTopHeight
            excludedBottomHeight = monitor.excludedBottomHeight
            lastFullScreenRequestSequence = monitor.fullScreenRequestSequence
            action = monitor.action
            interaction = monitor.interaction
            contextPageRequest = monitor.contextPageRequest
            fullScreenChange = monitor.fullScreenChange
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func update(from monitor: ReaderInputMonitor) {
            binding = monitor.binding
            isEnabled = monitor.isEnabled
            controlHasKeyboardFocus = monitor.controlHasKeyboardFocus
            excludedTopHeight = monitor.excludedTopHeight
            excludedBottomHeight = monitor.excludedBottomHeight
            action = monitor.action
            interaction = monitor.interaction
            contextPageRequest = monitor.contextPageRequest
            fullScreenChange = monitor.fullScreenChange

            if lastFullScreenRequestSequence != monitor.fullScreenRequestSequence {
                lastFullScreenRequestSequence = monitor.fullScreenRequestSequence
                hasPendingFullScreenRequest = true
            }
            performPendingFullScreenRequest()
            updateMonitoringState()
        }

        func attach(to view: MonitorHostView) {
            hostView = view
            guard window !== view.window else {
                performPendingFullScreenRequest()
                updateMonitoringState()
                return
            }

            stopMonitoring()
            NotificationCenter.default.removeObserver(self)
            window = view.window

            guard let window else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResignKey),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidEnterFullScreen),
                name: NSWindow.didEnterFullScreenNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidExitFullScreen),
                name: NSWindow.didExitFullScreenNotification,
                object: window
            )
            let isFullScreen = window.styleMask.contains(.fullScreen)
            Task { @MainActor [weak self] in
                self?.fullScreenChange(isFullScreen)
            }
            performPendingFullScreenRequest()
            updateMonitoringState()
        }

        func detach() {
            stopMonitoring()
            NotificationCenter.default.removeObserver(self)
            hostView = nil
            window = nil
        }

        @objc private func windowDidBecomeKey() {
            updateMonitoringState()
        }

        @objc private func windowDidResignKey() {
            stopMonitoring()
        }

        @objc private func windowDidEnterFullScreen() {
            fullScreenChange(true)
        }

        @objc private func windowDidExitFullScreen() {
            fullScreenChange(false)
        }

        private func updateMonitoringState() {
            guard window?.isKeyWindow == true else {
                stopMonitoring()
                return
            }
            startMonitoring()
        }

        private func startMonitoring() {
            guard eventMonitor == nil, let window else { return }
            previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
            window.acceptsMouseMovedEvents = true
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [
                    .keyDown,
                    .leftMouseDown,
                    .leftMouseDragged,
                    .leftMouseUp,
                    .rightMouseDown,
                    .mouseMoved
                ]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            window?.acceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
            mouseDownLocation = nil
            maximumDragDistance = 0
        }

        private func performPendingFullScreenRequest() {
            guard hasPendingFullScreenRequest, let window else { return }
            hasPendingFullScreenRequest = false
            guard window.isKeyWindow else { return }
            window.toggleFullScreen(nil)
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }

            switch event.type {
            case .mouseMoved:
                interaction()
            case .keyDown:
                interaction()
                guard ReaderInputMapping.shouldHandleReaderKey(
                          readerIsEnabled: isEnabled,
                          textIsEditing: isEditingText(in: window),
                          controlHasFocus: controlHasKeyboardFocus
                              || isAppKitControlFocused(in: window)
                      ),
                      !hasBlockingModifiers(event.modifierFlags),
                      let key = readerKey(for: event) else { return event }
                action(
                    ReaderInputMapping.action(
                        for: key,
                        shiftPressed: event.modifierFlags.contains(.shift),
                        binding: binding
                    )
                )
                return nil
            case .leftMouseDown:
                guard isEnabled,
                      let location = viewerLocation(for: event) else { return event }
                interaction()
                window.makeFirstResponder(nil)
                mouseDownLocation = location
                maximumDragDistance = 0
            case .leftMouseDragged:
                guard let start = mouseDownLocation,
                      let location = viewerLocation(for: event, requireInside: false) else {
                    return event
                }
                interaction()
                maximumDragDistance = max(
                    maximumDragDistance,
                    hypot(location.x - start.x, location.y - start.y)
                )
            case .leftMouseUp:
                guard let start = mouseDownLocation,
                      let location = viewerLocation(for: event) else {
                    mouseDownLocation = nil
                    return event
                }
                mouseDownLocation = nil
                guard maximumDragDistance <= 3,
                      let hostView,
                      let mappedAction = ReaderInputMapping.clickAction(
                          start: start,
                          end: location,
                          viewerWidth: hostView.bounds.width,
                          binding: binding
                      ) else { return event }
                action(mappedAction)
            case .rightMouseDown:
                guard isEnabled,
                      let location = viewerLocation(for: event),
                      let hostView else {
                    return event
                }
                interaction()
                contextPageRequest(location.x, hostView.bounds.width)
            default:
                break
            }
            return event
        }

        private func viewerLocation(
            for event: NSEvent,
            requireInside: Bool = true
        ) -> CGPoint? {
            guard let hostView else { return nil }
            let location = hostView.convert(event.locationInWindow, from: nil)
            guard !requireInside || hostView.bounds.contains(location) else { return nil }
            if requireInside {
                guard location.y >= excludedBottomHeight,
                      location.y <= hostView.bounds.height - excludedTopHeight else {
                    return nil
                }
            }
            return location
        }

        private func hasBlockingModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
            !flags.intersection([.command, .control, .option]).isEmpty
        }

        private func readerKey(for event: NSEvent) -> ReaderKey? {
            switch event.keyCode {
            case 123:
                return .leftArrow
            case 124:
                return .rightArrow
            case 49:
                return .space
            default:
                return switch event.charactersIgnoringModifiers?.lowercased() {
                case "1": .one
                case "2": .two
                case "s": .toggleAlignment
                default: nil
                }
            }
        }

        private func isEditingText(in window: NSWindow) -> Bool {
            window.firstResponder is NSTextView
        }

        private func isAppKitControlFocused(in window: NSWindow) -> Bool {
            if window.firstResponder is NSControl {
                return true
            }
            guard var view = window.firstResponder as? NSView else { return false }
            while let superview = view.superview {
                if superview is NSControl {
                    return true
                }
                view = superview
            }
            return false
        }
    }
}

@MainActor
final class MonitorHostView: NSView {
    weak var coordinator: ReaderInputMonitor.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.attach(to: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
