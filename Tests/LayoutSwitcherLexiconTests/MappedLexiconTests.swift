import Foundation
import XCTest
import LayoutSwitcherCore
@testable import LayoutSwitcherLexicon

final class MappedLexiconTests: XCTestCase {
    func testWordCompletionUsesFrequencyAndLanguageWithoutChangingPhrasePrefixMeaning() throws {
        let url = try compileFixture([
            .init(language: .english, key: "hello", score: 5_000, flags: []),
            .init(language: .english, key: "hellos", score: 3_000, flags: [])
        ])
        let lexicon = try MappedLexicon(url: url, expectedLanguage: .english)
        XCTAssertTrue(lexicon.hasCompletion(for: "HELL", language: .english, minimumScore: 4_000))
        XCTAssertTrue(lexicon.hasCompletion(for: "hello", language: .english, minimumScore: 4_000))
        XCTAssertFalse(lexicon.lookup("hell", language: .english).isStrictPrefix)
        XCTAssertFalse(lexicon.hasCompletion(for: "hellos", language: .english, minimumScore: 4_000))
        XCTAssertFalse(lexicon.hasCompletion(for: "hell", language: .russian, minimumScore: 0))
        XCTAssertFalse(lexicon.hasCompletion(for: "", language: .english, minimumScore: 0))
        XCTAssertFalse(lexicon.hasCompletion(for: "absent", language: .english, minimumScore: 0))
    }

    func testMappedLookupFindsEdgesPrefixSubjectFlagAndMiss() throws {
        let url = try compileFixture([
            .init(language: .english, key: "alpha", score: 3_000, flags: []),
            .init(language: .english, key: "Node.js runtime", score: 4_200, flags: [.subjectTerm]),
            .init(language: .english, key: "zulu", score: 2_800, flags: [])
        ])

        let lexicon = try MappedLexicon(url: url, expectedLanguage: .english)

        XCTAssertEqual(lexicon.entryCount, 3)
        XCTAssertEqual(lexicon.maximumPhraseWords, 2)
        XCTAssertEqual(lexicon.lookup("ALPHA", language: .english).score, 3_000)
        XCTAssertTrue(lexicon.lookup("node.js", language: .english).isStrictPrefix)
        XCTAssertTrue(lexicon.lookup("node.js runtime", language: .english).isSubjectTerm)
        XCTAssertNil(lexicon.lookup("missing", language: .english).score)
        XCTAssertEqual(lexicon.lookup("zulu", language: .english).score, 2_800)
        XCTAssertEqual(lexicon.lookup("alpha", language: .russian), .missing)
    }

    func testMappedLookupUsesTheSameUnicodeNormalizationAsCompiler() throws {
        let url = try compileFixture([
            .init(language: .english, key: "CAFÉ", score: 3_500, flags: [])
        ])
        let lexicon = try MappedLexicon(url: url, expectedLanguage: .english)

        XCTAssertEqual(lexicon.lookup("cafe\u{301}", language: .english).score, 3_500)
    }

    func testLongerSingleWordDoesNotMarkCompleteWordAsPhrasePrefix() throws {
        let url = try compileFixture([
            .init(language: .english, key: "hello", score: 5_000, flags: []),
            .init(language: .english, key: "hellos", score: 3_000, flags: [])
        ])
        let lexicon = try MappedLexicon(url: url, expectedLanguage: .english)

        XCTAssertFalse(lexicon.lookup("hello", language: .english).isStrictPrefix)
    }

    func testSpaceAndPeriodContinuationMarkPhrasePrefix() throws {
        let url = try compileFixture([
            .init(language: .english, key: "machine learning", score: 4_200, flags: [.subjectTerm]),
            .init(language: .english, key: "node.js", score: 4_200, flags: [.subjectTerm])
        ])
        let lexicon = try MappedLexicon(url: url, expectedLanguage: .english)

        XCTAssertTrue(lexicon.lookup("machine", language: .english).isStrictPrefix)
        XCTAssertTrue(lexicon.lookup("node", language: .english).isStrictPrefix)
    }

    func testRejectsEveryTruncationBeforePublishingMappedPointers() throws {
        let completeURL = try compileFixture([
            .init(language: .english, key: "hello", score: 5_000, flags: [])
        ])
        let complete = try Data(contentsOf: completeURL)

        for length in 0..<complete.count {
            XCTAssertThrowsError(
                try openMapped(Data(complete.prefix(length))),
                "truncation at byte \(length) must fail"
            )
        }
    }

    func testRejectsWrongLanguageVersionChecksumAndRecordOffset() throws {
        let url = try compileFixture([
            .init(language: .english, key: "hello", score: 5_000, flags: [])
        ])
        XCTAssertThrowsError(try MappedLexicon(url: url, expectedLanguage: .russian))

        var wrongVersion = try Data(contentsOf: url)
        wrongVersion[4] = 0xFF
        wrongVersion[5] = 0x7F
        XCTAssertThrowsError(try openMapped(wrongVersion))

        var wrongChecksum = try Data(contentsOf: url)
        wrongChecksum[wrongChecksum.count - 1] ^= 0x01
        XCTAssertThrowsError(try openMapped(wrongChecksum))

        var wrongOffset = try Data(contentsOf: url)
        wrongOffset.replaceSubrange(72..<80, with: repeatElement(UInt8.max, count: 8))
        XCTAssertThrowsError(try openMapped(wrongOffset))
    }

    private func compileFixture(_ entries: [LexiconEntry]) throws -> URL {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("fixture.lsidx")
        _ = try LexiconIndexCompiler.compile(entries: entries, language: .english, to: url)
        return url
    }

    private func openMapped(_ data: Data) throws -> MappedLexicon {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("bytes.lsidx")
        try data.write(to: url)
        return try MappedLexicon(url: url, expectedLanguage: .english)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MappedLexiconTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
