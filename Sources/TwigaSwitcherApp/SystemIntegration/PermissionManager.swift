import AppKit
import ApplicationServices
import CoreGraphics

public struct PermissionSnapshot: Equatable, Sendable {
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public static let granted = Self(accessibility: true, inputMonitoring: true)
}

public enum PermissionKind: Sendable {
    case accessibility
    case inputMonitoring
}

public protocol PermissionManaging {
    func snapshot() -> PermissionSnapshot
    func request(_ kind: PermissionKind)
    func openSettings(_ kind: PermissionKind)
}

public struct PermissionManager: PermissionManaging {
    public init() {}

    public func snapshot() -> PermissionSnapshot {
        .init(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess()
        )
    }

    public func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        }
    }

    public func openSettings(_ kind: PermissionKind) {
        let pane = kind == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
