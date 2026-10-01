import XCTest
@testable import TwigaSwitcherCore

final class TapHealthTests: XCTestCase {
    func testTapRetriesOnceThenStopsUntilHealthyEvent() {
        var health = TapHealth(maximumReenableAttempts: 1)
        XCTAssertEqual(health.handleDisable(), .reenable)
        XCTAssertEqual(health.handleDisable(), .stop)
        health.recordHealthyEvent()
        XCTAssertEqual(health.handleDisable(), .reenable)
    }
}
