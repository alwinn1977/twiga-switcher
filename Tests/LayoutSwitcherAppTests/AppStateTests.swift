import XCTest
import LayoutSwitcherCore
@testable import LayoutSwitcherApp

private final class StubPermissionManager: PermissionManaging {
    var value: PermissionSnapshot = .granted
    private(set) var requested: [PermissionKind] = []
    private(set) var opened: [PermissionKind] = []
    func snapshot() -> PermissionSnapshot { value }
    func request(_ kind: PermissionKind) { requested.append(kind) }
    func openSettings(_ kind: PermissionKind) { opened.append(kind) }
}

private final class StubKeyboardMonitor: KeyboardMonitoring, @unchecked Sendable {
    var isRunning = false
    var onStopped: ((String) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onLatestDecision: ((CorrectionPair?) -> Void)?
    var onInputSourcesChanged: (() -> Void)?
    var missingLayouts: [KeyboardLayout] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var savedRule: (UserCorrectionDisposition, CorrectionPair)?
    private(set) var configuredHotkeys: HotkeyConfiguration?
    private(set) var configuredSound: Bool?

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

    func setHotkeys(_ hotkeys: HotkeyConfiguration) { configuredHotkeys = hotkeys }
    func setSoundEnabled(_ enabled: Bool) { configuredSound = enabled }
}

final class AppStateTests: XCTestCase {
    @MainActor
    func testRuleSuggestionSurvivesMoreTypingAndSavesThePresentedPair() {
        let monitor = StubKeyboardMonitor()
        let controller = AppController(permissions: StubPermissionManager(), monitor: monitor, initialEnabled: true)
        let pair = CorrectionPair(source: "qzq", candidate: "йяй")
        monitor.onLatestDecision?(pair)
        monitor.onLatestDecision?(nil)
        XCTAssertNil(controller.latestDecisionPair)
        XCTAssertEqual(controller.pendingRuleSuggestion, pair)
        controller.saveSuggestedRule(.always)
        XCTAssertEqual(monitor.savedRule?.1, pair)
        XCTAssertNil(controller.pendingRuleSuggestion)
    }

    @MainActor
    func testDismissedSuggestionDoesNotSaveRuleAndCanBeOfferedAgain() {
        let monitor = StubKeyboardMonitor()
        let controller = AppController(permissions: StubPermissionManager(), monitor: monitor, initialEnabled: true)
        let pair = CorrectionPair(source: "qzq", candidate: "йяй")
        monitor.onLatestDecision?(pair)
        controller.dismissRuleSuggestion()
        XCTAssertNil(monitor.savedRule)
        monitor.onLatestDecision?(pair)
        XCTAssertEqual(controller.pendingRuleSuggestion, pair)
    }

    @MainActor
    func testMissingLayoutsClearAutomaticallyWhenSourcesAreAdded() {
        let monitor = StubKeyboardMonitor()
        let controller = AppController(permissions: StubPermissionManager(), monitor: monitor, initialEnabled: true)
        monitor.missingLayouts = [.russian, .english]
        monitor.onInputSourcesChanged?()
        XCTAssertTrue(controller.inputSourceError?.contains("Russian") == true)
        XCTAssertTrue(controller.inputSourceError?.contains("English") == true)
        guard case .error = controller.state else { return XCTFail("Missing sources must be visible") }
        monitor.missingLayouts = []
        monitor.onInputSourcesChanged?()
        XCTAssertNil(controller.inputSourceError)
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(monitor.startCount, 1)
    }

    @MainActor
    func testPermissionActionsAreSpecificAndRefreshStatus() {
        let permissions = StubPermissionManager()
        permissions.value = .init(accessibility: false, inputMonitoring: true)
        let controller = AppController(permissions: permissions, monitor: StubKeyboardMonitor(), initialEnabled: true)
        XCTAssertEqual(controller.permissionSnapshot.accessibility, false)
        controller.requestPermission(.accessibility)
        controller.openPermissionSettings(.accessibility)
        XCTAssertEqual(permissions.requested, [.accessibility])
        XCTAssertEqual(permissions.opened, [.accessibility])
        permissions.value = .granted
        controller.refresh()
        XCTAssertEqual(controller.permissionSnapshot, .granted)
    }

    @MainActor
    func testApplicationRuleChangesPersistAndAppearInSettings() throws {
        let suite = "ControllerApplicationRules-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = AppController(permissions: StubPermissionManager(), monitor: StubKeyboardMonitor(), initialEnabled: false, defaults: defaults)
        controller.addApplication(bundleID: "com.example.Editor", name: "Editor")
        controller.setApplicationMode(.disabled, for: "com.example.Editor")
        XCTAssertEqual(controller.applicationRules.first(where: { $0.bundleID == "com.example.Editor" })?.mode, .disabled)
        XCTAssertEqual(ApplicationRulesStore(defaults: defaults).mode(for: "com.example.Editor"), .disabled)
    }

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

    @MainActor
    func testShortcutAndSoundPreferencesApplyImmediatelyAndPersist() throws {
        let suiteName = "AppStatePreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HotkeyStore(defaults: defaults)
        let monitor = StubKeyboardMonitor()
        let controller = AppController(
            permissions: StubPermissionManager(),
            monitor: monitor,
            initialEnabled: true,
            hotkeyStore: store,
            defaults: defaults
        )
        let custom = Hotkey(keyCode: 35, modifiers: [.maskCommand, .maskShift], label: "P")

        XCTAssertTrue(controller.setHotkey(custom, for: .undoCorrection))
        XCTAssertEqual(monitor.configuredHotkeys?.undo, custom)
        XCTAssertEqual(store.configuration.undo, custom)
        controller.setSoundEnabled(false)
        XCTAssertEqual(monitor.configuredSound, false)
        XCTAssertFalse(defaults.bool(forKey: "layoutSwitchSoundEnabled"))
    }

    @MainActor
    func testInterfaceLanguageDefaultsToSystemAndPersistsExplicitChoice() throws {
        let suiteName = "AppLanguagePreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = AppController(
            permissions: StubPermissionManager(),
            monitor: StubKeyboardMonitor(),
            initialEnabled: false,
            hotkeyStore: HotkeyStore(defaults: defaults),
            defaults: defaults
        )

        XCTAssertEqual(controller.interfaceLanguage, .system)
        controller.setInterfaceLanguage(.russian)
        XCTAssertEqual(controller.interfaceLanguage, .russian)
        XCTAssertEqual(defaults.string(forKey: "interfaceLanguage"), "russian")
        controller.setInterfaceLanguage(.system)
        XCTAssertEqual(defaults.string(forKey: "interfaceLanguage"), "system")
    }
}
