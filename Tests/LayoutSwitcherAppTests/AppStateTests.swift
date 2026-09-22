import XCTest
import LayoutSwitcherCore
@testable import LayoutSwitcherApp

private final class StubPermissionManager: PermissionManaging {
    var value: PermissionSnapshot = .granted
    func snapshot() -> PermissionSnapshot { value }
    func request() {}
    func openSettings() {}
}

private final class StubKeyboardMonitor: KeyboardMonitoring {
    var isRunning = false
    var onStopped: ((String) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onLatestDecision: ((CorrectionPair?) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var savedRule: (UserCorrectionDisposition, CorrectionPair)?

    func start() -> Bool {
        startCount += 1
        isRunning = true
        return true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func setRule(_ disposition: UserCorrectionDisposition, for pair: CorrectionPair) throws {
        savedRule = (disposition, pair)
    }
}

final class AppStateTests: XCTestCase {
    func testEnabledAppStartsOnlyWithBothPermissions() {
        XCTAssertEqual(AppState.resolve(enabled: true, permissions: .granted, monitorRunning: true, error: nil), .active)
        XCTAssertEqual(AppState.resolve(enabled: true, permissions: .init(accessibility: true, inputMonitoring: false), monitorRunning: false, error: nil), .permissionsRequired)
    }

    func testDisabledAndFailureStatesRemainVisible() {
        XCTAssertEqual(AppState.resolve(enabled: false, permissions: .granted, monitorRunning: false, error: nil), .paused)
        XCTAssertEqual(AppState.resolve(enabled: true, permissions: .granted, monitorRunning: false, error: "Event monitor stopped"), .error("Event monitor stopped"))
    }


    @MainActor
    func testFatalMonitorStopIsLatchedUntilExplicitRestart() {
        let permissions = StubPermissionManager()
        let monitor = StubKeyboardMonitor()
        let controller = AppController(permissions: permissions, monitor: monitor, initialEnabled: true)
        XCTAssertEqual(monitor.startCount, 1)

        monitor.isRunning = false
        monitor.onStopped?("Event monitor stopped")

        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertEqual(controller.state, .error("Event monitor stopped"))

        controller.restartMonitor()
        XCTAssertEqual(monitor.startCount, 2)
        XCTAssertEqual(controller.state, .active)
    }

    @MainActor
    func testMonitorDiagnosticIsVisibleWithoutRestarting() {
        let monitor = StubKeyboardMonitor()
        let controller = AppController(permissions: StubPermissionManager(), monitor: monitor, initialEnabled: true)

        monitor.onDiagnostic?("Russian input source is unavailable")

        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertEqual(controller.state, .error("Russian input source is unavailable"))
    }

    @MainActor
    func testLatestPairEnablesManualLearningAction() {
        let monitor = StubKeyboardMonitor()
        let controller = AppController(permissions: StubPermissionManager(), monitor: monitor, initialEnabled: true)
        let pair = CorrectionPair(source: "ghbdtn", candidate: "привет")

        monitor.onLatestDecision?(pair)
        controller.setLatestRule(.never)

        XCTAssertEqual(controller.latestDecisionPair, pair)
        XCTAssertEqual(monitor.savedRule?.0, .never)
        XCTAssertEqual(monitor.savedRule?.1, pair)
    }
}
