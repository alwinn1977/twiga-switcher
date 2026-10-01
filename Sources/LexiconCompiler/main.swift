import CryptoKit
import Darwin
import Foundation
import TwigaSwitcherCore
import TwigaSwitcherLexicon

@main
enum LexiconCompilerMain {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("LexiconCompiler: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else { throw CLIError.usage }
        let options = try Options(Array(arguments.dropFirst()))
        switch command {
        case "compile-tsv":
            try compile(options)
        case "verify":
            try verify(options)
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func compile(_ options: Options) throws {
        let input = URL(fileURLWithPath: try options.single("--input"))
        let outputDirectory = URL(fileURLWithPath: try options.single("--output-directory"), isDirectory: true)
        let manifestURL = URL(fileURLWithPath: try options.single("--manifest"))
        let source = LexiconResourceManifest.Source(
            name: try options.single("--source-name"),
            version: try options.single("--source-version"),
            sha256: try options.single("--source-sha256"),
            license: try options.single("--license")
        )
        let subjectTerms = options.flag("--subject-terms")
        let minimumScore = try options.optionalInt("--minimum-score") ?? 0
        guard (0...8_000).contains(minimumScore) else { throw CLIError.invalidMinimumScore }
        let entries = try readEntries(from: input, subjectTerms: subjectTerms)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var indexes: [String: LexiconResourceManifest.Index] = [:]
        for (language, code) in [(Language.english, "en"), (.russian, "ru")] {
            let languageEntries = entries.filter { $0.language == language }
            guard !languageEntries.isEmpty else { continue }
            let file = "\(code).lsidx"
            let metadata = try LexiconIndexCompiler.compile(
                entries: languageEntries,
                language: language,
                to: outputDirectory.appendingPathComponent(file)
            )
            indexes[code] = .init(
                file: file,
                sha256: metadata.sha256,
                entryCount: metadata.entryCount,
                maximumPhraseWords: metadata.maximumPhraseWords
            )
        }
        guard !indexes.isEmpty else { throw CLIError.emptyInput }

        let manifest = LexiconResourceManifest(
            minimumScore: minimumScore,
            source: source,
            indexes: indexes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(manifest)
        data.append(0x0A)
        try writeAtomically(data, to: manifestURL)
    }

    private static func verify(_ options: Options) throws {
        let directory = URL(fileURLWithPath: try options.single("--directory"), isDirectory: true)
        let manifestURL = URL(fileURLWithPath: try options.single("--manifest"))
        let manifest = try JSONDecoder().decode(
            LexiconResourceManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.schemaVersion == 1 else { throw CLIError.invalidManifest }
        if let expectedMinimum = try options.optionalInt("--expect-minimum-score"),
           manifest.minimumScore != expectedMinimum {
            throw CLIError.failedExpectation("minimumScore=\(expectedMinimum)")
        }

        var mapped: [String: MappedLexicon] = [:]
        for (code, index) in manifest.indexes {
            guard let language = parseLanguage(code) else { throw CLIError.invalidLanguage(code) }
            let url = directory.appendingPathComponent(index.file)
            guard sha256(url) == index.sha256 else { throw CLIError.checksumMismatch(index.file) }
            let lexicon = try MappedLexicon(url: url, expectedLanguage: language)
            guard lexicon.entryCount == index.entryCount,
                  lexicon.maximumPhraseWords == index.maximumPhraseWords else {
                throw CLIError.invalidManifest
            }
            mapped[code] = lexicon
        }

        for expected in options.values("--expect-count") {
            let parts = expected.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let count = Int(parts[1]), mapped[parts[0]]?.entryCount == count else {
                throw CLIError.failedExpectation(expected)
            }
        }
        for expected in options.values("--lookup") {
            guard let colon = expected.firstIndex(of: ":"),
                  let equals = expected.lastIndex(of: "="),
                  colon < equals,
                  let score = Int(expected[expected.index(after: equals)...]) else {
                throw CLIError.failedExpectation(expected)
            }
            let code = String(expected[..<colon])
            let term = String(expected[expected.index(after: colon)..<equals])
            guard let language = parseLanguage(code) else {
                throw CLIError.failedExpectation(expected)
            }
            let actual = mapped[code]?.lookup(term, language: language).score
            guard actual == score else {
                throw CLIError.failedExpectation("\(expected), actual=\(actual.map(String.init) ?? "missing")")
            }
        }
    }

    private static func readEntries(from url: URL, subjectTerms: Bool) throws -> [LexiconEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var buffer = Data()
        var entries: [LexiconEntry] = []
        var lineNumber = 0

        func consume(_ lineData: Data) throws {
            lineNumber += 1
            guard lineData.count <= 4_096 else { throw CLIError.line(url.path, lineNumber, "line exceeds 4096 bytes") }
            var clean = lineData
            if clean.last == 0x0D { clean.removeLast() }
            guard let line = String(data: clean, encoding: .utf8) else {
                throw CLIError.line(url.path, lineNumber, "invalid UTF-8")
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3,
                  let language = parseLanguage(String(columns[0])),
                  let score = Int(columns[1]) else {
                throw CLIError.line(url.path, lineNumber, "expected language<TAB>score<TAB>term")
            }
            entries.append(LexiconEntry(
                language: language,
                key: String(columns[2]),
                score: score,
                flags: subjectTerms ? [.subjectTerm] : []
            ))
        }

        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                try consume(buffer[..<newline])
                buffer.removeSubrange(...newline)
            }
            guard buffer.count <= 4_096 else {
                throw CLIError.line(url.path, lineNumber + 1, "line exceeds 4096 bytes")
            }
        }
        if !buffer.isEmpty { try consume(buffer) }
        return entries
    }

    private static func parseLanguage(_ code: String) -> Language? {
        switch code {
        case "en": return .english
        case "ru": return .russian
        default: return nil
        }
    }

    private static func sha256(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

private struct Options {
    private var storage: [String: [String]] = [:]

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--") else { throw CLIError.usage }
            if key == "--subject-terms" {
                storage[key, default: []].append("true")
                index += 1
            } else {
                guard index + 1 < arguments.count else { throw CLIError.missingOption(key) }
                storage[key, default: []].append(arguments[index + 1])
                index += 2
            }
        }
    }

    func single(_ key: String) throws -> String {
        guard let values = storage[key], values.count == 1, let value = values.first else {
            throw CLIError.missingOption(key)
        }
        return value
    }

    func values(_ key: String) -> [String] { storage[key] ?? [] }
    func flag(_ key: String) -> Bool { storage[key] != nil }

    func optionalInt(_ key: String) throws -> Int? {
        guard let values = storage[key] else { return nil }
        guard values.count == 1, let value = values.first, let integer = Int(value) else {
            throw CLIError.missingOption(key)
        }
        return integer
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case usage
    case unknownCommand(String)
    case missingOption(String)
    case emptyInput
    case invalidManifest
    case invalidLanguage(String)
    case checksumMismatch(String)
    case failedExpectation(String)
    case line(String, Int, String)
    case invalidMinimumScore

    var description: String {
        switch self {
        case .usage: return "usage: LexiconCompiler <compile-tsv|verify> [options]"
        case let .unknownCommand(command): return "unknown command: \(command)"
        case let .missingOption(option): return "missing or repeated option: \(option)"
        case .emptyInput: return "input contains no dictionary entries"
        case .invalidManifest: return "manifest does not match compiled indexes"
        case let .invalidLanguage(language): return "invalid language: \(language)"
        case let .checksumMismatch(file): return "checksum mismatch: \(file)"
        case let .failedExpectation(value): return "verification failed: \(value)"
        case let .line(path, line, message): return "\(path):\(line): \(message)"
        case .invalidMinimumScore: return "minimum score must be between 0 and 8000"
        }
    }
}
