import AppKit
import ApplicationServices

public struct FocusDescriptor: Sendable {
    public let bundleID: String?; public let role: String?; public let subrole: String?; public let valueIsSettable: Bool
    public init(bundleID: String?, role: String?, subrole: String?, valueIsSettable: Bool) { self.bundleID = bundleID; self.role = role; self.subrole = subrole; self.valueIsSettable = valueIsSettable }
}
public struct FocusSafetyPolicy: Sendable {
    private let excluded = Set(["com.apple.Terminal","com.googlecode.iterm2","com.apple.ScreenSharing","com.microsoft.rdc.macos","com.realvnc.vncviewer"])
    public init() {}
    public func isSafe(_ d: FocusDescriptor) -> Bool { guard let id=d.bundleID, !excluded.contains(id), let role=d.role, d.valueIsSettable, d.subrole != "AXSecureTextField" else { return false }; return ["AXTextField","AXTextArea","AXComboBox"].contains(role) }
}
public struct FocusSafetyGuard {
    public init() {}
    public func isSafe() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier); var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &value) == .success, let value else { return false }
        let element = unsafeDowncast(value as AnyObject, to: AXUIElement.self)
        func string(_ key: String) -> String? { var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, key as CFString, &v) == .success else { return nil }; return v as? String }
        var settable = DarwinBoolean(false); AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return FocusSafetyPolicy().isSafe(.init(bundleID: app.bundleIdentifier, role: string(kAXRoleAttribute), subrole: string(kAXSubroleAttribute), valueIsSettable: settable.boolValue))
    }
}
