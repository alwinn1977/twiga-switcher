import Foundation
import LayoutSwitcherCore

public struct LexiconEntryFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let subjectTerm = LexiconEntryFlags(rawValue: 1 << 0)
    static let supported: LexiconEntryFlags = [.subjectTerm]
}

public struct LexiconEntry: Equatable, Sendable {
    public let language: Language
    public let key: String
    public let score: Int
    public let flags: LexiconEntryFlags

    public init(language: Language, key: String, score: Int, flags: LexiconEntryFlags) {
        self.language = language
        self.key = key
        self.score = score
        self.flags = flags
    }
}

public struct CompiledIndexMetadata: Equatable, Sendable {
    public let entryCount: Int
    public let maximumPhraseWords: Int
    public let sha256: String

    public init(entryCount: Int, maximumPhraseWords: Int, sha256: String) {
        self.entryCount = entryCount
        self.maximumPhraseWords = maximumPhraseWords
        self.sha256 = sha256
    }
}

public enum LexiconIndexError: Error, Equatable, Sendable {
    case invalidScore(Int)
    case languageMismatch
    case invalidTerm(String)
    case conflictingDuplicate(String)
    case unsupportedFlags(UInt32)
    case indexTooLarge
    case invalidFormat
    case unsupportedVersion(UInt16)
    case checksumMismatch
}

enum LexiconIndexFormat {
    static let magic = Data([0x4C, 0x53, 0x4C, 0x58]) // LSLX
    static let schemaVersion: UInt16 = 1
    static let headerSize = 72
    static let recordSize = 24
    static let checksumOffset = 40
    static let checksumSize = 32
    static let maximumTermScalars = 128
    static let maximumPhraseWords = 8

    static func languageCode(_ language: Language) -> UInt8 {
        language == .english ? 1 : 2
    }

    static func language(for code: UInt8) -> Language? {
        switch code {
        case 1: return .english
        case 2: return .russian
        default: return nil
        }
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var encoded = value.littleEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }
}
