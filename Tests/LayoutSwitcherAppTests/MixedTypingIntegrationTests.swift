import LayoutSwitcherCore
import XCTest

final class MixedTypingIntegrationTests: XCTestCase {
    func testTwentyFourLinesWithoutManualLayoutSwitches() throws {
        let session = try TypingSessionDriver(initialLayout: .english)
        let trace = try session.type(MixedTypingCorpus.expected, mode: .automatic)
        print("Automatic corpus processing: \(trace.processingDurationSeconds * 1_000) ms")
        XCTAssertEqual(trace.linePrefixes.count, 24)
        for (index, actual) in trace.linePrefixes.enumerated() {
            guard actual.utf8.elementsEqual(MixedTypingCorpus.expectedLinePrefixes[index].utf8) else {
                XCTFail("line \(index + 1): \(trace.firstDivergence)")
                return
            }
        }
        XCTAssertTrue(trace.editorText.utf8.elementsEqual(MixedTypingCorpus.expected.utf8))
        XCTAssertEqual(trace.manualSelections.count, 0)
        XCTAssertFalse(trace.automaticSelections.isEmpty)
        XCTAssertEqual(trace.words.first?.raw, "rjvgm.nth")
        XCTAssertEqual(trace.words.first?.layoutAfter, .russian)
        XCTAssertTrue(trace.corrections.contains { $0.layoutBefore == .english && $0.layoutAfter == .russian })
        XCTAssertTrue(trace.corrections.contains { $0.layoutBefore == .russian && $0.layoutAfter == .english })
        for (intended, raw) in [
            ("компьютер", "rjvgm.nth"), ("меню", "vty."),
            ("люди", "k.lb"), ("бюджет", ",.l;tn"),
            ("любой", "k.,jq"), ("ключ", "rk.x"),
            ("мьютекс", "vm.ntrc"), ("плюс", "gk.c")
        ] {
            let word = trace.words.first { $0.intended == intended }
            XCTAssertEqual(word?.raw, raw, intended)
            XCTAssertEqual(word?.layoutBefore, .english, intended)
            XCTAssertEqual(word?.layoutAfter, .russian, intended)
            XCTAssertTrue(word?.corrected == true, intended)
        }
    }

    func testTwentyFourLinesWithManualLayoutSwitches() throws {
        let session = try TypingSessionDriver(initialLayout: .english)
        let trace = try session.type(MixedTypingCorpus.expected, mode: .manualAtScriptChanges)
        print("Manual corpus processing: \(trace.processingDurationSeconds * 1_000) ms")
        XCTAssertEqual(trace.linePrefixes.count, 24)
        for (index, actual) in trace.linePrefixes.enumerated() {
            guard actual.utf8.elementsEqual(MixedTypingCorpus.expectedLinePrefixes[index].utf8) else {
                XCTFail("line \(index + 1): \(trace.firstDivergence)")
                return
            }
        }
        XCTAssertTrue(trace.editorText.utf8.elementsEqual(MixedTypingCorpus.expected.utf8))
        XCTAssertFalse(trace.manualSelections.isEmpty)
        XCTAssertEqual(trace.automaticSelections.count, 0)
        XCTAssertEqual(trace.corrections.count, 0, "Correctly typed words were changed: \(trace.corrections)")
        XCTAssertEqual(trace.words.first?.raw, "компьютер")
        XCTAssertEqual(trace.words.first?.layoutAfter, .russian)
    }
}
