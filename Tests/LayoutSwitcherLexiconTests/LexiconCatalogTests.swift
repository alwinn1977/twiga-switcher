import Foundation
import LayoutSwitcherCore
@testable import LayoutSwitcherLexicon
import XCTest

final class LexiconCatalogTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutSwitcherCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testSubjectPriorityLongestPhrasePrefixAndEnabledSnapshots() throws {
        let base = try mapped(
            name: "base",
            language: .english,
            entries: [("node", 7_000), ("ordinary", 4_000)]
        )
        let subject = try mapped(
            name: "subject",
            language: .english,
            entries: [("node", 3_000), ("node.js", 4_200), ("machine learning", 4_100)]
        )
        let enabled = LexiconCatalogSnapshot(
            baseLexicons: [base],
            subjectLexicons: [subject]
        )
        let disabled = LexiconCatalogSnapshot(
            baseLexicons: [base],
            subjectLexicons: []
        )

        XCTAssertEqual(enabled.maximumPhraseWords, 2)
        XCTAssertEqual(enabled.lookup("node", language: .english).score, 3_000)
        XCTAssertTrue(enabled.lookup("node", language: .english).isSubjectTerm)
        XCTAssertTrue(enabled.lookup("machine", language: .english).isStrictPrefix)
        XCTAssertEqual(enabled.lookup("machine learning", language: .english).score, 4_100)
        XCTAssertNil(disabled.lookup("node.js", language: .english).score)
        XCTAssertEqual(disabled.lookup("node", language: .english).score, 7_000)
        XCTAssertFalse(disabled.lookup("node", language: .english).isSubjectTerm)
    }

    func testConcurrentReadersObserveOnlyWholePublishedSnapshots() throws {
        let first = try mapped(name: "first", language: .english, entries: [("generation", 1_111)])
        let second = try mapped(name: "second", language: .english, entries: [("generation", 2_222)])
        let firstSnapshot = LexiconCatalogSnapshot(baseLexicons: [first], subjectLexicons: [])
        let secondSnapshot = LexiconCatalogSnapshot(baseLexicons: [second], subjectLexicons: [])
        let catalog = LexiconCatalog(initialSnapshot: firstSnapshot)
        let failures = LockedFailures()
        let group = DispatchGroup()

        for _ in 0..<8 {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                for _ in 0..<2_000 {
                    let score = catalog.lookup("generation", language: .english).score
                    if score != 1_111 && score != 2_222 {
                        failures.record(score)
                    }
                }
            }
        }
        for index in 0..<100 {
            catalog.replaceSnapshot(index.isMultiple(of: 2) ? secondSnapshot : firstSnapshot)
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(failures.values.isEmpty, "Unexpected scores: \(failures.values)")
        XCTAssertTrue(catalog.snapshot() === firstSnapshot)
    }

    private func mapped(
        name: String,
        language: Language,
        entries: [(String, Int)]
    ) throws -> MappedLexicon {
        let url = temporaryRoot.appendingPathComponent("\(name).lsidx")
        _ = try LexiconIndexCompiler.compile(
            entries: entries.map {
                LexiconEntry(language: language, key: $0.0, score: $0.1, flags: [])
            },
            language: language,
            to: url
        )
        return try MappedLexicon(url: url, expectedLanguage: language)
    }
}

private final class LockedFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int?] = []

    var values: [Int?] { lock.withLock { storage } }
    func record(_ score: Int?) { lock.withLock { storage.append(score) } }
}
