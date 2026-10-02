import Foundation

public enum ApplicationCorrectionMode: String, CaseIterable, Decodable, Sendable {
    case standard
    case disabled
    case compatibility
    case unchecked
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
    // Configuration and Launch Services are read once, outside the keyboard callback.
    public static let builtIns: [ConfiguredApplication] = {
        let configuration = ApplicationDefaultsConfiguration.bundled
        return makeBuiltIns(
            configuration: configuration,
            browsers: InstalledBrowserDiscovery.discover(urlSchemes: configuration.browserDiscovery.urlSchemes)
        )
    }()

    static func makeBuiltIns(
        configuration: ApplicationDefaultsConfiguration,
        browsers: [InstalledBrowser]
    ) -> [ConfiguredApplication] {
        var rules = configuration.applications
        var ids = Set(rules.map(\.bundleID))
        for browser in browsers.sorted(by: { ($0.name, $0.bundleID) < ($1.name, $1.bundleID) }) {
            guard ids.insert(browser.bundleID).inserted else { continue }
            rules.append(.init(bundleID: browser.bundleID, name: browser.name, mode: configuration.browserDiscovery.mode))
        }
        return rules
    }

    private let defaults: UserDefaults
    private let builtInRules: [ConfiguredApplication]

    public init(defaults: UserDefaults = .standard, builtIns: [ConfiguredApplication] = Self.builtIns) {
        self.defaults = defaults
        self.builtInRules = builtIns
    }

    public var overrides: [String: ApplicationCorrectionMode] {
        (defaults.dictionary(forKey: Self.modesKey) as? [String: String] ?? [:])
            .compactMapValues(ApplicationCorrectionMode.init(rawValue:))
    }

    public func mode(for bundleID: String) -> ApplicationCorrectionMode {
        overrides[bundleID]
            ?? builtInRules.first(where: { $0.bundleID == bundleID })?.mode
            ?? .standard
    }

    public var rules: [ApplicationRule] {
        let builtIns = builtInRules.map {
            ApplicationRule(bundleID: $0.bundleID, name: $0.name, mode: mode(for: $0.bundleID), isBuiltIn: true)
        }
        let names = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        // An override of a former default has no saved name. Keep it visible as a custom rule.
        let custom = Set(names.keys).union(overrides.keys).sorted().compactMap { id -> ApplicationRule? in
            guard !builtInRules.contains(where: { $0.bundleID == id }) else { return nil }
            let name = names[id] ?? id
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
        guard !bundleID.isEmpty, !builtInRules.contains(where: { $0.bundleID == bundleID }) else { return }
        var names = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        names[bundleID] = name
        defaults.set(names, forKey: Self.namesKey)
    }

    public func removeApplication(bundleID: String) {
        guard !builtInRules.contains(where: { $0.bundleID == bundleID }) else { return }
        var names = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        names.removeValue(forKey: bundleID)
        defaults.set(names, forKey: Self.namesKey)
        var modes = defaults.dictionary(forKey: Self.modesKey) as? [String: String] ?? [:]
        modes.removeValue(forKey: bundleID)
        defaults.set(modes, forKey: Self.modesKey)
    }
}
