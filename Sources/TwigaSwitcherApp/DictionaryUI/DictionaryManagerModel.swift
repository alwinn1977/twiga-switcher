import Combine
import Foundation
import TwigaSwitcherLexicon

public struct DictionaryManagerRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let detail: String
    public let isBase: Bool
    public let isBuiltIn: Bool
    public var isEnabled: Bool
    public let canRemove: Bool
    public let noticeURL: URL?
    public let importedEntryCount: Int?
    public let importedLanguages: String?
    public let importedLicense: String?

    public func displayName(in language: DisplayLanguage) -> String {
        guard isBuiltIn else { return name }
        switch id {
        case "dev.twigaswitcher.base.english": return InterfaceText.englishFrequencyDictionary.localized(language)
        case "dev.twigaswitcher.base.russian": return InterfaceText.russianFrequencyDictionary.localized(language)
        case "dev.twigaswitcher.dictionary.computer-terms": return InterfaceText.computerTerms.localized(language)
        default: return name
        }
    }

    public func displayDetail(in language: DisplayLanguage) -> String {
        if isBase { return InterfaceText.baseDictionaryDetail.localized(language) }
        if isBuiltIn { return InterfaceText.builtInSubjectDictionary.localized(language) }
        if let importedLanguages, let importedEntryCount, let importedLicense {
            return InterfaceText.importedDictionaryDetail.localized(
                language, importedLanguages, importedEntryCount, importedLicense
            )
        }
        return detail
    }
}

@MainActor
public final class DictionaryManagerModel: ObservableObject {
    public typealias Confirmation = @MainActor (DictionaryManagerRow) -> Bool
    public typealias CatalogReload = @MainActor () async -> Void

    @Published public private(set) var rows: [DictionaryManagerRow] = []
    @Published public private(set) var isWorking = false
    @Published private(set) var status: InterfaceStatus?
    public func statusMessage(in language: DisplayLanguage) -> String? { status?.localized(language) }

    private let store: DictionaryPackStore
    private let importer: DictionaryPackImporter
    private let computerTermsSettings: ComputerTermsSettings
    private let confirmRemoval: Confirmation
    private let reloadCatalog: CatalogReload

    public init(
        store: DictionaryPackStore? = nil,
        importer: DictionaryPackImporter = .init(),
        computerTermsSettings: ComputerTermsSettings = .shared,
        confirmRemoval: @escaping Confirmation = { _ in true },
        reloadCatalog: @escaping CatalogReload = {}
    ) {
        if let store {
            self.store = store
        } else if let created = try? DictionaryPackStore(rootURL: LexiconService.defaultPacksRootURL) {
            self.store = created
        } else {
            preconditionFailure("Unable to open dictionary store")
        }
        self.importer = importer
        self.computerTermsSettings = computerTermsSettings
        self.confirmRemoval = confirmRemoval
        self.reloadCatalog = reloadCatalog
        refresh()
    }

    public func refresh() {
        var result = [
            DictionaryManagerRow(
                id: "dev.twigaswitcher.base.english",
                name: "English Frequency Dictionary",
                version: "wordfreq 3.1.1",
                detail: "Base dictionary · always enabled",
                isBase: true,
                isBuiltIn: true,
                isEnabled: true,
                canRemove: false,
                noticeURL: nil,
                importedEntryCount: nil,
                importedLanguages: nil,
                importedLicense: nil
            ),
            DictionaryManagerRow(
                id: "dev.twigaswitcher.base.russian",
                name: "Russian Frequency Dictionary",
                version: "wordfreq 3.1.1",
                detail: "Base dictionary · always enabled",
                isBase: true,
                isBuiltIn: true,
                isEnabled: true,
                canRemove: false,
                noticeURL: nil,
                importedEntryCount: nil,
                importedLanguages: nil,
                importedLicense: nil
            ),
            DictionaryManagerRow(
                id: "dev.twigaswitcher.dictionary.computer-terms",
                name: "Computer Terms",
                version: "1.0.0",
                detail: "Built-in subject dictionary",
                isBase: false,
                isBuiltIn: true,
                isEnabled: computerTermsSettings.isEnabled,
                canRemove: false,
                noticeURL: BundledLexiconResources.computerTermsNoticeURL(),
                importedEntryCount: nil,
                importedLanguages: nil,
                importedLicense: nil
            ),
        ]
        if let packs = try? store.installedPacks() {
            result.append(contentsOf: packs.map { pack in
                let count = pack.indexManifest.indexes.values.reduce(0) { $0 + $1.entryCount }
                let languages = pack.indexManifest.indexes.keys.sorted().joined(separator: ", ")
                let notice = pack.directoryURL.appendingPathComponent("NOTICE.txt")
                return DictionaryManagerRow(
                    id: pack.identifier,
                    name: pack.manifest.name,
                    version: pack.manifest.version,
                    detail: "\(languages) · \(count) entries · \(pack.manifest.attribution.license)",
                    isBase: false,
                    isBuiltIn: false,
                    isEnabled: store.isEnabled(pack.identifier),
                    canRemove: true,
                    noticeURL: FileManager.default.fileExists(atPath: notice.path) ? notice : nil,
                    importedEntryCount: count,
                    importedLanguages: languages,
                    importedLicense: pack.manifest.attribution.license
                )
            })
        }
        rows = result
    }

    public func importPackage(at url: URL) async {
        isWorking = true
        status = nil
        defer { isWorking = false }
        do {
            let installed = try await importer.importPackage(at: url, into: store.directoryURL, existingPolicy: .replace)
            try store.setEnabled(true, identifier: installed.identifier)
            await reloadCatalog()
            refresh()
            status = .imported(installed.manifest.name)
        } catch {
            status = .importFailed(String(describing: error))
        }
    }

    public func setEnabled(_ enabled: Bool, row: DictionaryManagerRow) async {
        guard !row.isBase else { return }
        do {
            if row.isBuiltIn {
                computerTermsSettings.isEnabled = enabled
            } else {
                try store.setEnabled(enabled, identifier: row.id)
            }
            await reloadCatalog()
            refresh()
        } catch {
            status = .updateDictionaryFailed(String(describing: error))
        }
    }

    public func remove(_ row: DictionaryManagerRow) async {
        guard row.canRemove, confirmRemoval(row) else { return }
        do {
            try store.removeConfirmed(identifier: row.id)
            await reloadCatalog()
            refresh()
        } catch {
            status = .removeDictionaryFailed(String(describing: error))
        }
    }

}
