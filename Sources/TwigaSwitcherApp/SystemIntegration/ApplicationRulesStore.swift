import Foundation

public enum ApplicationCorrectionMode: String, CaseIterable, Sendable {
    case standard
    case disabled
    case compatibility
}

public struct ApplicationRule: Identifiable, Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let mode: ApplicationCorrectionMode
    public let isBuiltIn: Bool
    public var id: String { bundleID }
}

public struct ApplicationRulesStore {
    private static let modesKey = "applicationCorrectionModes"
    private static let namesKey = "applicationCorrectionNames"
    public static let builtIns: [(bundleID: String, name: String, mode: ApplicationCorrectionMode)] = [
        ("com.apple.Terminal", "Terminal", .disabled),
        ("com.googlecode.iterm2", "iTerm", .disabled),
        ("com.apple.ScreenSharing", "Screen Sharing", .disabled),
        ("com.microsoft.rdc.macos", "Microsoft Remote Desktop", .disabled),
        ("com.realvnc.vncviewer", "RealVNC Viewer", .disabled),
        ("com.openai.codex", "Codex", .compatibility),
        ("us.zoom.xos", "Zoom Workplace", .compatibility),
    ]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var overrides: [String: ApplicationCorrectionMode] {
        (defaults.dictionary(forKey: Self.modesKey) as? [String: String] ?? [:])
            .compactMapValues(ApplicationCorrectionMode.init(rawValue:))
    }

    public func mode(for bundleID: String) -> ApplicationCorrectionMode {
        overrides[bundleID]
            ?? Self.builtIns.first(where: { $0.bundleID == bundleID })?.mode
            ?? .standard
    }

    public var rules: [ApplicationRule] {
        let builtIns = Self.builtIns.map {
            ApplicationRule(bundleID: $0.bundleID, name: $0.name, mode: mode(for: $0.bundleID), isBuiltIn: true)
        }
        let names = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        let custom = names.keys.sorted().compactMap { id -> ApplicationRule? in
            guard !Self.builtIns.contains(where: { $0.bundleID == id }), let name = names[id] else { return nil }
            return ApplicationRule(bundleID: id, name: name, mode: mode(for: id), isBuiltIn: false)
        }
        return builtIns + custom
    }

    public func setMode(_ mode: ApplicationCorrectionMode, for bundleID: String) {
        var modes = defaults.dictionary(forKey: Self.modesKey) as? [String: String] ?? [:]
        modes[bundleID] = mode.rawValue
        defaults.set(modes, forKey: Self.modesKey)
    }

    public func addApplication(bundleID: String, name: String) {
        guard !bundleID.isEmpty, !Self.builtIns.contains(where: { $0.bundleID == bundleID }) else { return }
        var names = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        names[bundleID] = name
        defaults.set(names, forKey: Self.namesKey)
    }

    public func removeApplication(bundleID: String) {
        guard !Self.builtIns.contains(where: { $0.bundleID == bundleID }) else { return }
        var names = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        names.removeValue(forKey: bundleID)
        defaults.set(names, forKey: Self.namesKey)
        var modes = defaults.dictionary(forKey: Self.modesKey) as? [String: String] ?? [:]
        modes.removeValue(forKey: bundleID)
        defaults.set(modes, forKey: Self.modesKey)
    }
}
