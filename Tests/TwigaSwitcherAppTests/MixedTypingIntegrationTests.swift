import TwigaSwitcherCore
import XCTest

final class MixedTypingIntegrationTests: XCTestCase {
    func testLowercaseRussianConnectivesBetweenEnglishWords() throws {
        for expected in ["windows и linux ", "elephant а mouse ", "cat и dog "] {
            let session = try TypingSessionDriver(initialLayout: .english)
            let trace = try session.type(expected, mode: .automatic)
            XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
        }
    }

    func testEnglishSingleLetterWordsAndLowercaseInitialismsStayUnchanged() throws {
        for expected in ["a cat ", "i write ", "b.b hello ", "f.b.i hello "] {
            let session = try TypingSessionDriver(initialLayout: .english)
            let trace = try session.type(expected, mode: .automatic)
            XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
            XCTAssertTrue(trace.corrections.isEmpty)
        }
    }

    func testReportedRussianConnectivesBetweenEnglishAnimalNames() throws {
        let expected = "У попа была собака и elephant а также мышь and rat и кролик "
        let session = try TypingSessionDriver(initialLayout: .english)
        let trace = try session.type(expected, mode: .automatic)
        XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
    }

    func testSingleLetterRussianWordsAtSentenceStart() throws {
        for expected in [
            "А потом привет.\n", "И потом привет.\n", "О проекте.\n", "У меня привет.\n",
            "В проекте.\n", "К проекту.\n", "С проектом.\n", "Я пишу.\n"
        ] {
            let session = try TypingSessionDriver(initialLayout: .english)
            let trace = try session.type(expected, mode: .automatic)
            XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
        }
    }

    func testSingleLetterRussianWordsInMixedTextAndBeforePunctuation() throws {
        for expected in [
            "Linux а потом привет.\n", "Linux и в проекте.\n", "И у меня привет!\n",
            "А привет, потом привет.\n", "С меню.\n", "А я пишу.\n"
        ] {
            let session = try TypingSessionDriver(initialLayout: .english)
            let trace = try session.type(expected, mode: .automatic)
            XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
        }
    }

    func testSingleLetterEnglishWordsAndInitialismsStayUnchanged() throws {
        for expected in ["A hello.\n", "B hello.\n", "B B hello.\n", "C developer.\n", "F test.\n", "B.B hello.\n"] {
            let session = try TypingSessionDriver(initialLayout: .english)
            let trace = try session.type(expected, mode: .automatic)
            XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
            XCTAssertTrue(trace.corrections.isEmpty)
        }
    }

    func testSingleLetterRussianWordBeforeMultiwordDictionaryTerm() throws {
        let expected = "И искусственный интеллект.\n"
        let session = try TypingSessionDriver(initialLayout: .english)
        let trace = try session.type(expected, mode: .automatic)
        XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
    }

    func testSingleLetterRussianWordsTypedInCorrectLayoutStayUnchanged() throws {
        let expected = "А потом привет. И потом привет. О проекте. У меня привет. В проекте. К проекту. С проектом. Я пишу.\n"
        let session = try TypingSessionDriver(initialLayout: .russian)
        let trace = try session.type(expected, mode: .manualAtScriptChanges)
        XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
        XCTAssertTrue(trace.corrections.isEmpty)
    }

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
        XCTAssertEqual(trace.words.first?.raw, "rjvgьютер")
        XCTAssertEqual(trace.words.first?.layoutAfter, .russian)
        XCTAssertTrue(trace.corrections.contains { $0.layoutBefore == .english && $0.layoutAfter == .russian })
        XCTAssertTrue(trace.corrections.contains { $0.layoutBefore == .russian && $0.layoutAfter == .english })
        for (intended, raw) in [
            ("компьютер", "rjvgьютер"), ("меню", "vty."),
            ("люди", "k.lb"), ("бюджет", ",.l;tт"),
            ("любой", "k.,jй"), ("ключ", "rk.x"),
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
