import Foundation
import TwigaSwitcherCore
@testable import TwigaSwitcherApp
import XCTest

final class UserRuleStoreTests: XCTestCase {
    private var root: URL!
    private var file: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RuleTests-\(UUID().uuidString)")
        file = root.appendingPathComponent("rules.json")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testRoundTripNormalizationReplacementAndMinimalSchema() throws {
        let store = try UserRuleStore(fileURL: file)
        try store.set(disposition: .always, source: "  GHBDTN ", candidate: "ПРИВЕТ")
        try store.set(disposition: .never, source: "ghbdtn", candidate: "привет")

        let reloaded = try UserRuleStore(fileURL: file)
        XCTAssertEqual(reloaded.loadSnapshot().rules.count, 1)
        XCTAssertEqual(reloaded.disposition(source: "GHBDTN", candidate: "ПРИВЕТ"), .never)
        let json = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(json.contains("schemaVersion"))
        XCTAssertFalse(json.contains("timestamp"))
        XCTAssertFalse(json.contains("application"))
        XCTAssertFalse(json.contains("context"))
    }

    func testMalformedJSONIsQuarantined() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)

        let store = try UserRuleStore(fileURL: file)

        XCTAssertTrue(store.loadSnapshot().rules.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
    }

    func testFailedAtomicWriteKeepsOldDiskAndMemorySnapshot() throws {
        let initial = try UserRuleStore(fileURL: file)
        try initial.set(disposition: .always, source: "one", candidate: "дту")
        let before = try Data(contentsOf: file)
        let failing = try UserRuleStore(fileURL: file) { _ in throw FixtureWriteError.failed }

        XCTAssertThrowsError(try failing.set(disposition: .never, source: "two", candidate: "ецщ"))
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertNil(failing.disposition(source: "two", candidate: "ецщ"))
    }

    func testRemoveSelectedAndAll() throws {
        let store = try UserRuleStore(fileURL: file)
        try store.set(disposition: .always, source: "one", candidate: "дту")
        try store.set(disposition: .never, source: "two", candidate: "ецщ")
        try store.remove(try XCTUnwrap(store.loadSnapshot().rules.first))
        XCTAssertEqual(store.loadSnapshot().rules.count, 1)
        try store.removeAll()
        XCTAssertTrue(store.loadSnapshot().rules.isEmpty)
    }
}

private enum FixtureWriteError: Error { case failed }
