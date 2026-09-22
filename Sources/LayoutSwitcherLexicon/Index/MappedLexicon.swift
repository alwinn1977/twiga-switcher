import CryptoKit
import Foundation
import LayoutSwitcherCore

public final class MappedLexicon: @unchecked Sendable, FrequencyLexicon {
    public let entryCount: Int
    public let maximumPhraseWords: Int

    private let file: MappedFile
    private let language: Language
    private let recordTableOffset: Int
    private let stringTableOffset: Int
    private let stringTableLength: Int

    public init(url: URL, expectedLanguage: Language) throws {
        let file = try MappedFile(url: url)
        let bytes = file.bytes
        guard bytes.count >= LexiconIndexFormat.headerSize,
              Data(bytes: bytes.baseAddress!, count: 4) == LexiconIndexFormat.magic else {
            throw LexiconIndexError.invalidFormat
        }

        let version: UInt16 = try Self.readInteger(bytes, at: 4)
        guard version == LexiconIndexFormat.schemaVersion else {
            throw LexiconIndexError.unsupportedVersion(version)
        }
        guard let encodedLanguage = LexiconIndexFormat.language(for: bytes[6]),
              encodedLanguage == expectedLanguage,
              bytes[7] == 0 else {
            throw LexiconIndexError.languageMismatch
        }

        let count: UInt32 = try Self.readInteger(bytes, at: 8)
        let maximumWords: UInt16 = try Self.readInteger(bytes, at: 12)
        let headerReserved: UInt16 = try Self.readInteger(bytes, at: 14)
        let recordsOffsetValue: UInt64 = try Self.readInteger(bytes, at: 16)
        let stringsOffsetValue: UInt64 = try Self.readInteger(bytes, at: 24)
        let stringsLengthValue: UInt64 = try Self.readInteger(bytes, at: 32)
        guard headerReserved == 0,
              let entryCount = Int(exactly: count),
              let recordsOffset = Int(exactly: recordsOffsetValue),
              let stringsOffset = Int(exactly: stringsOffsetValue),
              let stringsLength = Int(exactly: stringsLengthValue),
              recordsOffset == LexiconIndexFormat.headerSize else {
            throw LexiconIndexError.invalidFormat
        }

        let recordsSize = try Self.checkedMultiply(entryCount, LexiconIndexFormat.recordSize)
        let expectedStringsOffset = try Self.checkedAdd(recordsOffset, recordsSize)
        let expectedFileSize = try Self.checkedAdd(stringsOffset, stringsLength)
        guard stringsOffset == expectedStringsOffset,
              expectedFileSize == bytes.count else {
            throw LexiconIndexError.invalidFormat
        }

        let expectedChecksum = Data(
            bytes: bytes.baseAddress!.advanced(by: LexiconIndexFormat.checksumOffset),
            count: LexiconIndexFormat.checksumSize
        )
        let payload = Data(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes.baseAddress!.advanced(by: recordsOffset)),
            count: bytes.count - recordsOffset,
            deallocator: .none
        )
        guard Data(SHA256.hash(data: payload)) == expectedChecksum else {
            throw LexiconIndexError.checksumMismatch
        }

        var previousKey: Data?
        var computedMaximumWords = 0
        for index in 0..<entryCount {
            let record = try Self.readRecord(
                bytes,
                index: index,
                recordTableOffset: recordsOffset,
                stringTableOffset: stringsOffset,
                stringTableLength: stringsLength
            )
            guard let key = String(data: record.key, encoding: .utf8),
                  TermNormalizer.normalize(key) == key,
                  (0...8_000).contains(record.score),
                  record.flags.subtracting(.supported).isEmpty,
                  record.reserved == 0 else {
                throw LexiconIndexError.invalidFormat
            }
            if let previousKey {
                guard previousKey.lexicographicallyPrecedes(record.key) else {
                    throw LexiconIndexError.invalidFormat
                }
            }
            previousKey = record.key
            computedMaximumWords = max(computedMaximumWords, key.split(separator: " ").count)
        }
        guard computedMaximumWords == Int(maximumWords),
              computedMaximumWords <= LexiconIndexFormat.maximumPhraseWords else {
            throw LexiconIndexError.invalidFormat
        }

