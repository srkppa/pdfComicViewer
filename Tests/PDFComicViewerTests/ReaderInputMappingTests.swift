import Foundation
import XCTest
@testable import PDFComicViewer

final class ReaderInputMappingTests: XCTestCase {
    @MainActor
    func testMonitorHostConsumesArrowKeyThroughResponderChain() throws {
        var actions: [ReaderInputAction] = []
        let monitor = ReaderInputMonitor(
            binding: .right,
            isEnabled: true,
            controlHasKeyboardFocus: false,
            excludedTopHeight: 0,
            excludedBottomHeight: 0,
            fullScreenRequestSequence: 0,
            focusRequestSequence: 0,
            action: { actions.append($0) },
            interaction: {},
            contextPageRequest: { _, _ in },
            fullScreenChange: { _ in }
        )
        let coordinator = monitor.makeCoordinator()
        let hostView = MonitorHostView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        hostView.coordinator = coordinator
        let window = NSWindow(
            contentRect: hostView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostView
        coordinator.attach(to: hostView)
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.function, .numericPad],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{F702}",
                charactersIgnoringModifiers: "\u{F702}",
                isARepeat: false,
                keyCode: 123
            )
        )

        XCTAssertTrue(window.makeFirstResponder(hostView))
        hostView.keyDown(with: event)

        XCTAssertEqual(actions, [.next])
    }

    /// PDFを開いた直後は、サイドバーなど別のビューにフォーカスが残っていても
    /// 本文へ戻す。戻さないと、一度本文をクリックするまでページ送りの
    /// ショートカットが効かない。
    @MainActor
    func testFocusRequestMovesFirstResponderToViewer() {
        let hostView = MonitorHostView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(
            contentRect: hostView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let sidebarField = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        let container = NSView(frame: hostView.frame)
        container.addSubview(hostView)
        container.addSubview(sidebarField)
        window.contentView = container
        window.makeKeyAndOrderFront(nil)

        let coordinator = makeMonitor(focusRequestSequence: 0).makeCoordinator()
        hostView.coordinator = coordinator
        coordinator.attach(to: hostView)
        XCTAssertTrue(window.makeFirstResponder(sidebarField))

        coordinator.update(from: makeMonitor(focusRequestSequence: 1))

        XCTAssertTrue(
            window.firstResponder === hostView
                || window.firstResponder?.isKind(of: NSView.self) == true
                && (window.firstResponder as? NSView)?.isDescendant(of: hostView) == true,
            "本文へフォーカスが移っていない: \(String(describing: window.firstResponder))"
        )
    }

    /// 同じ要求番号のまま再描画されただけなら、フォーカスは奪わない。
    /// 奪うと、ツールバーやサイドバーを操作している最中に持っていかれてしまう。
    @MainActor
    func testUnchangedFocusRequestLeavesFirstResponderAlone() {
        let hostView = MonitorHostView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(
            contentRect: hostView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let sidebarField = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        let container = NSView(frame: hostView.frame)
        container.addSubview(hostView)
        container.addSubview(sidebarField)
        window.contentView = container
        window.makeKeyAndOrderFront(nil)

        let coordinator = makeMonitor(focusRequestSequence: 3).makeCoordinator()
        hostView.coordinator = coordinator
        coordinator.attach(to: hostView)
        XCTAssertTrue(window.makeFirstResponder(sidebarField))

        coordinator.update(from: makeMonitor(focusRequestSequence: 3))

        XCTAssertFalse(window.firstResponder === hostView)
    }

    @MainActor
    private func makeMonitor(focusRequestSequence: Int) -> ReaderInputMonitor {
        ReaderInputMonitor(
            binding: .right,
            isEnabled: true,
            controlHasKeyboardFocus: false,
            excludedTopHeight: 0,
            excludedBottomHeight: 0,
            fullScreenRequestSequence: 0,
            focusRequestSequence: focusRequestSequence,
            action: { _ in },
            interaction: {},
            contextPageRequest: { _, _ in },
            fullScreenChange: { _ in }
        )
    }

    func testDragPanKeepsClickJitterStationaryAndPansAfterThreshold() {
        let start = CGPoint(x: 100, y: 100)
        let origin = CGPoint(x: 40, y: 60)
        let limits = CGPoint(x: 300, y: 200)

        XCTAssertEqual(
            ReaderDragPan.origin(
                startPointer: start,
                currentPointer: CGPoint(x: 102, y: 101),
                startOrigin: origin,
                maximumOrigin: limits,
                magnification: 2
            ),
            origin
        )
        XCTAssertEqual(
            ReaderDragPan.origin(
                startPointer: start,
                currentPointer: CGPoint(x: 80, y: 60),
                startOrigin: origin,
                maximumOrigin: limits,
                magnification: 2
            ),
            CGPoint(x: 50, y: 80)
        )
    }

    func testDragPanConstrainsOriginToScrollableBounds() {
        XCTAssertEqual(
            ReaderDragPan.origin(
                startPointer: .zero,
                currentPointer: CGPoint(x: 100, y: 100),
                startOrigin: CGPoint(x: 10, y: 20),
                maximumOrigin: CGPoint(x: 200, y: 300),
                magnification: 1
            ),
            .zero
        )
        XCTAssertEqual(
            ReaderDragPan.origin(
                startPointer: .zero,
                currentPointer: CGPoint(x: -500, y: -500),
                startOrigin: CGPoint(x: 10, y: 20),
                maximumOrigin: CGPoint(x: 200, y: 300),
                magnification: 1
            ),
            CGPoint(x: 200, y: 300)
        )
    }

    func testReaderKeysAreHandledWhenCanvasHasKeyboardFocus() {
        XCTAssertTrue(
            ReaderInputMapping.shouldHandleReaderKey(
                readerIsEnabled: true,
                textIsEditing: false,
                controlHasFocus: false
            )
        )
    }

    func testReaderKeysPassThroughWhenOperationControlHasKeyboardFocus() {
        XCTAssertFalse(
            ReaderInputMapping.shouldHandleReaderKey(
                readerIsEnabled: true,
                textIsEditing: false,
                controlHasFocus: true
            )
        )
    }

    func testReaderKeysPassThroughWhileEditingTextOrShowingModalState() {
        XCTAssertFalse(
            ReaderInputMapping.shouldHandleReaderKey(
                readerIsEnabled: true,
                textIsEditing: true,
                controlHasFocus: false
            )
        )
        XCTAssertFalse(
            ReaderInputMapping.shouldHandleReaderKey(
                readerIsEnabled: false,
                textIsEditing: false,
                controlHasFocus: false
            )
        )
    }

    func testUnhandledReaderKeysAreConsumedBeforeAppKitCanBeep() {
        XCTAssertTrue(
            ReaderInputMapping.shouldConsumeUnhandledKey(
                keyCode: 123,
                hasCommandOrControlOrOption: false
            )
        )
        XCTAssertTrue(
            ReaderInputMapping.shouldConsumeUnhandledKey(
                keyCode: 124,
                hasCommandOrControlOrOption: false
            )
        )
        XCTAssertTrue(
            ReaderInputMapping.shouldConsumeUnhandledKey(
                keyCode: 49,
                hasCommandOrControlOrOption: false
            )
        )
    }

    func testUnhandledModifiedOrUnrelatedKeysKeepAppKitDefaultBehavior() {
        XCTAssertFalse(
            ReaderInputMapping.shouldConsumeUnhandledKey(
                keyCode: 123,
                hasCommandOrControlOrOption: true
            )
        )
        XCTAssertFalse(
            ReaderInputMapping.shouldConsumeUnhandledKey(
                keyCode: 0,
                hasCommandOrControlOrOption: false
            )
        )
    }

    func testRightBindingMapsLeftArrowToNextAndRightArrowToPrevious() {
        XCTAssertEqual(
            ReaderInputMapping.action(for: .leftArrow, binding: .right),
            .next
        )
        XCTAssertEqual(
            ReaderInputMapping.action(for: .rightArrow, binding: .right),
            .previous
        )
    }

    func testLeftBindingReversesArrowActions() {
        XCTAssertEqual(
            ReaderInputMapping.action(for: .leftArrow, binding: .left),
            .previous
        )
        XCTAssertEqual(
            ReaderInputMapping.action(for: .rightArrow, binding: .left),
            .next
        )
    }

    func testSpaceKeepsReadingOrderAcrossBindingDirections() {
        XCTAssertEqual(
            ReaderInputMapping.action(for: .space, binding: .right),
            .next
        )
        XCTAssertEqual(
            ReaderInputMapping.action(for: .space, binding: .left),
            .next
        )
        XCTAssertEqual(
            ReaderInputMapping.action(for: .space, shiftPressed: true, binding: .left),
            .previous
        )
    }

    func testNumberAndAlignmentKeysMapToDisplayActions() {
        XCTAssertEqual(ReaderInputMapping.action(for: .one, binding: .right), .singlePage)
        XCTAssertEqual(ReaderInputMapping.action(for: .two, binding: .right), .spread)
        XCTAssertEqual(
            ReaderInputMapping.action(for: .toggleAlignment, binding: .right),
            .toggleAlignment
        )
    }

    /// Shiftを添えたSは、文書全体のずらしではなく、いま見ているページから先を
    /// ずらす操作に割り当てる。横長ページで組み合わせが途切れた先では、
    /// 全体のずらし（S）が届かないため。
    func testShiftedAlignmentKeyMapsToLocalShift() {
        XCTAssertEqual(
            ReaderInputMapping.action(
                for: .toggleAlignment, shiftPressed: true, binding: .right
            ),
            .shiftSpreadHere
        )
        XCTAssertEqual(
            ReaderInputMapping.action(
                for: .toggleAlignment, shiftPressed: true, binding: .left
            ),
            .shiftSpreadHere
        )
    }

    func testRightBindingMapsLeftClickToNextAndRightClickToPrevious() {
        XCTAssertEqual(
            ReaderInputMapping.clickAction(
                start: CGPoint(x: 20, y: 20),
                end: CGPoint(x: 22, y: 21),
                viewerWidth: 100,
                binding: .right
            ),
            .next
        )
        XCTAssertEqual(
            ReaderInputMapping.clickAction(
                start: CGPoint(x: 80, y: 20),
                end: CGPoint(x: 80, y: 20),
                viewerWidth: 100,
                binding: .right
            ),
            .previous
        )
    }

    func testLeftBindingReversesClickActions() {
        XCTAssertEqual(
            ReaderInputMapping.clickAction(
                start: CGPoint(x: 20, y: 20),
                end: CGPoint(x: 20, y: 20),
                viewerWidth: 100,
                binding: .left
            ),
            .previous
        )
        XCTAssertEqual(
            ReaderInputMapping.clickAction(
                start: CGPoint(x: 80, y: 20),
                end: CGPoint(x: 80, y: 20),
                viewerWidth: 100,
                binding: .left
            ),
            .next
        )
    }

    func testDragBeyondThreePointsDoesNotTurnPage() {
        XCTAssertNil(
            ReaderInputMapping.clickAction(
                start: CGPoint(x: 20, y: 20),
                end: CGPoint(x: 23.1, y: 20),
                viewerWidth: 100,
                binding: .right
            )
        )
        XCTAssertEqual(
            ReaderInputMapping.clickAction(
                start: CGPoint(x: 20, y: 20),
                end: CGPoint(x: 23, y: 20),
                viewerWidth: 100,
                binding: .right
            ),
            .next
        )
    }
}

final class ReaderPresentationTests: XCTestCase {
    func testPageCounterUsesOneBasedNumbersForSpread() {
        XCTAssertEqual(
            ReaderPresentation.pageCounterText(for: .pair(11, 12), totalPages: 180),
            "12–13 / 180"
        )
    }

    func testPageCounterUsesOneBasedNumberForSinglePage() {
        XCTAssertEqual(
            ReaderPresentation.pageCounterText(for: .single(11), totalPages: 180),
            "12 / 180"
        )
    }

    func testContextTargetUsesPhysicalLeftAndRightPages() {
        let placement = PagePlacement(left: 12, right: 11, centered: nil)

        XCTAssertEqual(
            ReaderPresentation.pageIndex(
                atHorizontalPosition: 20,
                viewerWidth: 100,
                placement: placement
            ),
            12
        )
        XCTAssertEqual(
            ReaderPresentation.pageIndex(
                atHorizontalPosition: 80,
                viewerWidth: 100,
                placement: placement
            ),
            11
        )
    }

    func testContextTargetUsesCenteredPhysicalPageAtAnyPosition() {
        let placement = PagePlacement(left: nil, right: nil, centered: 4)

        XCTAssertEqual(
            ReaderPresentation.pageIndex(
                atHorizontalPosition: 5,
                viewerWidth: 100,
                placement: placement
            ),
            4
        )
        XCTAssertEqual(
            ReaderPresentation.pageIndex(
                atHorizontalPosition: 95,
                viewerWidth: 100,
                placement: placement
            ),
            4
        )
    }
}

@MainActor
final class ReaderLiveConfigurationTests: XCTestCase {
    func testProgressFileURLUsesApplicationSupportBundleDirectory() {
        let support = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        XCTAssertEqual(
            ReaderViewModel.progressFileURL(applicationSupportDirectory: support),
            support
                .appendingPathComponent("com.srkppa.PDFComicViewer", isDirectory: true)
                .appendingPathComponent("reading-progress.json")
        )
    }
}
