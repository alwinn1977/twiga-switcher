import Foundation
import LayoutSwitcherCore
import LayoutSwitcherLexicon
@testable import LayoutSwitcherApp
import XCTest

final class LexiconServiceTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutSwitcherServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testValidBaseResourcesPublishWorkingSnapshot() throws {
        let base = try makeBaseLexicons()
        let service = LexiconService(baseLoader: { base }, packsRootURL: temporaryRoot.appendingPathComponent("packs"))

        try service.start()

        let snapshot = try XCTUnwrap(service.currentSnapshot)
        XCTAssertEqual(snapshot.lookup("hello", language: .english).score, 5_000)
        XCTAssertEqual(snapshot.lookup("привет", language: .russian).score, 5_100)
        XCTAssertNil(service.fatalDiagnostic)
    }

    func testMissingOrCorruptBaseResourcesFailClosed() throws {
        let service = LexiconService(
            baseLoader: { throw FixtureError.unavailable },
            packsRootURL: temporaryRoot.appendingPathComponent("packs")
        )

        XCTAssertThrowsError(try service.start())
        XCTAssertNil(service.currentSnapshot)
        XCTAssertNotNil(service.fatalDiagnostic)
        XCTAssertNil(service.catalog.lookup("hello", language: .english).score)
    }

    func testCorruptOptionalPackIsDisabledWithoutHidingBase() async throws {
        let packsRoot = temporaryRoot.appendingPathComponent("packs")
        let package = try makePackage()
        let installed = try await DictionaryPackImporter().importPackage(
            at: package,
            into: packsRoot,
            existingPolicy: .reject
        )
        let store = try DictionaryPackStore(rootURL: packsRoot)
        try store.setEnabled(true, identifier: installed.identifier)
        let indexURL = try XCTUnwrap(installed.englishIndexURL)
        var bytes = try Data(contentsOf: indexURL)
        bytes[bytes.index(before: bytes.endIndex)] ^= 0xFF
        try bytes.write(to: indexURL)

        let base = try makeBaseLexicons()
        let service = LexiconService(baseLoader: { base }, packsRootURL: packsRoot)
        try service.start()

        XCTAssertEqual(service.currentSnapshot?.lookup("hello", language: .english).score, 5_000)
        XCTAssertNil(service.currentSnapshot?.lookup("kubernetes", language: .english).score)
        XCTAssertFalse(try DictionaryPackStore(rootURL: packsRoot).isEnabled(installed.identifier))
        XCTAssertTrue(service.diagnostics.contains { $0.packIdentifier == installed.identifier })
    }

    private func makeBaseLexicons() throws -> BundledBaseLexicons {
        let englishURL = temporaryRoot.appendingPathComponent("base-en.lsidx")
        let russianURL = temporaryRoot.appendingPathComponent("base-ru.lsidx")
        let englishMetadata = try LexiconIndexCompiler.compile(
            entries: [.init(language: .english, key: "hello", score: 5_000, flags: [])],
            language: .english,
            to: englishURL
        )
        let russianMetadata = try LexiconIndexCompiler.compile(
            entries: [.init(language: .russian, key: "привет", score: 5_100, flags: [])],
            language: .russian,
            to: russianURL
        )
        let manifest = LexiconResourceManifest(
            minimumScore: 2_500,
            source: .init(name: "fixture", version: "1", sha256: "fixture", license: "Fixture"),
            indexes: [
                "en": .init(file: englishURL.lastPathComponent, sha256: englishMetadata.sha256, entryCount: 1, maximumPhraseWords: 1),
                "ru": .init(file: russianURL.lastPathComponent, sha256: russianMetadata.sha256, entryCount: 1, maximumPhraseWords: 1),
            ]
        )
        return BundledBaseLexicons(
            manifest: manifest,
            english: try MappedLexicon(url: englishURL, expectedLanguage: .english),
            russian: try MappedLexicon(url: russianURL, expectedLanguage: .russian)
        )
    }

    private func makePackage() throws -> URL {
        let package = temporaryRoot.appendingPathComponent("Terms.layoutdict", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let manifest = DictionaryPackManifest(
            identifier: "dev.layoutswitcher.test-terms",
            name: "Test Terms",
            version: "1.0.0",
            description: "Fixture",
            attribution: .init(source: "Tests", license: "MIT")
        )
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        try Data("en\t4200\tKubernetes\n".utf8).write(to: package.appendingPathComponent("entries.tsv"))
        return package
    }
}

private enum FixtureError: Error {
    case unavailable
}
