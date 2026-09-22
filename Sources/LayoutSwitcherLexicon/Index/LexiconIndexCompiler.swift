import CryptoKit
import Foundation
import LayoutSwitcherCore

public enum LexiconIndexCompiler {
    public static func compile(
        entries: [LexiconEntry],
        language: Language,
        to outputURL: URL
    ) throws -> CompiledIndexMetadata {
        let normalizedEntries = try normalize(entries, language: language)
        let payload = try makePayload(normalizedEntries)
        let payloadDigest = Data(SHA256.hash(data: payload.data))

        var output = Data(capacity: LexiconIndexFormat.headerSize + payload.data.count)
        output.append(LexiconIndexFormat.magic)
        output.appendLittleEndian(LexiconIndexFormat.schemaVersion)
        output.append(LexiconIndexFormat.languageCode(language))
        output.append(0)
        output.appendLittleEndian(UInt32(normalizedEntries.count))
        output.appendLittleEndian(UInt16(payload.maximumPhraseWords))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt64(LexiconIndexFormat.headerSize))
        output.appendLittleEndian(UInt64(LexiconIndexFormat.headerSize + payload.recordsSize))
        output.appendLittleEndian(UInt64(payload.stringsSize))
        output.append(payloadDigest)
        precondition(output.count == LexiconIndexFormat.headerSize)
        output.append(payload.data)

        try writeAtomically(output, to: outputURL)
        let fileDigest = SHA256.hash(data: output).map { String(format: "%02x", $0) }.joined()
        return CompiledIndexMetadata(
            entryCount: normalizedEntries.count,
            maximumPhraseWords: payload.maximumPhraseWords,
            sha256: fileDigest
        )
    }

    private struct NormalizedEntry {
        let key: String
        let utf8: Data
        let score: Int32
        let flags: LexiconEntryFlags
    }

    private struct Payload {
        let data: Data
        let recordsSize: Int
        let stringsSize: Int
        let maximumPhraseWords: Int
    }

    private static func normalize(
        _ entries: [LexiconEntry],
        language: Language
    ) throws -> [NormalizedEntry] {
        var byKey: [String: NormalizedEntry] = [:]
        for entry in entries {
            guard entry.language == language else { throw LexiconIndexError.languageMismatch }
            guard (0...8_000).contains(entry.score) else {
                throw LexiconIndexError.invalidScore(entry.score)
            }
            guard entry.flags.subtracting(.supported).isEmpty else {
                throw LexiconIndexError.unsupportedFlags(entry.flags.rawValue)
            }

            let key = TermNormalizer.normalize(entry.key)
            guard isValidTerm(key) else { throw LexiconIndexError.invalidTerm(entry.key) }
            let normalized = NormalizedEntry(
                key: key,
                utf8: Data(key.utf8),
                score: Int32(entry.score),
                flags: entry.flags
            )
            if let existing = byKey[key] {
                guard existing.score == normalized.score, existing.flags == normalized.flags else {
                    throw LexiconIndexError.conflictingDuplicate(key)
                }
            } else {
                byKey[key] = normalized
            }
        }
        return byKey.values.sorted { lhs, rhs in
            lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
    }

    private static func isValidTerm(_ term: String) -> Bool {
        let scalars = term.unicodeScalars
        guard !scalars.isEmpty,
              scalars.count <= LexiconIndexFormat.maximumTermScalars,
              term.split(separator: " ").count <= LexiconIndexFormat.maximumPhraseWords,
              scalars.contains(where: CharacterSet.letters.contains) else {
            return false
        }
        let punctuation = CharacterSet(charactersIn: ".+#-_/\\@'\"")
        return scalars.allSatisfy {
            CharacterSet.letters.contains($0)
                || CharacterSet.decimalDigits.contains($0)
                || $0 == " "
                || punctuation.contains($0)
        }
    }

    private static func makePayload(_ entries: [NormalizedEntry]) throws -> Payload {
        let recordsSize = try checkedMultiply(entries.count, LexiconIndexFormat.recordSize)
        var records = Data(capacity: recordsSize)
        var strings = Data()
        var maximumPhraseWords = 0

        for entry in entries {
            guard let stringOffset = UInt64(exactly: strings.count),
                  let stringLength = UInt32(exactly: entry.utf8.count) else {
                throw LexiconIndexError.indexTooLarge
            }
            records.appendLittleEndian(stringOffset)
            records.appendLittleEndian(stringLength)
            records.appendLittleEndian(entry.score)
            records.appendLittleEndian(entry.flags.rawValue)
            records.appendLittleEndian(UInt32(0))
            strings.append(entry.utf8)
            maximumPhraseWords = max(maximumPhraseWords, entry.key.split(separator: " ").count)
        }

        var data = Data(capacity: try checkedAdd(records.count, strings.count))
        data.append(records)
        data.append(strings)
        return Payload(
            data: data,
            recordsSize: records.count,
            stringsSize: strings.count,
            maximumPhraseWords: maximumPhraseWords
        )
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw LexiconIndexError.indexTooLarge }
        return value
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw LexiconIndexError.indexTooLarge }
        return value
    }

    private static func writeAtomically(_ data: Data, to outputURL: URL) throws {
        let fileManager = FileManager.default
        let directory = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL)
            let handle = try FileHandle(forWritingTo: temporaryURL)
            try handle.synchronize()
            try handle.close()
            if fileManager.fileExists(atPath: outputURL.path) {
                _ = try fileManager.replaceItemAt(outputURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: outputURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
