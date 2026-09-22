import Foundation
import LayoutSwitcherCore
@testable import LayoutSwitcherApp
import XCTest

final class LastCorrectionCoordinatorTests: XCTestCase {
    func testCommandZWithinLifetimeAndSameFocusBuildsReversalAndLearnsAfterSuccess() throws {
        final class ClockBox: @unchecked Sendable { var value = 100.0 }
        let clock = ClockBox()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("undo-rules-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UserRuleStore(fileURL: root.appendingPathComponent("rules.json"))
        let coordinator = LastCorrectionCoordinator(ruleStore: store, clock: { clock.value })
        let focus = FocusIdentity(processID: 1, elementHash: 2)
        coordinator.record(.init(source: "ghbdtn", candidate: "привет", delimiter: " ", focus: focus, originalLayout: .english))
        clock.value = 109.9

        let action = try XCTUnwrap(coordinator.handleCommandZ(currentFocus: focus))
        XCTAssertEqual(action.reversalPlan.deleteKeyCount, 7)
        XCTAssertEqual(action.reversalPlan.replacement, "ghbdtn")
        try coordinator.complete(action, result: .completed)
        XCTAssertEqual(store.disposition(source: "ghbdtn", candidate: "привет"), .never)
    }

    func testExpiredFocusMismatchAndInvalidationPassThroughWithoutLearning() throws {
        final class ClockBox: @unchecked Sendable { var value = 0.0 }
        let clock = ClockBox()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("undo-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UserRuleStore(fileURL: root.appendingPathComponent("rules.json"))
        let coordinator = LastCorrectionCoordinator(ruleStore: store, clock: { clock.value })
        let focus = FocusIdentity(processID: 1, elementHash: 2)
        let correction = LastCorrection(source: "a", candidate: "ф", delimiter: " ", focus: focus, originalLayout: .english)

        coordinator.record(correction)
        clock.value = 10.001
        XCTAssertNil(coordinator.handleCommandZ(currentFocus: focus))
        coordinator.record(correction)
        XCTAssertNil(coordinator.handleCommandZ(currentFocus: .init(processID: 1, elementHash: 3)))
        coordinator.record(correction)
        coordinator.invalidate()
        XCTAssertNil(coordinator.handleCommandZ(currentFocus: focus))
        XCTAssertTrue(store.loadSnapshot().rules.isEmpty)
    }

    func testFailedReversalDoesNotLearn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("undo-fail-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UserRuleStore(fileURL: root.appendingPathComponent("rules.json"))
        let coordinator = LastCorrectionCoordinator(ruleStore: store, clock: { 1 })
        let focus = FocusIdentity(processID: 1, elementHash: 2)
        coordinator.record(.init(source: "a", candidate: "ф", delimiter: " ", focus: focus, originalLayout: .english))
        let action = try XCTUnwrap(coordinator.handleCommandZ(currentFocus: focus))

        try coordinator.complete(action, result: .partialFailure)
        XCTAssertTrue(store.loadSnapshot().rules.isEmpty)
    }
}
