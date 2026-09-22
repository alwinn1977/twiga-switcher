import Foundation

public final class ComputerTermsSettings: @unchecked Sendable {
    public static let shared = ComputerTermsSettings()

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "computerTermsDictionaryEnabled"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public var isEnabled: Bool {
        get {
            guard defaults.object(forKey: key) != nil else { return true }
            return defaults.bool(forKey: key)
        }
        set { defaults.set(newValue, forKey: key) }
    }
}
