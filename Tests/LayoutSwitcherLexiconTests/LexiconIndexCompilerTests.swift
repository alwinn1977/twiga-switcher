import Foundation
import XCTest
import LayoutSwitcherCore
@testable import LayoutSwitcherLexicon

final class LexiconIndexCompilerTests: XCTestCase {
    func testCompilerSortsNormalizedKeysAndProducesIdenticalBytes() throws {
        let entries = [
            LexiconEntry(language: .english, key: "World", score: 4_100, flags: []),
            LexiconEntry(language: .english, key: "hello", score: 5_200, flags: [])
        ]
        let directory = try temporaryDirectory()
        let first = directory.appendingPathComponent("first.lsidx")
        let second = directory.appendingPathComponent("second.lsidx")

        let firstMetadata = try LexiconIndexCompiler.compile(
            entries: entries,
            language: .english,
            to: first
        )
        let secondMetadata = try LexiconIndexCompiler.compile(
            entries: Array(entries.reversed()),
            language: .english,
            to: second
        )

        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: second))
        XCTAssertEqual(firstMetadata, secondMetadata)
        XCTAssertEqual(firstMetadata.entryCount, 2)
        XCTAssertEqual(firstMetadata.maximumPhraseWords, 1)
        XCTAssertEqual(firstMetadata.sha256.count, 64)
    }

    func testCompilerCollapsesIdenticalNormalizedDuplicates() throws {
        let output = try temporaryDirectory().appendingPathComponent("duplicate.lsidx")
        let metadata = try LexiconIndexCompiler.compile(
            entries: [
                .init(language: .english, key: "NODE.JS", score: 4_200, flags: [.subjectTerm]),
                .init(language: .english, key: "node.js", score: 4_200, flags: [.subjectTerm])
            ],
            language: .english,
            to: output
        )

        XCTAssertEqual(metadata.entryCount, 1)
    }

    func testCompilerRejectsConflictsAndInvalidEntries() throws {
        let output = try temporaryDirectory().appendingPathComponent("invalid.lsidx")

        XCTAssertThrowsError(try LexiconIndexCompiler.compile(
            entries: [
                .init(language: .english, key: "node.js", score: 4_200, flags: []),
                .init(language: .english, key: "NODE.JS", score: 4_100, flags: [])
            ],
            language: .english,
            to: output
        ))
        XCTAssertThrowsError(try LexiconIndexCompiler.compile(
            entries: [.init(language: .russian, key: "привет", score: 4_000, flags: [])],
            language: .english,
            to: output
        ))
        XCTAssertThrowsError(try LexiconIndexCompiler.compile(
            entries: [.init(language: .english, key: "hello", score: 8_001, flags: [])],
            language: .english,
            to: output
        ))
        XCTAssertThrowsError(try LexiconIndexCompiler.compile(
            entries: [.init(language: .english, key: String(repeating: "a", count: 129), score: 3_000, flags: [])],
            language: .english,
            to: output
        ))
        XCTAssertThrowsError(try LexiconIndexCompiler.compile(
            entries: [.init(language: .english, key: "one two three four five six seven eight nine", score: 3_000, flags: [])],
            language: .english,
            to: output
        ))
        XCTAssertThrowsError(try LexiconIndexCompiler.compile(
            entries: [.init(language: .english, key: "hello🙂", score: 3_000, flags: [])],
            language: .english,
            to: output
        ))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutSwitcherLexiconTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
