import AppKit
import Combine
import TwigaSwitcherCore
import ServiceManagement

@MainActor
public final class AppController: ObservableObject {
    @Published public private(set) var state: AppState = .paused
    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var pendingRuleSuggestion: CorrectionPair?
    @Published public private(set) var missingLayouts: [KeyboardLayout] = []
    private let presentDialogs: Bool
    private var ruleDialog: NSPanel?
    private var layoutDialog: NSPanel?
    @Published public private(set) var latestDecisionPair: CorrectionPair?
    @Published public private(set) var hotkeys: HotkeyConfiguration
    @Published public private(set) var soundEnabled: Bool
    @Published public private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    @Published public private(set) var launchAtLoginError: String?
    @Published public private(set) var shortcutError: String?
    @Published public private(set) var interfaceLanguage: InterfaceLanguage
    @Published public private(set) var permissionSnapshot: PermissionSnapshot = .init(accessibility: false, inputMonitoring: false)
    @Published public private(set) var applicationRules: [ApplicationRule] = []

    private let permissions: any PermissionManaging
    private let monitor: any KeyboardMonitoring
    private let hotkeyStore: HotkeyStore
    private let defaults: UserDefaults
    private let loginItem: any LoginItemManaging
    private let applicationRulesStore: ApplicationRulesStore
    private var lastError: String?
    private var activationObserver: NSObjectProtocol?

    public init(
        permissions: any PermissionManaging = PermissionManager(),
        monitor: any KeyboardMonitoring = KeyboardMonitor(),
        initialEnabled: Bool? = nil,
        hotkeyStore: HotkeyStore = HotkeyStore(),
        defaults: UserDefaults = .standard,
        presentDialogs: Bool = false,
        loginItem: any LoginItemManaging = LoginItemManager()
    ) {
        self.presentDialogs = presentDialogs
        self.permissions = permissions
        self.monitor = monitor
        self.hotkeyStore = hotkeyStore
        self.defaults = defaults
        self.loginItem = loginItem
        self.applicationRulesStore = ApplicationRulesStore(defaults: defaults)
        self.applicationRules = applicationRulesStore.rules
        self.hotkeys = hotkeyStore.configuration
        self.soundEnabled = defaults.object(forKey: "layoutSwitchSoundEnabled") as? Bool ?? true
        self.interfaceLanguage = InterfaceLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .system
        self.isEnabled = initialEnabled
            ?? defaults.object(forKey: "automaticCorrectionEnabled") as? Bool
            ?? true
        monitor.setHotkeys(hotkeys)
        monitor.setSoundEnabled(soundEnabled)
        monitor.onStopped = { [weak self] message in
            MainActor.assumeIsolated {
                self?.handleMonitorStopped(message)
            }
        }
        monitor.onDiagnostic = { [weak self] message in
            MainActor.assumeIsolated {
                self?.handleMonitorDiagnostic(message)
            }
        }
        monitor.onLatestDecision = { [weak self] pair in
            MainActor.assumeIsolated {
                self?.latestDecisionPair = pair
                if let pair { self?.offerRule(pair) }
            }
        }
        monitor.onInputSourcesChanged = { [weak self] in
            MainActor.assumeIsolated { self?.updateInputSourceStatus() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    public var inputSourceError: String? {
        guard !missingLayouts.isEmpty else { return nil }
        return missingLayouts.map { $0 == .russian
            ? InterfaceText.russianInputSourceUnavailable.localized(.english)
            : InterfaceText.englishInputSourceUnavailable.localized(.english) }.joined(separator: "\n")
    }

    private func updateInputSourceStatus() {
        let previous = missingLayouts
        missingLayouts = monitor.missingLayouts
        state = .resolve(enabled: isEnabled, permissions: permissionSnapshot,
                         monitorRunning: monitor.isRunning, error: lastError ?? inputSourceError)
        guard presentDialogs, previous != missingLayouts else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutDialog?.close()
            self.layoutDialog = nil
            guard let message = self.inputSourceError else { return }
            self.layoutDialog = SuggestionDialogs.missingLayouts(message: InterfaceText.diagnostic(message, in: self.displayLanguage), language: self.displayLanguage)
        }
    }

    private func offerRule(_ pair: CorrectionPair) {
        guard pendingRuleSuggestion != pair else { return }
        pendingRuleSuggestion = pair
        guard presentDialogs else { return }
        // Present outside the event-tap callback; the immutable pair survives typing,
        // mouse events and activation of the dialog itself.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingRuleSuggestion == pair else { return }
            self.ruleDialog?.close()
            self.ruleDialog = SuggestionDialogs.rule(pair: pair, language: self.displayLanguage) { [weak self] disposition in
                guard let self, self.pendingRuleSuggestion == pair else { return }
                if let disposition { self.saveSuggestedRule(disposition) }
                else { self.dismissRuleSuggestion() }
            }
        }
    }

    public func dismissRuleSuggestion() {
        pendingRuleSuggestion = nil
        ruleDialog?.close()
        ruleDialog = nil
    }

    public func saveSuggestedRule(_ disposition: UserCorrectionDisposition) {
        guard let pair = pendingRuleSuggestion else { return }
        do {
            try monitor.setRule(disposition, for: pair)
            dismissRuleSuggestion()
        } catch { handleMonitorDiagnostic("Unable to save learned rule") }
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "automaticCorrectionEnabled")
        lastError = nil
        refresh()
    }

