import AppKit
import ApplicationServices

private enum SpotlightFocus {
    static func isSearchHost(_ bundleID: String?) -> Bool {
        bundleID == "com.apple.Spotlight" || bundleID == "com.apple.campo"
    }

    static func matches(bundleID: String?, elementIdentifier: String?) -> Bool {
        bundleID == "com.apple.Spotlight"
            || (bundleID == "com.apple.campo" && elementIdentifier == "SpotlightSearchField")
    }
}

public struct FocusIdentity: Equatable, @unchecked Sendable {
    public let processID: pid_t
    public let elementHash: UInt
    private let element: AXUIElement?
    var accessibilityElement: AXUIElement? { element }

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
    public let bundleID: String?
    public let elementIdentifier: String?
    var isSpotlightSearch: Bool {
        SpotlightFocus.matches(bundleID: bundleID, elementIdentifier: elementIdentifier)
    }

    public init(identity: FocusIdentity, bundleID: String? = nil, elementIdentifier: String? = nil) {
        self.identity = identity
        self.bundleID = bundleID
        self.elementIdentifier = elementIdentifier
    }
}

public struct FocusDescriptor: Sendable {
    public let bundleID: String?
    public let role: String?
    public let subrole: String?
    public let valueIsSettable: Bool
    public let subroleLookupSucceeded: Bool
    public let settableLookupSucceeded: Bool
    public let elementIdentifier: String?

    public init(
        bundleID: String?,
        role: String?,
        subrole: String?,
        valueIsSettable: Bool,
        subroleLookupSucceeded: Bool = true,
        settableLookupSucceeded: Bool = true,
        elementIdentifier: String? = nil
    ) {
        self.bundleID = bundleID
        self.role = role
        self.subrole = subrole
        self.valueIsSettable = valueIsSettable
        self.subroleLookupSucceeded = subroleLookupSucceeded
        self.settableLookupSucceeded = settableLookupSucceeded
        self.elementIdentifier = elementIdentifier
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
        // New macOS versions host Spotlight in Siri AI. Keep the Spotlight
        // application setting attached to its search field, not Siri conversations.
        let correctionBundleID = SpotlightFocus.matches(
            bundleID: descriptor.bundleID, elementIdentifier: descriptor.elementIdentifier
        ) ? "com.apple.Spotlight" : descriptor.bundleID
        if usesApplicationFocus(bundleID: correctionBundleID) { return true }
        guard let bundleID = correctionBundleID,
              mode(for: bundleID) != .disabled,
              descriptor.subroleLookupSucceeded,
              descriptor.role != "AXSecureTextField",
              descriptor.subrole != "AXSecureTextField" else {
            return false
        }

        // Keyboard replacement does not require AXValue to be writable. Custom
        // editors may report a document container instead of a text field.
        // Compatibility keeps the focus identity and secure-field checks, but
        // deliberately does not use AX roles/capabilities to infer editability.
        if mode(for: bundleID) == .compatibility { return true }
        guard let role = descriptor.role,
              descriptor.settableLookupSucceeded,
              descriptor.valueIsSettable else { return false }
        return ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
    }

    public func allowsApplicationLevelFallback(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return mode(for: bundleID) == .compatibility
    }

    public func usesApplicationFocus(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return mode(for: bundleID) == .unchecked
    }
}

public protocol FocusSnapshotProviding {
    func snapshot() -> FocusSnapshot?
}

struct FocusApplication: Equatable {
    let processID: pid_t
    let bundleID: String?
}

protocol FocusAccessibilityReading {
    func focusedElement() -> (result: AXError, element: AXUIElement?)
    func focusedElement(in application: FocusApplication) -> (result: AXError, element: AXUIElement?)
    func focusedApplication() -> FocusApplication?
    func application(for element: AXUIElement) -> FocusApplication?
    func descriptor(for element: AXUIElement, bundleID: String?) -> FocusDescriptor?
}

public struct FocusSafetyGuard: FocusSnapshotProviding {
    private let defaults: UserDefaults
    private let frontmostApplication: () -> FocusApplication?
    private let accessibility: any FocusAccessibilityReading

    public init(messagingTimeout: Float = 0.05, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.frontmostApplication = {
            NSWorkspace.shared.frontmostApplication.map {
                FocusApplication(processID: $0.processIdentifier, bundleID: $0.bundleIdentifier)
            }
        }
        self.accessibility = SystemFocusAccessibilityReader(messagingTimeout: messagingTimeout)
    }

    init(
        defaults: UserDefaults,
        frontmostApplication: @escaping () -> FocusApplication?,
        accessibility: any FocusAccessibilityReading
    ) {
        self.defaults = defaults
        self.frontmostApplication = frontmostApplication
        self.accessibility = accessibility
    }

