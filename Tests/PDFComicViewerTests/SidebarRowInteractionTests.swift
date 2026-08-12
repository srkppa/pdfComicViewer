import AppKit
import XCTest
@testable import PDFComicViewer

final class SidebarRowInteractionTests: XCTestCase {
    func testNoModifiersOpens() {
        let result = SidebarRowInteraction.shouldOpenPDF(modifiers: [])

        XCTAssertTrue(result)
    }

    func testCommandModifierPreventsOpen() {
        let result = SidebarRowInteraction.shouldOpenPDF(modifiers: [.command])

        XCTAssertFalse(result)
    }

    func testShiftModifierPreventsOpen() {
        let result = SidebarRowInteraction.shouldOpenPDF(modifiers: [.shift])

        XCTAssertFalse(result)
    }

    func testCommandAndShiftTogetherPreventOpen() {
        let result = SidebarRowInteraction.shouldOpenPDF(modifiers: [.command, .shift])

        XCTAssertFalse(result)
    }

    func testUnrelatedModifierLikeOptionStillOpens() {
        let result = SidebarRowInteraction.shouldOpenPDF(modifiers: [.option])

        XCTAssertTrue(result)
    }
}
