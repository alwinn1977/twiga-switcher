import AppKit
import ApplicationServices

public struct FocusIdentity: Equatable, @unchecked Sendable {
    public let processID: pid_t
    public let elementHash: UInt
    private let element: AXUIElement?

    public init(processID: pid_t, elementHash: UInt) {
        self.processID = processID
        self.elementHash = elementHash
        self.element = nil
    }

    fileprivate init(processID: pid_t, element: AXUIElement) {
        self.processID = processID
        self.elementHash = CFHash(element)
        self.element = element
    }

    public static func == (lhs: FocusIdentity, rhs: FocusIdentity) -> Bool {
        guard lhs.processID == rhs.processID else { return false }
        if let lhsElement = lhs.element, let rhsElement = rhs.element {
            return CFEqual(lhsElement, rhsElement)
        }
        return lhs.elementHash == rhs.elementHash
    }
}

public struct FocusSnapshot: Equatable, Sendable {
    public let identity: FocusIdentity

    public init(identity: FocusIdentity) {
        self.identity = identity
    }
}

public struct FocusDescriptor: Sendable {
    public let bundleID: String?
    public let role: String?
    public let subrole: String?
    public let valueIsSettable: Bool
    public let subroleLookupSucceeded: Bool
    public let settableLookupSucceeded: Bool

    public init(
        bundleID: String?,
        role: String?,
        subrole: String?,
        valueIsSettable: Bool,
        subroleLookupSucceeded: Bool = true,
        settableLookupSucceeded: Bool = true
    ) {
        self.bundleID = bundleID
        self.role = role
        self.subrole = subrole
        self.valueIsSettable = valueIsSettable
        self.subroleLookupSucceeded = subroleLookupSucceeded
        self.settableLookupSucceeded = settableLookupSucceeded
    }
}

public struct FocusSafetyPolicy: Sendable {
    private let overrides: [String: ApplicationCorrectionMode]

    public init(overrides: [String: ApplicationCorrectionMode] = [:]) { self.overrides = overrides }

    private func mode(for bundleID: String) -> ApplicationCorrectionMode {
        overrides[bundleID]
            ?? ApplicationRulesStore.builtIns.first(where: { $0.bundleID == bundleID })?.mode
            ?? .standard
    }

    public func isSafe(_ descriptor: FocusDescriptor) -> Bool {
        guard let bundleID = descriptor.bundleID,
              mode(for: bundleID) != .disabled,
              let role = descriptor.role,
              descriptor.subroleLookupSucceeded,
              descriptor.settableLookupSucceeded,
              descriptor.valueIsSettable,
              descriptor.subrole != "AXSecureTextField" else {
            return false
        }

        if ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) {
            return true
        }
        return mode(for: bundleID) == .compatibility && role == "AXGroup"
    }

    public func allowsApplicationLevelFallback(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return mode(for: bundleID) == .compatibility
    }
}

public protocol FocusSnapshotProviding {
    func snapshot() -> FocusSnapshot?
}

public struct FocusSafetyGuard: FocusSnapshotProviding {
    private let messagingTimeout: Float
    private let defaults: UserDefaults

    public init(messagingTimeout: Float = 0.05, defaults: UserDefaults = .standard) {
        self.messagingTimeout = messagingTimeout
        self.defaults = defaults
    }

    public func snapshot() -> FocusSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let processID = app.processIdentifier
        let axApp = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(axApp, messagingTimeout)

        let policy = FocusSafetyPolicy(overrides: ApplicationRulesStore(defaults: defaults).overrides)
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        if focusedResult == .noValue,
           policy.allowsApplicationLevelFallback(bundleID: app.bundleIdentifier) {
            return FocusSnapshot(identity: FocusIdentity(
                processID: processID,
                elementHash: UInt(UInt32(bitPattern: processID))
            ))
        }
        guard focusedResult == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let element = unsafeDowncast(focusedValue as AnyObject, to: AXUIElement.self)
        // AX timeouts belong to an individual object; the app's timeout does not
        // propagate to its focused field. Never let that field stall the event tap.
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        guard let role = stringAttribute(kAXRoleAttribute, from: element) else { return nil }
        let subrole = optionalStringAttribute(kAXSubroleAttribute, from: element)
        guard subrole.succeeded, subrole.value != "AXSecureTextField" else { return nil }

        var settable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        )

        let descriptor = FocusDescriptor(
            bundleID: app.bundleIdentifier,
            role: role,
            subrole: subrole.value,
            valueIsSettable: settable.boolValue,
            subroleLookupSucceeded: subrole.succeeded,
            settableLookupSucceeded: settableResult == .success
        )
        guard policy.isSafe(descriptor) else { return nil }

        return FocusSnapshot(identity: FocusIdentity(processID: processID, element: element))
    }

    private func stringAttribute(_ key: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success,
              let string = value as? String else {
            return nil
        }
        return string
    }

    private func optionalStringAttribute(
        _ key: String,
        from element: AXUIElement
    ) -> (value: String?, succeeded: Bool) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)

        switch result {
        case .success:
            guard let value else { return (nil, true) }
            guard let string = value as? String else { return (nil, false) }
            return (string, true)
        case .noValue, .attributeUnsupported:
            return (nil, true)
        default:
            return (nil, false)
        }
    }
}
