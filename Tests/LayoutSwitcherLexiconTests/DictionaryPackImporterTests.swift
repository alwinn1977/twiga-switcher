import Foundation
import LayoutSwitcherCore
@testable import LayoutSwitcherLexicon
import XCTest

final class DictionaryPackImporterTests: XCTestCase {
    private var temporaryRoot: URL!
    private var installRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutSwitcherPackTests-\(UUID().uuidString)", isDirectory: true)
        installRoot = temporaryRoot.appendingPathComponent("Installed", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testImportsValidBilingualPhrasesCommentsAndPunctuation() async throws {
        let package = try makePackage(entries: """
            # project terms

            en\t4200\tNode.js
            en\t3900\tC++
            ru\t4100\tмашинное обучение
            """)

        let installed = try await DictionaryPackImporter().importPackage(
            at: package,
            into: installRoot,
            existingPolicy: .reject
        )

        XCTAssertEqual(installed.identifier, "dev.layoutswitcher.test")
        let english = try MappedLexicon(
            url: XCTUnwrap(installed.englishIndexURL),
            expectedLanguage: .english
        )
        let russian = try MappedLexicon(
            url: XCTUnwrap(installed.russianIndexURL),
            expectedLanguage: .russian
        )
        XCTAssertEqual(english.lookup("node.js", language: .english).score, 4_200)
        XCTAssertEqual(english.lookup("C++", language: .english).score, 3_900)
        XCTAssertTrue(english.lookup("node", language: .english).isStrictPrefix)
        XCTAssertEqual(russian.lookup("машинное обучение", language: .russian).score, 4_100)
    }

    func testRejectsMalformedRowsAndTerms() async throws {
        let invalidEntries = [
            Data([0x65, 0x6E, 0x09, 0x34, 0x30, 0x30, 0x30, 0x09, 0xFF]),
            Data("de\t4000\twort\n".utf8),
            Data("en\t-1\tword\n".utf8),
            Data("en\t8001\tword\n".utf8),
            Data("en\t4000\t123+\n".utf8),
            Data("en\t4000\tbad!term\n".utf8),
            Data("en\t4000\t\(String(repeating: "a", count: 129))\n".utf8),
            Data("en\t4000\tone two three four five six seven eight nine\n".utf8),
            Data("en\t4000\t\(String(repeating: "a", count: 4_090))\n".utf8),
        ]

        for entries in invalidEntries {
            let package = try makePackage(entriesData: entries)
            await XCTAssertThrowsErrorAsync {
                try await DictionaryPackImporter().importPackage(
                    at: package,
                    into: self.installRoot,
                    existingPolicy: .reject
                )
            }
            try? FileManager.default.removeItem(at: package)
        }
    }

    func testRejectsSourceSizeEntryCountDuplicateIdentifierAndTraversal() async throws {
        XCTAssertEqual(DictionaryPackImportLimits().maximumSourceBytes, 50 * 1_024 * 1_024)
        XCTAssertEqual(DictionaryPackImportLimits().maximumEntries, 1_000_000)
        let oversizedPackage = try makePackage(entries: "en\t4000\tword\n")
        let oversizedImporter = DictionaryPackImporter(limits: .init(
            maximumSourceBytes: 8,
            maximumEntries: 1_000_000,
            maximumLineBytes: 4_096
        ))
        await XCTAssertThrowsErrorAsync {
            try await oversizedImporter.importPackage(at: oversizedPackage, into: self.installRoot, existingPolicy: .reject)
        }

        let tooManyPackage = try makePackage(entries: "en\t4000\tone\nen\t4000\ttwo\nen\t4000\tthree\n")
        let boundedImporter = DictionaryPackImporter(limits: .init(
            maximumSourceBytes: 50 * 1_024 * 1_024,
            maximumEntries: 2,
            maximumLineBytes: 4_096
        ))
        await XCTAssertThrowsErrorAsync {
            try await boundedImporter.importPackage(at: tooManyPackage, into: self.installRoot, existingPolicy: .reject)
        }

        let valid = try makePackage(entries: "en\t4000\tfirst\n")
        _ = try await DictionaryPackImporter().importPackage(at: valid, into: installRoot, existingPolicy: .reject)
        let duplicate = try makePackage(entries: "en\t4000\tsecond\n")
        await XCTAssertThrowsErrorAsync {
            try await DictionaryPackImporter().importPackage(at: duplicate, into: self.installRoot, existingPolicy: .reject)
        }

        let traversal = try makePackage(
            identifier: "dev.layoutswitcher.test/../../outside",
            entries: "en\t4000\tword\n"
        )
        await XCTAssertThrowsErrorAsync {
            try await DictionaryPackImporter().importPackage(at: traversal, into: self.installRoot, existingPolicy: .reject)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent("outside").path))
    }

