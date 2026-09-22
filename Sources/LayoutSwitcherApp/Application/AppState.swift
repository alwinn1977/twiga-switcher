public enum AppState: Equatable, Sendable {
    case active
    case paused
    case permissionsRequired
    case error(String)

    public static func resolve(enabled: Bool, permissions: PermissionSnapshot, monitorRunning: Bool, error: String?) -> AppState {
        guard enabled else { return .paused }
        guard permissions.accessibility && permissions.inputMonitoring else { return .permissionsRequired }
        if let error { return .error(error) }
        return monitorRunning ? .active : .error("Event monitor is not running")
    }

    public var title: String {
        switch self {
        case .active: return "Automatic correction is active"
        case .paused: return "Automatic correction is paused"
        case .permissionsRequired: return "Permissions required"
        case let .error(message): return message
        }
    }

    public var systemImage: String {
        switch self {
        case .active: return "keyboard.badge.ellipsis"
        case .paused: return "pause.circle"
        case .permissionsRequired: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
}
