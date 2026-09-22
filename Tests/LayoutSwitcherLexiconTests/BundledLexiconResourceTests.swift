import Foundation
import LayoutSwitcherCore
@testable import LayoutSwitcherLexicon
import Testing

@Suite("Bundled frequency lexicons")
struct BundledLexiconResourceTests {
    @Test("loads and verifies the pinned English and Russian indexes")
    func loadsBaseIndexes() throws {
        let resources = try BundledLexiconResources.loadBase()

        #expect(resources.manifest.schemaVersion == 1)
        #expect(resources.manifest.minimumScore == 2_500)
        #expect(resources.manifest.source.name == "wordfreq")
        #expect(resources.manifest.source.version == "3.1.1")
        #expect(resources.manifest.source.sha256 == "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473")
        #expect(resources.english.entryCount == resources.manifest.indexes["en"]?.entryCount)
        #expect(resources.russian.entryCount == resources.manifest.indexes["ru"]?.entryCount)
        #expect(resources.english.lookup("development", language: .english).score ?? 0 >= 2_500)
        #expect(resources.russian.lookup("разработчики", language: .russian).score ?? 0 >= 2_500)
        #expect(resources.russian.lookup("ghbdtn", language: .russian) == .missing)
    }

    @Test("ships attribution and the complete data license")
    func includesLicenseNotices() throws {
        let notices = try BundledLexiconResources.loadNotices()

        #expect(notices.wordfreq.contains("wordfreq"))
        #expect(notices.wordfreq.contains("Creative Commons Attribution-ShareAlike 4.0"))
        #expect(notices.dataLicense.contains("Creative Commons Attribution-ShareAlike 4.0"))
    }
}
