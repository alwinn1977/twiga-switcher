import Foundation

public struct LexiconResourceManifest: Codable, Equatable, Sendable {
    public struct Source: Codable, Equatable, Sendable {
        public let name: String
        public let version: String
        public let sha256: String
        public let license: String

        public init(name: String, version: String, sha256: String, license: String) {
            self.name = name
            self.version = version
            self.sha256 = sha256
            self.license = license
        }
    }

    public struct Index: Codable, Equatable, Sendable {
        public let file: String
        public let sha256: String
        public let entryCount: Int
        public let maximumPhraseWords: Int

        public init(file: String, sha256: String, entryCount: Int, maximumPhraseWords: Int) {
            self.file = file
            self.sha256 = sha256
            self.entryCount = entryCount
            self.maximumPhraseWords = maximumPhraseWords
        }
    }

    public let schemaVersion: Int
    public let minimumScore: Int
    public let source: Source
    public let indexes: [String: Index]

    public init(
        schemaVersion: Int = 1,
        minimumScore: Int,
        source: Source,
        indexes: [String: Index]
    ) {
        self.schemaVersion = schemaVersion
        self.minimumScore = minimumScore
        self.source = source
        self.indexes = indexes
    }
}
