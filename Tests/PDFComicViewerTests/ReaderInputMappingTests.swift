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
