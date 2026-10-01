import TwigaSwitcherCore
@testable import TwigaSwitcherApp
import XCTest

final class KeyboardMonitorDecisionTests: XCTestCase {
    func testResetBufferPublishesClearedDecision() {
        let monitor = KeyboardMonitor()
        var updates: [CorrectionPair?] = []
        monitor.onLatestDecision = { updates.append($0) }

        monitor.resetBuffer()

        XCTAssertEqual(updates.count, 1)
        guard let update = updates.first else { return }
        XCTAssertNil(update)
    }
}
