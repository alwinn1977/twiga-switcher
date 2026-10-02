import Combine
import Foundation
import TwigaSwitcherCore
@testable import TwigaSwitcherApp
import XCTest

@MainActor
final class RulesManagerModelTests: XCTestCase {
    func testOpenModelReflectsRulesSavedAndRemovedOutsideTheWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RulesModelChanges-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UserRuleStore(fileURL: root.appendingPathComponent("rules.json"))
        let model = RulesManagerModel(store: store)
        let added = expectation(description: "Rule added outside window")
        let changed = expectation(description: "Rule changed outside window")
        let removed = expectation(description: "Rules removed outside window")
        let subscription = model.$rules.dropFirst().sink { rules in
            if rules.isEmpty { removed.fulfill() }
            else if rules.first?.disposition == .always { added.fulfill() }
            else if rules.first?.disposition == .never { changed.fulfill() }
        }
        defer { subscription.cancel() }

        try await Task.detached {
            try store.set(disposition: .always, source: "ghbdtn", candidate: "привет")
        }.value
        let addedResult = await XCTWaiter.fulfillment(of: [added], timeout: 2)
        XCTAssertEqual(addedResult, .completed)
        XCTAssertEqual(model.rules, [.init(source: "ghbdtn", candidate: "привет", disposition: .always)])

        try store.set(disposition: .never, source: "ghbdtn", candidate: "привет")
        let changedResult = await XCTWaiter.fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(changedResult, .completed)
        XCTAssertEqual(model.rules.first?.disposition, .never)

        try store.removeAll()
        let removedResult = await XCTWaiter.fulfillment(of: [removed], timeout: 2)
        XCTAssertEqual(removedResult, .completed)
        XCTAssertTrue(model.rules.isEmpty)
    }

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
