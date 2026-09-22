import AppKit
import ApplicationServices
import CoreGraphics

public struct PermissionSnapshot: Equatable, Sendable { public let accessibility: Bool; public let inputMonitoring: Bool; public static let granted = Self(accessibility: true, inputMonitoring: true) }
public struct PermissionManager {
    public init() {}
    public func snapshot() -> PermissionSnapshot { .init(accessibility: AXIsProcessTrusted(), inputMonitoring: CGPreflightListenEventAccess()) }
    public func request() { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary); _ = CGRequestListenEventAccess() }
    public func openSettings() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
}
