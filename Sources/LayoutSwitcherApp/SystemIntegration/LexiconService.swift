import Foundation
import LayoutSwitcherCore
import LayoutSwitcherLexicon

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
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("Dictionaries", isDirectory: true)
    }

    public let catalog: LexiconCatalog

    private let baseLoader: BaseLoader
    private let computerTermsLoader: ComputerTermsLoader?
    private let computerTermsSettings: ComputerTermsSettings?
    private let packsRootURL: URL
    private let lock = NSLock()
    private var publishedSnapshot: LexiconCatalogSnapshot?
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

    public var currentSnapshot: LexiconCatalogSnapshot? {
        lock.withLock { publishedSnapshot }
    }

    public var diagnostics: [LexiconServiceDiagnostic] {
        lock.withLock { publishedDiagnostics }
    }

    public var fatalDiagnostic: LexiconServiceDiagnostic? {
        lock.withLock { publishedFatalDiagnostic }
    }

    public func start() throws {
        let base: BundledBaseLexicons
        do {
            base = try baseLoader()
        } catch {
            let diagnostic = LexiconServiceDiagnostic(
                message: LexiconServiceError.baseLexiconsUnavailable.description,
                packIdentifier: nil,
                isFatal: true
            )
            let empty = LexiconCatalogSnapshot(baseLexicons: [], subjectLexicons: [])
            catalog.replaceSnapshot(empty)
            lock.withLock {
                publishedSnapshot = nil
                publishedDiagnostics = [diagnostic]
                publishedFatalDiagnostic = diagnostic
            }
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
            let empty = LexiconCatalogSnapshot(baseLexicons: [], subjectLexicons: [])
            catalog.replaceSnapshot(empty)
            lock.withLock {
                publishedSnapshot = nil
                publishedDiagnostics = [diagnostic]
                publishedFatalDiagnostic = diagnostic
            }
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
                    packIdentifier: "dev.layoutswitcher.dictionary.computer-terms",
                    isFatal: false
                ))
            }
        }
        let installedPacks = (try? store.installedPacks()) ?? []
        let installedIdentifiers = Set(installedPacks.map(\.identifier))
        for identifier in store.enabledIdentifiersSnapshot().subtracting(installedIdentifiers) {
            try? store.setEnabled(false, identifier: identifier)
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
                try? store.setEnabled(false, identifier: pack.identifier)
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
        catalog.replaceSnapshot(snapshot)
        lock.withLock {
            publishedSnapshot = snapshot
            publishedDiagnostics = nonfatalDiagnostics
            publishedFatalDiagnostic = nil
        }
    }

    public func reloadPacks() async {
        _ = try? await Task.detached(priority: .utility) { [self] in
            try start()
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
