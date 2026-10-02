import Foundation
import TwigaSwitcherCore
import TwigaSwitcherLexicon

public struct LexiconServiceDiagnostic: Equatable, Sendable {
    public let message: String
    public let packIdentifier: String?
    public let isFatal: Bool

    public init(message: String, packIdentifier: String?, isFatal: Bool) {
        self.message = message
        self.packIdentifier = packIdentifier
        self.isFatal = isFatal
    }
}

public enum LexiconServiceError: Error, CustomStringConvertible, Sendable {
    case baseLexiconsUnavailable

    public var description: String {
        switch self {
        case .baseLexiconsUnavailable:
            return "Bundled frequency dictionaries are unavailable or corrupt"
        }
    }
}

public final class LexiconService: @unchecked Sendable {
    public typealias BaseLoader = @Sendable () throws -> BundledBaseLexicons
    public typealias ComputerTermsLoader = @Sendable () throws -> any FrequencyLexicon

    public static var defaultPacksRootURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("TwigaSwitcher", isDirectory: true)
            .appendingPathComponent("Dictionaries", isDirectory: true)
    }

    public let catalog: LexiconCatalog

    private let baseLoader: BaseLoader
    private let computerTermsLoader: ComputerTermsLoader?
    private let computerTermsSettings: ComputerTermsSettings?
    private let packsRootURL: URL
    private let lock = NSLock()
    private var loadGeneration: UInt64 = 0
    private var publishedDiagnostics: [LexiconServiceDiagnostic] = []
    private var publishedFatalDiagnostic: LexiconServiceDiagnostic?

    public convenience init() {
        self.init(
            baseLoader: { try BundledLexiconResources.loadBase() },
            packsRootURL: Self.defaultPacksRootURL,
            computerTermsLoader: { try BundledLexiconResources.loadComputerTerms() },
            computerTermsSettings: .shared
        )
    }

    public init(
        baseLoader: @escaping BaseLoader,
        packsRootURL: URL,
        computerTermsLoader: ComputerTermsLoader? = nil,
        computerTermsSettings: ComputerTermsSettings? = nil
    ) {
        self.baseLoader = baseLoader
        self.packsRootURL = packsRootURL
        self.computerTermsLoader = computerTermsLoader
        self.computerTermsSettings = computerTermsSettings
        self.catalog = LexiconCatalog(initialSnapshot: .init(baseLexicons: [], subjectLexicons: []))
    }

    public var diagnostics: [LexiconServiceDiagnostic] {
        lock.withLock { publishedDiagnostics }
    }

    public var fatalDiagnostic: LexiconServiceDiagnostic? {
        lock.withLock { publishedFatalDiagnostic }
    }

    public func start() throws {
        try load(generation: beginLoad())
    }

    private func beginLoad() -> UInt64 {
        lock.withLock {
            loadGeneration &+= 1
            return loadGeneration
        }
    }

    private func load(generation: UInt64) throws {
        let base: BundledBaseLexicons
        do {
            base = try baseLoader()
        } catch {
            let diagnostic = LexiconServiceDiagnostic(
                message: LexiconServiceError.baseLexiconsUnavailable.description,
                packIdentifier: nil,
                isFatal: true
            )
            publish(nil, diagnostics: [diagnostic], fatalDiagnostic: diagnostic, generation: generation)
            throw LexiconServiceError.baseLexiconsUnavailable
        }

        let store: DictionaryPackStore
        do {
            store = try DictionaryPackStore(rootURL: packsRootURL)
        } catch {
            let diagnostic = LexiconServiceDiagnostic(
                message: "Dictionary storage is unavailable",
                packIdentifier: nil,
                isFatal: true
            )
            publish(nil, diagnostics: [diagnostic], fatalDiagnostic: diagnostic, generation: generation)
            throw LexiconServiceError.baseLexiconsUnavailable
        }

        var subjectLexicons: [any FrequencyLexicon] = []
        var nonfatalDiagnostics: [LexiconServiceDiagnostic] = []
        if computerTermsSettings?.isEnabled == true, let computerTermsLoader {
            do {
                subjectLexicons.append(try computerTermsLoader())
            } catch {
                nonfatalDiagnostics.append(.init(
                    message: "Built-in Computer Terms dictionary is unavailable",
                    packIdentifier: "dev.twigaswitcher.dictionary.computer-terms",
                    isFatal: false
                ))
            }
        }
        let installedPacks = (try? store.installedPacks()) ?? []
        let installedIdentifiers = Set(installedPacks.map(\.identifier))
        for identifier in store.enabledIdentifiersSnapshot().subtracting(installedIdentifiers) {
            disablePack(identifier, in: store, generation: generation)
            nonfatalDiagnostics.append(.init(
                message: "Disabled unreadable dictionary pack: \(identifier)",
                packIdentifier: identifier,
                isFatal: false
            ))
        }
        for pack in installedPacks where store.isEnabled(pack.identifier) {
            do {
                let mapped = try open(pack)
                subjectLexicons.append(contentsOf: mapped)
            } catch {
                disablePack(pack.identifier, in: store, generation: generation)
                nonfatalDiagnostics.append(.init(
                    message: "Disabled corrupt dictionary pack: \(pack.manifest.name)",
                    packIdentifier: pack.identifier,
                    isFatal: false
                ))
            }
        }

        let snapshot = LexiconCatalogSnapshot(
            baseLexicons: [base.english, base.russian],
            subjectLexicons: subjectLexicons
        )
        publish(snapshot, diagnostics: nonfatalDiagnostics, fatalDiagnostic: nil, generation: generation)
    }

    private func publish(
        _ snapshot: LexiconCatalogSnapshot?,
        diagnostics: [LexiconServiceDiagnostic],
        fatalDiagnostic: LexiconServiceDiagnostic?,
        generation: UInt64
    ) {
        lock.withLock {
            guard generation == loadGeneration else { return }
            catalog.replaceSnapshot(snapshot ?? .init(baseLexicons: [], subjectLexicons: []))
            publishedDiagnostics = diagnostics
            publishedFatalDiagnostic = fatalDiagnostic
        }
    }

    private func disablePack(_ identifier: String, in store: DictionaryPackStore, generation: UInt64) {
        lock.withLock {
            guard generation == loadGeneration else { return }
            try? store.setEnabled(false, identifier: identifier)
        }
    }

    public func reloadPacks() async {
        let generation = beginLoad()
        _ = try? await Task.detached(priority: .utility) { [self] in
            try load(generation: generation)
        }.value
    }

    private func open(_ pack: InstalledDictionaryPack) throws -> [MappedLexicon] {
        var mapped: [MappedLexicon] = []
        if let metadata = pack.indexManifest.indexes["en"],
           let url = pack.englishIndexURL {
            let lexicon = try MappedLexicon(url: url, expectedLanguage: .english)
            guard lexicon.entryCount == metadata.entryCount,
                  lexicon.maximumPhraseWords == metadata.maximumPhraseWords else {
                throw LexiconServiceError.baseLexiconsUnavailable
            }
            mapped.append(lexicon)
        }
        if let metadata = pack.indexManifest.indexes["ru"],
           let url = pack.russianIndexURL {
            let lexicon = try MappedLexicon(url: url, expectedLanguage: .russian)
            guard lexicon.entryCount == metadata.entryCount,
                  lexicon.maximumPhraseWords == metadata.maximumPhraseWords else {
                throw LexiconServiceError.baseLexiconsUnavailable
            }
            mapped.append(lexicon)
        }
        guard !mapped.isEmpty else { throw LexiconServiceError.baseLexiconsUnavailable }
        return mapped
    }
}