    func testRejectsActualFiftyMiBSourceLimitBeforeParsing() async throws {
        let package = try makePackage(entries: "en\t4000\tword\n")
        let handle = try FileHandle(forWritingTo: package.appendingPathComponent("entries.tsv"))
        try handle.truncate(atOffset: UInt64(50 * 1_024 * 1_024 + 1))
        try handle.close()

        await XCTAssertThrowsErrorAsync {
            try await DictionaryPackImporter().importPackage(
                at: package,
                into: self.installRoot,
                existingPolicy: .reject
            )
        }
    }

    func testCancellationNeverPublishesPartialPack() async throws {
        let rows = String(repeating: "en\t4000\tcancellable\n", count: 100_000)
        let package = try makePackage(entries: rows)
        let destinationRoot = try XCTUnwrap(installRoot)
        let task = Task {
            try await DictionaryPackImporter().importPackage(
                at: package,
                into: destinationRoot,
                existingPolicy: .reject
            )
        }
        task.cancel()

        await XCTAssertThrowsErrorAsync { try await task.value }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destinationRoot.appendingPathComponent("dev.layoutswitcher.test").path
        ))
    }

    func testRejectsSymlinkedPackageFiles() async throws {
        let package = try makePackage(entries: "en\t4000\tword\n")
        let external = temporaryRoot.appendingPathComponent("external.tsv")
        try Data("en\t5000\texternal\n".utf8).write(to: external)
        let entriesURL = package.appendingPathComponent("entries.tsv")
        try FileManager.default.removeItem(at: entriesURL)
        try FileManager.default.createSymbolicLink(at: entriesURL, withDestinationURL: external)

        await XCTAssertThrowsErrorAsync {
            try await DictionaryPackImporter().importPackage(at: package, into: self.installRoot, existingPolicy: .reject)
        }
    }

    func testFailedUpdatePreservesWorkingPackAndEnabledState() async throws {
        let importer = DictionaryPackImporter()
        let originalPackage = try makePackage(entries: "en\t4000\toriginal\n")
        let original = try await importer.importPackage(at: originalPackage, into: installRoot, existingPolicy: .reject)
        let originalURL = try XCTUnwrap(original.englishIndexURL)
        let before = try Data(contentsOf: originalURL)
        let store = try DictionaryPackStore(rootURL: installRoot)
        try store.setEnabled(true, identifier: original.identifier)

        let corruptUpdate = try makePackage(entries: "en\t9000\tbroken\n")
        await XCTAssertThrowsErrorAsync {
            try await importer.importPackage(at: corruptUpdate, into: self.installRoot, existingPolicy: .replace)
        }

        XCTAssertEqual(try Data(contentsOf: originalURL), before)
        XCTAssertTrue(store.isEnabled(original.identifier))
    }

    func testSuccessfulUpdateAndConfirmedRemovalAreScoped() async throws {
        let importer = DictionaryPackImporter()
        let first = try makePackage(entries: "en\t4000\told\n")
        let installed = try await importer.importPackage(at: first, into: installRoot, existingPolicy: .reject)
        let sibling = installRoot.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sibling)

        let update = try makePackage(entries: "en\t5000\tnew\n")
        let replaced = try await importer.importPackage(at: update, into: installRoot, existingPolicy: .replace)
        let mapped = try MappedLexicon(url: XCTUnwrap(replaced.englishIndexURL), expectedLanguage: .english)
        XCTAssertEqual(mapped.lookup("new", language: .english).score, 5_000)
        XCTAssertNil(mapped.lookup("old", language: .english).score)

        let store = try DictionaryPackStore(rootURL: installRoot)
        try store.setEnabled(true, identifier: installed.identifier)
        try store.removeConfirmed(identifier: installed.identifier)
        XCTAssertFalse(store.isEnabled(installed.identifier))
        XCTAssertFalse(FileManager.default.fileExists(atPath: replaced.directoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }

    func testStoreReloadDropsEnabledIdentifiersWithoutInstalledPacks() throws {
        try FileManager.default.createDirectory(at: installRoot, withIntermediateDirectories: true)
        let store = try DictionaryPackStore(rootURL: installRoot)
        try store.setEnabled(true, identifier: "dev.layoutswitcher.missing")

        let reloaded = try DictionaryPackStore(rootURL: installRoot)
        XCTAssertFalse(reloaded.isEnabled("dev.layoutswitcher.missing"))
    }

    private func makePackage(
        identifier: String = "dev.layoutswitcher.test",
        entries: String
    ) throws -> URL {
        try makePackage(identifier: identifier, entriesData: Data(entries.utf8))
    }

    private func makePackage(
        identifier: String = "dev.layoutswitcher.test",
        entriesData: Data
    ) throws -> URL {
        let package = temporaryRoot.appendingPathComponent("Pack-\(UUID().uuidString).layoutdict", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let manifest = DictionaryPackManifest(
            identifier: identifier,
            name: "Test Pack",
            version: "1.0.0",
            description: "Test terms",
            attribution: .init(source: "Test fixtures", license: "MIT")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        try entriesData.write(to: package.appendingPathComponent("entries.tsv"))
        return package
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> some Any,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {}
}
