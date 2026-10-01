import Foundation
import TwigaSwitcherCore
@testable import TwigaSwitcherApp
import XCTest

@MainActor
final class RulesManagerModelTests: XCTestCase {
    func testDeterministicListDeleteAndConfirmedDeleteAll() throws {
        final class Confirmation { var allowed = false }
        let confirmation = Confirmation()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RulesModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UserRuleStore(fileURL: root.appendingPathComponent("rules.json"))
        try store.set(disposition: .never, source: "zeta", candidate: "яуеф")
        try store.set(disposition: .always, source: "alpha", candidate: "фдзрф")
        let model = RulesManagerModel(store: store, confirmDeleteAll: { confirmation.allowed })

        XCTAssertEqual(model.rules.map(\.source), ["alpha", "zeta"])
        model.remove(model.rules[0])
        XCTAssertEqual(model.rules.map(\.source), ["zeta"])
        model.removeAll()
        XCTAssertEqual(model.rules.count, 1)
        confirmation.allowed = true
        model.removeAll()
        XCTAssertTrue(model.rules.isEmpty)
    }
}