    public func refresh() {
        let loginItemStatus = loginItem.status
        if loginItemStatus != launchAtLoginStatus { launchAtLoginError = nil }
        launchAtLoginStatus = loginItemStatus
        let snapshot = permissions.snapshot()
        permissionSnapshot = snapshot
        if isEnabled && snapshot == .granted && lastError == nil {
            if !monitor.isRunning && !monitor.start() {
                lastError = monitor.startError ?? "Unable to start keyboard monitor"
            }
        } else if !isEnabled || snapshot != .granted {
            monitor.stop()
        }
        state = .resolve(enabled: isEnabled, permissions: snapshot, monitorRunning: monitor.isRunning, error: lastError ?? inputSourceError)
    }

    public func requestPermission(_ kind: PermissionKind) { permissions.request(kind); refresh() }
    public func openPermissionSettings(_ kind: PermissionKind) { permissions.openSettings(kind) }

    public func setApplicationMode(_ mode: ApplicationCorrectionMode, for bundleID: String) {
        applicationRulesStore.setMode(mode, for: bundleID)
        applicationRules = applicationRulesStore.rules
    }

    public func addApplication(bundleID: String, name: String) {
        applicationRulesStore.addApplication(bundleID: bundleID, name: name)
        applicationRules = applicationRulesStore.rules
    }

    public func removeApplication(bundleID: String) {
        applicationRulesStore.removeApplication(bundleID: bundleID)
        applicationRules = applicationRulesStore.rules
    }

    public func restartMonitor() {
        monitor.stop()
        lastError = nil
        refresh()
    }

    public func setLatestRule(_ disposition: UserCorrectionDisposition) {
        guard let pair = latestDecisionPair else { return }
        do {
            try monitor.setRule(disposition, for: pair)
        } catch {
            handleMonitorDiagnostic("Unable to save learned rule")
        }
    }

    @discardableResult
    public func setHotkey(_ hotkey: Hotkey, for action: HotkeyAction) -> Bool {
        guard hotkeyStore.set(hotkey, for: action) else {
            shortcutError = "Choose a valid shortcut that differs from the other action."
            return false
        }
        hotkeys = hotkeyStore.configuration
        monitor.setHotkeys(hotkeys)
        shortcutError = nil
        return true
    }

    public func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        defaults.set(enabled, forKey: "layoutSwitchSoundEnabled")
        monitor.setSoundEnabled(enabled)
    }

    // macOS owns persistence. Reading status never opts the user into autostart.
    // A pending registration stays on so it can also be cancelled with the toggle.
    public var launchAtLoginEnabled: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginStatus = loginItem.status
        launchAtLoginError = nil
        guard enabled != launchAtLoginEnabled else { return }
        do {
            if enabled { try loginItem.register() }
            else { try loginItem.unregister() }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLoginStatus = loginItem.status
    }

    public func openLoginItemSettings() { loginItem.openSettings() }

    public var displayLanguage: DisplayLanguage { interfaceLanguage.resolve() }

    public func setInterfaceLanguage(_ language: InterfaceLanguage) {
        interfaceLanguage = language
        defaults.set(language.rawValue, forKey: "interfaceLanguage")
    }

    public func reloadDictionaries() async {
        await monitor.reloadDictionaries()
    }

    private func handleMonitorStopped(_ message: String) {
        lastError = message
        state = .resolve(
            enabled: isEnabled,
            permissions: permissions.snapshot(),
            monitorRunning: false,
            error: message
        )
    }

    private func handleMonitorDiagnostic(_ message: String) {
        lastError = message
        state = .resolve(
            enabled: isEnabled,
            permissions: permissions.snapshot(),
            monitorRunning: monitor.isRunning,
            error: message
        )
    }
}
