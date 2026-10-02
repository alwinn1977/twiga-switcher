import Foundation
import TwigaSwitcherCore

public struct ConfiguredApplication: Decodable, Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let mode: ApplicationCorrectionMode
}

public struct BrowserDiscoveryConfiguration: Decodable, Sendable {
    public let urlSchemes: [String]
    public let mode: ApplicationCorrectionMode
}

public struct ApplicationDefaultsConfiguration: Decodable, Sendable {
    public let applications: [ConfiguredApplication]
    public let browserDiscovery: BrowserDiscoveryConfiguration

    public static let bundled: Self = ConfigurationResource.load("Applications")

    private enum CodingKeys: String, CodingKey { case applications, browserDiscovery }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applications = try container.decode([ConfiguredApplication].self, forKey: .applications)
        browserDiscovery = try container.decode(BrowserDiscoveryConfiguration.self, forKey: .browserDiscovery)
        guard Set(applications.map(\.bundleID)).count == applications.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .applications, in: container, debugDescription: "Application bundle IDs must be unique"
            )
        }
    }
}

public struct LanguageLayoutConfiguration: Decodable, Sendable {
    public let inputSourceIDs: [String]
    public let primaryLanguage: String
}

public struct KeyboardLayoutsConfiguration: Decodable, Sendable {
    public let english: LanguageLayoutConfiguration
    public let russian: LanguageLayoutConfiguration

    public static let bundled: Self = ConfigurationResource.load("KeyboardLayouts")

    private enum CodingKeys: String, CodingKey { case english, russian }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        english = try container.decode(LanguageLayoutConfiguration.self, forKey: .english)
        russian = try container.decode(LanguageLayoutConfiguration.self, forKey: .russian)
        guard Set(english.inputSourceIDs).isDisjoint(with: russian.inputSourceIDs) else {
            throw DecodingError.dataCorruptedError(
                forKey: .russian, in: container, debugDescription: "An input source cannot belong to both languages"
            )
        }
    }

    public func sources(for layout: KeyboardLayout) -> LanguageLayoutConfiguration {
        layout == .english ? english : russian
    }
}

private enum ConfigurationResource {
    static func load<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Configuration") else {
            preconditionFailure("Missing bundled configuration: \(name).json")
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            preconditionFailure("Invalid bundled configuration \(name).json: \(error)")
        }
    }
}
