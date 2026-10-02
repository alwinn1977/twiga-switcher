import CryptoKit
import Foundation
import TwigaSwitcherCore

public struct BundledBaseLexicons: Sendable {
    public let manifest: LexiconResourceManifest
    public let english: MappedLexicon
    public let russian: MappedLexicon

    public init(manifest: LexiconResourceManifest, english: MappedLexicon, russian: MappedLexicon) {
        self.manifest = manifest
        self.english = english
        self.russian = russian
    }
}

public struct BundledComputerTermsLexicons: Sendable, FrequencyLexicon {
    public let manifest: LexiconResourceManifest
    public let english: MappedLexicon
    public let russian: MappedLexicon

    public func lookup(_ text: String, language: Language) -> LexiconMatch {
        switch language {
        case .english: english.lookup(text, language: language)
        case .russian: russian.lookup(text, language: language)
        }
    }
}

public enum BundledLexiconResourceError: Error, Equatable, Sendable {
    case missingResource(String)
    case invalidManifest
    case checksumMismatch(String)
    case metadataMismatch(String)
    case unreadableResource(String)
}

public enum BundledLexiconResources {
    private static let expectedWheelSHA256 = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"

    public static func loadBase() throws -> BundledBaseLexicons {
        try loadBase(bundle: .module)
    }

    public static func loadComputerTerms() throws -> BundledComputerTermsLexicons {
        try loadComputerTerms(bundle: .module)
    }

    public static func computerTermsNoticeURL() -> URL? {
        Bundle.module.url(
            forResource: "computer-terms-NOTICE",
            withExtension: "txt",
            subdirectory: "Licenses"
        )
    }

    static func loadBase(bundle: Bundle) throws -> BundledBaseLexicons {
        guard let manifestURL = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "Lexicons/Base"
        ) else {
            throw BundledLexiconResourceError.missingResource("manifest.json")
        }
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        } catch {
            throw BundledLexiconResourceError.unreadableResource("manifest.json")
        }
        guard let manifest = try? JSONDecoder().decode(LexiconResourceManifest.self, from: manifestData),
              manifest.schemaVersion == 1,
              manifest.minimumScore == 2_500,
              manifest.source.name == "wordfreq",
              manifest.source.version == "3.1.1",
              manifest.source.sha256 == expectedWheelSHA256,
              manifest.source.license == "CC-BY-SA-4.0" else {
            throw BundledLexiconResourceError.invalidManifest
        }

        let english = try loadIndex(
            languageCode: "en",
            language: .english,
            manifest: manifest,
            bundle: bundle,
            subdirectory: "Lexicons/Base"
        )
        let russian = try loadIndex(
            languageCode: "ru",
            language: .russian,
            manifest: manifest,
            bundle: bundle,
            subdirectory: "Lexicons/Base"
        )
        return BundledBaseLexicons(manifest: manifest, english: english, russian: russian)
    }

    static func loadComputerTerms(bundle: Bundle) throws -> BundledComputerTermsLexicons {
        let directory = "Lexicons/ComputerTerms"
        guard let manifestURL = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: directory
        ) else {
            throw BundledLexiconResourceError.missingResource("ComputerTerms/manifest.json")
        }
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        } catch {
            throw BundledLexiconResourceError.unreadableResource("ComputerTerms/manifest.json")
        }
        guard let manifest = try? JSONDecoder().decode(LexiconResourceManifest.self, from: manifestData),
              manifest.schemaVersion == 1,
              manifest.minimumScore == 0,
              manifest.source.name == "dev.twigaswitcher.dictionary.computer-terms",
              manifest.source.version == "1.0.0",
              manifest.source.sha256 == "project-authored",
              manifest.source.license == "CC0-1.0" else {
            throw BundledLexiconResourceError.invalidManifest
        }
        return try BundledComputerTermsLexicons(
            manifest: manifest,
            english: loadIndex(
                languageCode: "en",
                language: .english,
                manifest: manifest,
                bundle: bundle,
                subdirectory: directory
            ),
            russian: loadIndex(
                languageCode: "ru",
                language: .russian,
                manifest: manifest,
                bundle: bundle,
                subdirectory: directory
            )
        )
    }

    private static func loadIndex(
        languageCode: String,
        language: Language,
        manifest: LexiconResourceManifest,
        bundle: Bundle,
        subdirectory: String
    ) throws -> MappedLexicon {
        guard let metadata = manifest.indexes[languageCode],
              metadata.file == "\(languageCode).lsidx",
              metadata.entryCount > 0,
              metadata.maximumPhraseWords > 0 else {
            throw BundledLexiconResourceError.metadataMismatch(languageCode)
        }
        guard let url = bundle.url(
            forResource: languageCode,
            withExtension: "lsidx",
            subdirectory: subdirectory
        ) else {
            throw BundledLexiconResourceError.missingResource(metadata.file)
        }
        guard try sha256(of: url) == metadata.sha256 else {
            throw BundledLexiconResourceError.checksumMismatch(metadata.file)
        }
        let lexicon = try MappedLexicon(url: url, expectedLanguage: language)
        guard lexicon.entryCount == metadata.entryCount,
              lexicon.maximumPhraseWords == metadata.maximumPhraseWords else {
            throw BundledLexiconResourceError.metadataMismatch(metadata.file)
        }
        return lexicon
    }

    private static func sha256(of url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw BundledLexiconResourceError.unreadableResource(url.lastPathComponent)
        }
        defer { try? handle.close() }

        var digest = SHA256()
        do {
            while let data = try handle.read(upToCount: 64 * 1_024), !data.isEmpty {
                digest.update(data: data)
            }
        } catch {
            throw BundledLexiconResourceError.unreadableResource(url.lastPathComponent)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