    public func snapshot() -> FocusSnapshot? {
        let policy = FocusSafetyPolicy(overrides: ApplicationRulesStore(defaults: defaults).overrides)
        let frontmost = frontmostApplication()
        // This explicit per-app mode must not query Accessibility at all.
        // Input boundaries, mouse events and app activation still clear the buffer.
        if let app = frontmost, policy.usesApplicationFocus(bundleID: app.bundleID) {
            return applicationSnapshot(app)
        }
        // System search panels can own keyboard focus while another application
        // remains frontmost. Its field and its rules must come from the AX owner.
        let focusedApplication = accessibility.focusedApplication()
        // Preserve the original per-application lookup when AX confirms that the
        // frontmost app owns focus. Electron fields can belong to a renderer, and
        // a system-wide query can differ from the host's focused-field query.
        var scopedApplication = frontmost.flatMap {
            $0.processID == focusedApplication?.processID && !SpotlightFocus.isSearchHost($0.bundleID) ? $0 : nil
        }
        var focused = scopedApplication.map { accessibility.focusedElement(in: $0) }
            ?? accessibility.focusedElement()
        // Codex/Electron can report no system-wide focused app AND no focused
        // element. That absence must not remove the original application query
        // or its explicitly configured compatibility fallback.
        if scopedApplication == nil, focusedApplication == nil,
           focused.result == .noValue, let frontmost {
            scopedApplication = frontmost
            focused = accessibility.focusedElement(in: frontmost)
        }
        if focused.result == .noValue {
            guard let app = scopedApplication ?? focusedApplication,
                  policy.allowsApplicationLevelFallback(bundleID: app.bundleID)
                    || policy.usesApplicationFocus(bundleID: app.bundleID) else { return nil }
            return applicationSnapshot(app)
        }
        guard focused.result == .success, let element = focused.element,
              let app = scopedApplication ?? accessibility.application(for: element) else { return nil }
        if policy.usesApplicationFocus(bundleID: app.bundleID) {
            return applicationSnapshot(app)
        }
        guard let descriptor = accessibility.descriptor(for: element, bundleID: app.bundleID),
              policy.isSafe(descriptor) else { return nil }

        return FocusSnapshot(
            identity: FocusIdentity(processID: app.processID, element: element),
            bundleID: app.bundleID, elementIdentifier: descriptor.elementIdentifier
        )
    }

    private func applicationSnapshot(_ app: FocusApplication) -> FocusSnapshot {
        FocusSnapshot(identity: FocusIdentity(
            processID: app.processID,
            elementHash: UInt(UInt32(bitPattern: app.processID))
        ), bundleID: app.bundleID)
    }
}

private struct SystemFocusAccessibilityReader: FocusAccessibilityReading {
    let messagingTimeout: Float

    func focusedElement() -> (result: AXError, element: AXUIElement?) {
        focusedElement(from: AXUIElementCreateSystemWide())
    }

    func focusedElement(in application: FocusApplication) -> (result: AXError, element: AXUIElement?) {
        focusedElement(from: AXUIElementCreateApplication(application.processID))
    }

    private func focusedElement(from root: AXUIElement) -> (result: AXError, element: AXUIElement?) {
        AXUIElementSetMessagingTimeout(root, messagingTimeout)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return (result == .success ? .failure : result, nil)
        }
        return (.success, unsafeDowncast(value as AnyObject, to: AXUIElement.self))
    }

    func focusedApplication() -> FocusApplication? {
        let root = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, messagingTimeout)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(root, kAXFocusedApplicationAttribute as CFString, &value)
        guard result == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return application(for: unsafeDowncast(value as AnyObject, to: AXUIElement.self))
    }

    func application(for element: AXUIElement) -> FocusApplication? {
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success, processID > 0,
              let app = NSRunningApplication(processIdentifier: processID) else { return nil }
        return FocusApplication(processID: processID, bundleID: app.bundleIdentifier)
    }

    func descriptor(for element: AXUIElement, bundleID: String?) -> FocusDescriptor? {
        // AX timeouts belong to an individual object; the root's timeout does not
        // propagate to its focused field. Never let that field stall the event tap.
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        let role = optionalStringAttribute(kAXRoleAttribute, from: element)
        guard role.succeeded else { return nil }
        let subrole = optionalStringAttribute(kAXSubroleAttribute, from: element)
        guard subrole.succeeded, subrole.value != "AXSecureTextField" else { return nil }

        var settable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        )
        return FocusDescriptor(
            bundleID: bundleID,
            role: role.value,
            subrole: subrole.value,
            valueIsSettable: settable.boolValue,
            subroleLookupSucceeded: subrole.succeeded,
            settableLookupSucceeded: settableResult == .success,
            elementIdentifier: stringAttribute(kAXIdentifierAttribute, from: element)
        )
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