        self.file = file
        self.language = encodedLanguage
        self.entryCount = entryCount
        self.maximumPhraseWords = Int(maximumWords)
        self.recordTableOffset = recordsOffset
        self.stringTableOffset = stringsOffset
        self.stringTableLength = stringsLength
    }

    public func lookup(_ text: String, language: Language) -> LexiconMatch {
        guard language == self.language else { return .missing }
        let query = Data(TermNormalizer.normalize(text).utf8)
        guard !query.isEmpty else { return .missing }

        let insertionIndex = lowerBound(for: query)
        var score: Int?
        var isSubjectTerm = false
        if insertionIndex < entryCount,
           let record = try? record(at: insertionIndex),
           record.key == query {
            score = record.score
            isSubjectTerm = record.flags.contains(.subjectTerm)
        }

        var isStrictPrefix = false
        let prefixIndex = insertionIndex + (score == nil ? 0 : 1)
        if prefixIndex < entryCount,
           let next = try? record(at: prefixIndex) {
            isStrictPrefix = Self.isPhraseContinuation(next.key, after: query)
        }

        return LexiconMatch(
            score: score,
            isSubjectTerm: isSubjectTerm,
            isStrictPrefix: isStrictPrefix
        )
    }

    private struct Record {
        let key: Data
        let score: Int
        let flags: LexiconEntryFlags
        let reserved: UInt32
    }

    private func lowerBound(for query: Data) -> Int {
        var lower = 0
        var upper = entryCount
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            guard let key = try? record(at: middle).key else { return entryCount }
            if key.lexicographicallyPrecedes(query) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func isPhraseContinuation(_ key: Data, after query: Data) -> Bool {
        guard key.count > query.count, key.starts(with: query) else { return false }
        let separator = key[key.index(key.startIndex, offsetBy: query.count)]
        return separator == 0x20 || separator == 0x2E
    }

    private func record(at index: Int) throws -> Record {
        try Self.readRecord(
            file.bytes,
            index: index,
            recordTableOffset: recordTableOffset,
            stringTableOffset: stringTableOffset,
            stringTableLength: stringTableLength
        )
    }

    private static func readRecord(
        _ bytes: UnsafeRawBufferPointer,
        index: Int,
        recordTableOffset: Int,
        stringTableOffset: Int,
        stringTableLength: Int
    ) throws -> Record {
        let scaledIndex = try checkedMultiply(index, LexiconIndexFormat.recordSize)
        let offset = try checkedAdd(recordTableOffset, scaledIndex)
        let stringOffsetValue: UInt64 = try readInteger(bytes, at: offset)
        let stringLengthValue: UInt32 = try readInteger(bytes, at: offset + 8)
        let score: Int32 = try readInteger(bytes, at: offset + 12)
        let flags: UInt32 = try readInteger(bytes, at: offset + 16)
        let reserved: UInt32 = try readInteger(bytes, at: offset + 20)
        guard let stringOffset = Int(exactly: stringOffsetValue),
              let stringLength = Int(exactly: stringLengthValue),
              stringOffset <= stringTableLength,
              stringLength <= stringTableLength - stringOffset else {
            throw LexiconIndexError.invalidFormat
        }
        let start = try checkedAdd(stringTableOffset, stringOffset)
        let end = try checkedAdd(start, stringLength)
        guard start >= 0, end <= bytes.count else { throw LexiconIndexError.invalidFormat }
        return Record(
            key: Data(bytes: bytes.baseAddress!.advanced(by: start), count: stringLength),
            score: Int(score),
            flags: LexiconEntryFlags(rawValue: flags),
            reserved: reserved
        )
    }

    private static func readInteger<T: FixedWidthInteger>(
        _ bytes: UnsafeRawBufferPointer,
        at offset: Int
    ) throws -> T {
        guard offset >= 0, offset <= bytes.count - MemoryLayout<T>.size else {
            throw LexiconIndexError.invalidFormat
        }
        return T(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: T.self))
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw LexiconIndexError.invalidFormat }
        return value
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw LexiconIndexError.invalidFormat }
        return value
    }
}
