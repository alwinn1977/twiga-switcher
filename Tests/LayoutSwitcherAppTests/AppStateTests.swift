import XCTest
@testable import LayoutSwitcherApp

final class AppStateTests: XCTestCase {
    func testEnabledAppStartsOnlyWithBothPermissions() {
        XCTAssertEqual(AppState.resolve(enabled: true, permissions: .granted, monitorRunning: true, error: nil), .active)
        XCTAssertEqual(AppState.resolve(enabled: true, permissions: .init(accessibility: true, inputMonitoring: false), monitorRunning: false, error: nil), .permissionsRequired)
    }

    func testDisabledAndFailureStatesRemainVisible() {
        XCTAssertEqual(AppState.resolve(enabled: false, permissions: .granted, monitorRunning: false, error: nil), .paused)
        XCTAssertEqual(AppState.resolve(enabled: true, permissions: .granted, monitorRunning: false, error: "Event monitor stopped"), .error("Event monitor stopped"))
    }
}
