import AppKit
import Combine
import LayoutSwitcherCore

@MainActor
public final class AppController: ObservableObject {
    @Published public private(set) var state: AppState = .paused
    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var latestDecisionPair: CorrectionPair?

    private let permissions: any PermissionManaging
    private let monitor: any KeyboardMonitoring
    private var lastError: String?
    private var activationObserver: NSObjectProtocol?

    public init(
        permissions: any PermissionManaging = PermissionManager(),
        monitor: any KeyboardMonitoring = KeyboardMonitor(),
        initialEnabled: Bool? = nil
    ) {
        self.permissions = permissions
        self.monitor = monitor
        self.isEnabled = initialEnabled
            ?? UserDefaults.standard.object(forKey: "automaticCorrectionEnabled") as? Bool
            ?? true
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
            MainActor.assumeIsolated { self?.latestDecisionPair = pair }
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

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "automaticCorrectionEnabled")
        lastError = nil
        refresh()
    }

    public func refresh() {
        let snapshot = permissions.snapshot()
        if isEnabled && snapshot == .granted && lastError == nil {
            if !monitor.isRunning && !monitor.start() {
                lastError = monitor.startError ?? "Unable to start keyboard monitor"
            }
        } else if !isEnabled || snapshot != .granted {
            monitor.stop()
        }
        state = .resolve(enabled: isEnabled, permissions: snapshot, monitorRunning: monitor.isRunning, error: lastError)
    }

    public func requestPermissions() { permissions.request(); refresh() }
    public func openPrivacySettings() { permissions.openSettings() }

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
