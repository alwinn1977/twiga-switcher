import LayoutSwitcherCore
import XCTest

final class TypingSessionDriverTests: XCTestCase {
    func testDriverAppliesMonitorReplacementToEditor() throws {
        let session = try TypingSessionDriver(initialLayout: .english)
        let trace = try session.type("привет \n", mode: .automatic)
        XCTAssertEqual(trace.editorText, "привет \n")
        XCTAssertEqual(trace.layoutSelections, [.russian])
        XCTAssertEqual(trace.manualSelections.count, 0)
        XCTAssertEqual(trace.automaticSelections, [.russian])
        XCTAssertEqual(trace.words.first?.raw, "ghbdtn")
        XCTAssertEqual(trace.words.first?.layoutAfter, .russian)
    }

    func testSyntheticReplacementIsNotInsertedTwice() throws {
        let session = try TypingSessionDriver(initialLayout: .english)
        let trace = try session.type("привет ", mode: .automatic, echoSyntheticEvents: true)
        XCTAssertEqual(trace.editorText, "привет ")
        XCTAssertEqual(trace.corrections.count, 1)
        XCTAssertEqual(trace.automaticSelections, [.russian])
    }

    func testManualSwitchUsesSameMonitorWithoutAutomaticReplacement() throws {
        let session = try TypingSessionDriver(initialLayout: .english)
        let trace = try session.type("привет hello\n", mode: .manualAtScriptChanges)
        XCTAssertEqual(trace.editorText, "привет hello\n")
        XCTAssertEqual(trace.manualSelections, [.russian, .english])
        XCTAssertEqual(trace.automaticSelections.count, 0)
        XCTAssertEqual(trace.corrections.count, 0)
    }

    func testBudgetCorrectsAfterEnglishTermAndLiteralComma() throws {
        let session = try TypingSessionDriver(initialLayout: .english)
        let trace = try session.type("PostgreSQL, бюджет ", mode: .automatic)
        XCTAssertEqual(trace.editorText, "PostgreSQL, бюджет ", trace.firstDivergence)
        XCTAssertEqual(trace.words.last?.raw, ",.l;tn")
        XCTAssertEqual(trace.words.last?.layoutAfter, .russian)
    }

    func testDivergenceNamesFirstWrongPhysicalKeyNotLineReturn() throws {
        let session = try TypingSessionDriver(initialLayout: .english)
        let trace = try session.type("йяй \n", mode: .automatic)
        XCTAssertNotEqual(trace.editorText, "йяй \n")
        XCTAssertTrue(trace.firstDivergence.contains("keycode 12"), trace.firstDivergence)
        XCTAssertTrue(trace.firstDivergence.contains("raw \"q\""), trace.firstDivergence)
    }
}
