public enum TapDisableAction: Equatable, Sendable { case reenable, stop }

public struct TapHealth: Sendable {
    private let maximumReenableAttempts: Int
    private var attempts = 0
    public init(maximumReenableAttempts: Int) { self.maximumReenableAttempts = maximumReenableAttempts }
    public mutating func handleDisable() -> TapDisableAction {
        guard attempts < maximumReenableAttempts else { return .stop }
        attempts += 1; return .reenable
    }
    public mutating func recordHealthyEvent() { attempts = 0 }
}
