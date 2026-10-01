import Foundation

public struct DictionaryPackAttribution: Codable, Equatable, Sendable {
    public let source: String
    public let license: String

    public init(source: String, license: String) {
        self.source = source
        self.license = license
    }
}

public struct DictionaryPackManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let identifier: String
    public let name: String
    public let version: String
    public let description: String
    public let attribution: DictionaryPackAttribution

    public init(
        schemaVersion: Int = 1,
        identifier: String,
        name: String,
        version: String,
        description: String,
        attribution: DictionaryPackAttribution
    ) {
        self.schemaVersion = schemaVersion
        self.identifier = identifier
        self.name = name
        self.version = version
        self.description = description
        self.attribution = attribution
    }
}

public struct InstalledDictionaryPack: Sendable {
    public let manifest: DictionaryPackManifest
    public let indexManifest: LexiconResourceManifest
    public let directoryURL: URL

    public var identifier: String { manifest.identifier }
    public var englishIndexURL: URL? { indexURL(for: "en") }
    public var russianIndexURL: URL? { indexURL(for: "ru") }

    public init(
        manifest: DictionaryPackManifest,
        indexManifest: LexiconResourceManifest,
        directoryURL: URL
    ) {
        self.manifest = manifest
        self.indexManifest = indexManifest
        self.directoryURL = directoryURL
    }

    private func indexURL(for languageCode: String) -> URL? {
        guard let file = indexManifest.indexes[languageCode]?.file else { return nil }
        return directoryURL.appendingPathComponent(file)
    }
}

public enum ExistingDictionaryPackPolicy: Sendable {
    case reject
    case replace
}

public struct DictionaryPackImportLimits: Equatable, Sendable {
    public let maximumSourceBytes: Int
    public let maximumEntries: Int
    public let maximumLineBytes: Int

    public init(
        maximumSourceBytes: Int = 50 * 1_024 * 1_024,
        maximumEntries: Int = 1_000_000,
        maximumLineBytes: Int = 4_096
    ) {
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumEntries = maximumEntries
        self.maximumLineBytes = maximumLineBytes
    }
}

public enum DictionaryPackError: Error, Equatable, Sendable {
    case invalidPackage
    case symbolicLink(String)
    case missingFile(String)
    case sourceTooLarge
    case invalidManifest
    case invalidIdentifier
    case alreadyInstalled(String)
    case invalidUTF8(line: Int)
    case invalidRow(line: Int, reason: String)
    case tooManyEntries
    case cancelled
    case atomicInstallFailed
}
