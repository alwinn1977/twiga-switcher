import Foundation
import LayoutSwitcherLexicon
@testable import LayoutSwitcherApp
import XCTest

final class DictionaryManagerModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DictionaryModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    @MainActor
    func testBaseCannotToggleAndComputerTermsDefaultsEnabledButCanToggle() async throws {
        let store = try DictionaryPackStore(rootURL: root.appendingPathComponent("installed"))
        let suite = "DictionaryManagerModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DictionaryManagerModel(
            store: store,
            computerTermsSettings: ComputerTermsSettings(defaults: defaults)
        )
        let base = try XCTUnwrap(model.rows.first { $0.isBase })
        let builtIn = try XCTUnwrap(model.rows.first { $0.id.contains("computer-terms") })

        await model.setEnabled(false, row: base)
        await model.remove(base)
        await model.setEnabled(false, row: builtIn)

        XCTAssertTrue(model.rows.first { $0.id == base.id }?.isEnabled == true)
        XCTAssertTrue(builtIn.isEnabled)
        XCTAssertFalse(model.rows.first { $0.id == builtIn.id }?.isEnabled == true)
        XCTAssertFalse(base.canRemove)
    }

    @MainActor
    func testImportToggleAndConfirmedRemoval() async throws {
        final class Confirmation { var allowed = false }
        let confirmation = Confirmation()
        let store = try DictionaryPackStore(rootURL: root.appendingPathComponent("installed"))
        let model = DictionaryManagerModel(
            store: store,
            confirmRemoval: { _ in confirmation.allowed }
        )
        let package = try makePackage()

        await model.importPackage(at: package)
        var row = try XCTUnwrap(model.rows.first { $0.id == "dev.layoutswitcher.model-test" })
        XCTAssertTrue(row.isEnabled)
        await model.setEnabled(false, row: row)
        row = try XCTUnwrap(model.rows.first { $0.id == row.id })
        XCTAssertFalse(row.isEnabled)

        await model.remove(row)
        XCTAssertNotNil(model.rows.first { $0.id == row.id })
        confirmation.allowed = true
        await model.remove(row)
        XCTAssertNil(model.rows.first { $0.id == row.id }, model.statusMessage ?? "no status")
    }

    @MainActor
    func testInvalidImportReportsValidationError() async throws {
        let store = try DictionaryPackStore(rootURL: root.appendingPathComponent("installed"))
        let model = DictionaryManagerModel(store: store)
        let package = try makePackage(entries: "xx\t9000\tbroken!\n")

        await model.importPackage(at: package)

        XCTAssertTrue(model.statusMessage?.contains("Import failed") == true)
        XCTAssertEqual(model.rows.filter { !$0.isBuiltIn }.count, 0)
    }

    private func makePackage(entries: String = "en\t4200\tGraphQL\n") throws -> URL {
        let package = root.appendingPathComponent("Model.layoutdict", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let manifest = DictionaryPackManifest(
            identifier: "dev.layoutswitcher.model-test",
            name: "Model Test",
            version: "1.0.0",
            description: "Fixture",
            attribution: .init(source: "Tests", license: "MIT")
        )
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        try Data(entries.utf8).write(to: package.appendingPathComponent("entries.tsv"))
        return package
    }
}
