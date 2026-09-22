import AppKit
import Combine

@MainActor
public final class AppController: ObservableObject {
    @Published public private(set) var state: AppState = .paused
    @Published public private(set) var isEnabled: Bool

    private let permissions: PermissionManager
    private let monitor: KeyboardMonitor
    private var lastError: String?
    private var activationObserver: NSObjectProtocol?

    public init(permissions: PermissionManager = PermissionManager(), monitor: KeyboardMonitor = KeyboardMonitor()) {
        self.permissions = permissions
        self.monitor = monitor
        self.isEnabled = UserDefaults.standard.object(forKey: "automaticCorrectionEnabled") as? Bool ?? true
        monitor.onStopped = { [weak self] message in
            Task { @MainActor in self?.lastError = message; self?.refresh() }
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
        if isEnabled && snapshot == .granted {
            if !monitor.isRunning && !monitor.start() { lastError = "Unable to start keyboard monitor" }
        } else {
            monitor.stop()
        }
        state = .resolve(enabled: isEnabled, permissions: snapshot, monitorRunning: monitor.isRunning, error: lastError)
    }

    public func requestPermissions() { permissions.request(); refresh() }
    public func openPrivacySettings() { permissions.openSettings() }
}
