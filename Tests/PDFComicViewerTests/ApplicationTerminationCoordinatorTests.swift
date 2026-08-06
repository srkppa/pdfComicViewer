import XCTest
@testable import PDFComicViewer

@MainActor
final class ApplicationTerminationCoordinatorTests: XCTestCase {
    func testRepeatedTerminationRequestFlushesAndRepliesExactlyOnce() async throws {
        let coordinator = ApplicationTerminationCoordinator()
        var flushCount = 0
        var replies: [Bool] = []
        let flush: @MainActor () async -> Void = {
            flushCount += 1
            try? await Task.sleep(for: .milliseconds(20))
        }
        let reply: @MainActor (Bool) -> Void = { replies.append($0) }

        XCTAssertEqual(coordinator.requestTermination(flush: flush, reply: reply), .later)
        XCTAssertEqual(coordinator.requestTermination(flush: flush, reply: reply), .later)
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(flushCount, 1)
        XCTAssertEqual(replies, [true])
    }
}
