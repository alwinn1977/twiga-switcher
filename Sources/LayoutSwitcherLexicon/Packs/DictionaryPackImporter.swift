import CryptoKit
import Darwin
import Foundation
import LayoutSwitcherCore

public struct DictionaryPackImporter: Sendable {
    public let limits: DictionaryPackImportLimits

    public init(limits: DictionaryPackImportLimits = .init()) {
        self.limits = limits
    }

    public func importPackage(
        at packageURL: URL,
        into installRoot: URL,
        existingPolicy: ExistingDictionaryPackPolicy
    ) async throws -> InstalledDictionaryPack {
        let task = Task.detached(priority: .utility) {
                try Self.importSynchronously(
                    packageURL: packageURL,
                    installRoot: installRoot,
                    existingPolicy: existingPolicy,
                    limits: limits
                )
        }
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch is CancellationError {
            throw DictionaryPackError.cancelled
        }
    }

    private static func importSynchronously(
        packageURL: URL,
        installRoot: URL,
        existingPolicy: ExistingDictionaryPackPolicy,
        limits: DictionaryPackImportLimits
    ) throws -> InstalledDictionaryPack {
        try Task.checkCancellation()
        guard packageURL.pathExtension == "layoutdict",
              try isDirectory(packageURL),
              try !isSymbolicLink(packageURL) else {
            throw DictionaryPackError.invalidPackage
        }

        let manifestURL = packageURL.appendingPathComponent("manifest.json", isDirectory: false)
        let entriesURL = packageURL.appendingPathComponent("entries.tsv", isDirectory: false)
        try validateRegularFile(manifestURL, named: "manifest.json")
        try validateRegularFile(entriesURL, named: "entries.tsv")
        let noticeURL = packageURL.appendingPathComponent("NOTICE.txt", isDirectory: false)
        if FileManager.default.fileExists(atPath: noticeURL.path) {
            try validateRegularFile(noticeURL, named: "NOTICE.txt")
        }

        let sourceBytes = try [manifestURL, entriesURL, noticeURL]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .reduce(into: 0) { total, url in
                let size = try fileSize(url)
                let (sum, overflow) = total.addingReportingOverflow(size)
                guard !overflow else { throw DictionaryPackError.sourceTooLarge }
                total = sum
            }
        guard sourceBytes <= limits.maximumSourceBytes else {
            throw DictionaryPackError.sourceTooLarge
        }

        let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        guard let manifest = try? JSONDecoder().decode(DictionaryPackManifest.self, from: manifestData),
              isValid(manifest: manifest) else {
            throw DictionaryPackError.invalidManifest
        }
        guard isValidIdentifier(manifest.identifier) else {
            throw DictionaryPackError.invalidIdentifier
        }

        try FileManager.default.createDirectory(at: installRoot, withIntermediateDirectories: true)
        let canonicalRoot = installRoot.standardizedFileURL
        let destination = canonicalRoot.appendingPathComponent(manifest.identifier, isDirectory: true).standardizedFileURL
        guard destination.deletingLastPathComponent() == canonicalRoot else {
            throw DictionaryPackError.invalidIdentifier
        }
        let destinationExists = FileManager.default.fileExists(atPath: destination.path)
        if destinationExists, existingPolicy == .reject {
            throw DictionaryPackError.alreadyInstalled(manifest.identifier)
        }

        let entries = try readEntries(from: entriesURL, limits: limits)
        let temporary = canonicalRoot.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        var published = false
        defer {
            if !published || FileManager.default.fileExists(atPath: temporary.path) {
                try? FileManager.default.removeItem(at: temporary)
            }
        }

        let english = entries.filter { $0.language == .english }
        let russian = entries.filter { $0.language == .russian }
        var indexes: [String: LexiconResourceManifest.Index] = [:]
        if !english.isEmpty {
            indexes["en"] = try compile(english, language: .english, code: "en", directory: temporary)
        }
        if !russian.isEmpty {
            indexes["ru"] = try compile(russian, language: .russian, code: "ru", directory: temporary)
        }
        guard !indexes.isEmpty else { throw DictionaryPackError.invalidPackage }

        let sourceSHA = SHA256.hash(data: try Data(contentsOf: entriesURL, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        let indexManifest = LexiconResourceManifest(
            minimumScore: 0,
            source: .init(
                name: manifest.identifier,
                version: manifest.version,
                sha256: sourceSHA,
                license: manifest.attribution.license
            ),
            indexes: indexes
        )
        try writeJSON(manifest, to: temporary.appendingPathComponent("pack.json"))
        try writeJSON(indexManifest, to: temporary.appendingPathComponent("indexes.json"))
        if FileManager.default.fileExists(atPath: noticeURL.path) {
            try FileManager.default.copyItem(at: noticeURL, to: temporary.appendingPathComponent("NOTICE.txt"))
        }

        try Task.checkCancellation()
        if destinationExists {
            guard existingPolicy == .replace else {
                throw DictionaryPackError.alreadyInstalled(manifest.identifier)
            }
            let result = temporary.path.withCString { temporaryPath in
                destination.path.withCString { destinationPath in
                    renamex_np(temporaryPath, destinationPath, UInt32(RENAME_SWAP))
                }
            }
            guard result == 0 else { throw DictionaryPackError.atomicInstallFailed }
        } else {
            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch {
                throw DictionaryPackError.atomicInstallFailed
            }
        }
        published = true
        return InstalledDictionaryPack(
            manifest: manifest,
            indexManifest: indexManifest,
            directoryURL: destination
        )
    }

    private static func compile(
        _ entries: [LexiconEntry],
        language: Language,
        code: String,
        directory: URL
    ) throws -> LexiconResourceManifest.Index {
        let file = "\(code).lsidx"
        let url = directory.appendingPathComponent(file)
        let metadata = try LexiconIndexCompiler.compile(entries: entries, language: language, to: url)
        let mapped = try MappedLexicon(url: url, expectedLanguage: language)
        guard mapped.entryCount == metadata.entryCount,
              mapped.maximumPhraseWords == metadata.maximumPhraseWords else {
            throw DictionaryPackError.invalidPackage
        }
        return .init(
            file: file,
            sha256: metadata.sha256,
            entryCount: metadata.entryCount,
            maximumPhraseWords: metadata.maximumPhraseWords
        )
    }

    private static func readEntries(
        from url: URL,
        limits: DictionaryPackImportLimits
    ) throws -> [LexiconEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var buffer = Data()
        var entries: [LexiconEntry] = []
        var lineNumber = 0

        func consume(_ rawLine: Data) throws {
            lineNumber += 1
            guard rawLine.count <= limits.maximumLineBytes else {
                throw DictionaryPackError.invalidRow(line: lineNumber, reason: "line exceeds byte limit")
            }
            var lineData = rawLine
            if lineData.last == 0x0D { lineData.removeLast() }
            guard let line = String(data: lineData, encoding: .utf8) else {
                throw DictionaryPackError.invalidUTF8(line: lineNumber)
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else {
                throw DictionaryPackError.invalidRow(line: lineNumber, reason: "expected language, score, and term")
            }
            let language: Language
            switch columns[0] {
            case "en": language = .english
            case "ru": language = .russian
            default: throw DictionaryPackError.invalidRow(line: lineNumber, reason: "unsupported language")
            }
            guard let score = Int(columns[1]), (0...8_000).contains(score) else {
                throw DictionaryPackError.invalidRow(line: lineNumber, reason: "score must be 0...8000")
            }
            let term = TermNormalizer.normalize(String(columns[2]))
            guard validTerm(term) else {
                throw DictionaryPackError.invalidRow(line: lineNumber, reason: "unsupported term")
            }
            entries.append(LexiconEntry(language: language, key: term, score: score, flags: [.subjectTerm]))
            guard entries.count <= limits.maximumEntries else { throw DictionaryPackError.tooManyEntries }
        }

        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                try consume(Data(buffer[..<newline]))
                buffer.removeSubrange(...newline)
            }
            guard buffer.count <= limits.maximumLineBytes else {
                throw DictionaryPackError.invalidRow(line: lineNumber + 1, reason: "line exceeds byte limit")
            }
        }
        if !buffer.isEmpty { try consume(buffer) }
        return entries
    }

    private static func validTerm(_ term: String) -> Bool {
        let scalars = term.unicodeScalars
        let punctuation = CharacterSet(charactersIn: ".+#-_/\\@'\"")
        return !scalars.isEmpty
            && scalars.count <= 128
            && term.split(separator: " ").count <= 8
            && scalars.contains(where: CharacterSet.letters.contains)
            && scalars.allSatisfy {
                CharacterSet.letters.contains($0)
                    || CharacterSet.decimalDigits.contains($0)
                    || $0 == " "
                    || punctuation.contains($0)
            }
    }

    private static func isValid(manifest: DictionaryPackManifest) -> Bool {
        manifest.schemaVersion == 1
            && !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !manifest.attribution.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !manifest.attribution.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isValidIdentifier(_ identifier: String) -> Bool {
        let pattern = #"^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$"#
        return identifier.range(of: pattern, options: .regularExpression) != nil
    }

    private static func validateRegularFile(_ url: URL, named name: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DictionaryPackError.missingFile(name)
        }
        if try isSymbolicLink(url) { throw DictionaryPackError.symbolicLink(name) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw DictionaryPackError.invalidPackage
        }
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private static func isSymbolicLink(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values.isSymbolicLink == true
    }

    private static func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else { throw DictionaryPackError.invalidPackage }
        return size
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
