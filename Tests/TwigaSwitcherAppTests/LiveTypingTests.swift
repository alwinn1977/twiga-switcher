import Foundation
import CoreGraphics
import XCTest
import TwigaSwitcherCore
import TwigaSwitcherLexicon
@testable import TwigaSwitcherApp

final class LiveTypingTests: XCTestCase {
    private let focus = FocusSnapshot(identity: .init(processID: 42, elementHash: 7))

    private func pipeline(
        rules: [UserRule] = [], english: [String] = ["hello", "printer"], russianScore: Int = 5_000
    ) throws
        -> InputPipeline<LexiconCatalog, UserRuleSnapshot> {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        var dictionaries: [MappedLexicon] = []
        for (language, words) in [(Language.english, english), (.russian, ["привет", "приветы", "да"])] {
            let url = root.appendingPathComponent(language == .english ? "en" : "ru")
            _ = try LexiconIndexCompiler.compile(
                entries: words.map { .init(language: language, key: $0,
                                          score: language == .russian ? russianScore : 5_000, flags: []) },
                language: language, to: url
            )
            dictionaries.append(try MappedLexicon(url: url, expectedLanguage: language))
        }
        return InputPipeline(converter: LayoutConverter(), detector: LanguageDetector(
            lexicon: LexiconCatalog(initialSnapshot: .init(baseLexicons: dictionaries, subjectLexicons: [])),
            rules: UserRuleSnapshot(rules: rules)
        ))
    }

    func testIncompleteWordCorrectsOnFourthKeyAndKeepsWholeWordForBackspaceAndForce() throws {
        var input = try pipeline()
        for character in "ghb" { XCTAssertEqual(input.handle(.character(character), focusIsSafe: true), .passThrough) }
        XCTAssertEqual(input.handle(.character("d"), focusIsSafe: true), .replace(.init(
            deleteKeyCount: 3, replacement: "прив", delimiter: "", targetLayout: .russian
        )))
        XCTAssertEqual(input.handle(.character("е"), focusIsSafe: true), .passThrough)
        _ = input.handle(.backspace, focusIsSafe: true)
        XCTAssertEqual(input.forceCorrection(focusIsSafe: true), .replace(.init(
            deleteKeyCount: 4, replacement: "ghbd", delimiter: "", targetLayout: .english
        )))
    }

    func testKnownSourcePrefixAndNeverRulePreventEarlyCorrection() throws {
        var recognized = try pipeline(english: ["ghbdmore"])
        var forbidden = try pipeline(rules: [.init(source: "ghbdtn", candidate: "привет", disposition: .never)])
        for character in "ghbd" {
            XCTAssertEqual(recognized.handle(.character(character), focusIsSafe: true), .passThrough)
            XCTAssertEqual(forbidden.handle(.character(character), focusIsSafe: true), .passThrough)
        }
    }

    func testNeverRuleLearnedForPrefixAlsoPreventsCorrectionOfCompletedWord() throws {
        var input = try pipeline(rules: [.init(source: "ghbd", candidate: "прив", disposition: .never)])
        for character in "ghbdtn" { XCTAssertEqual(input.handle(.character(character), focusIsSafe: true), .passThrough) }
        XCTAssertEqual(input.handle(.boundary(" "), focusIsSafe: true), .passThrough)
    }

    func testLowerFrequencyCompletionWaitsForBoundary() throws {
        var input = try pipeline(russianScore: 3_000)
        for character in "ghbdtn" { XCTAssertEqual(input.handle(.character(character), focusIsSafe: true), .passThrough) }
        XCTAssertEqual(input.handle(.boundary(" "), focusIsSafe: true), .replace(.init(
            deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian
        )))
    }

    func testLiveCorrectionRequiresFreshMatchingFocus() throws {
        var input = FocusedInputProcessor(pipeline: try pipeline())
        for character in "ghb" { _ = input.handle(.character(character), focus: focus) }
        XCTAssertTrue(input.needsFocusSnapshot(for: .character("d")))
        let other = FocusSnapshot(identity: .init(processID: 42, elementHash: 8))
        XCTAssertEqual(input.handle(.character("d"), focus: other), .passThrough)
        XCTAssertEqual(input.handle(.boundary(" "), focus: other), .passThrough)
    }

    func testUnavailableFocusCannotTriggerLiveReplacement() throws {
        var input = FocusedInputProcessor(pipeline: try pipeline())
        for character in "ghb" { _ = input.handle(.character(character), focus: focus) }
        XCTAssertEqual(input.handle(.character("d"), focus: nil), .passThrough)
    }

    func testBundledDictionariesSwitchBeforeSpaceAndContinueTypingBothDirections() throws {
        for (layout, expected) in [(KeyboardLayout.english, "привет"), (.russian, "hello")] {
            let session = try TypingSessionDriver(initialLayout: layout)
            let trace = try session.type(expected, mode: .automatic, echoSyntheticEvents: true)
            XCTAssertEqual(trace.editorText, expected)
            XCTAssertEqual(trace.automaticSelections.count, 1)
            XCTAssertLessThan(try XCTUnwrap(trace.corrections.first).replacement.count, expected.count)
        }
    }

    func testShortWordCorrectsWithPunctuationTypedAtTargetPhysicalKeys() throws {
        let normalizer = KeyboardEventNormalizer(syntheticMarker: 123)
        let cases: [(String, CGKeyCode, CGEventFlags, String)] = [
            ("/", 44, [], "."), ("?", 44, .maskShift, ","),
            ("&", 26, .maskShift, "?"), ("$", 21, .maskShift, ";"),
            ("^", 22, .maskShift, ":"), ("!", 18, .maskShift, "!"),
            (")", 29, .maskShift, ")")
        ]
        for (text, key, flags, expected) in cases {
            var input = try pipeline()
            for character in "lf" { _ = input.handle(.character(character), focusIsSafe: true) }
            let event = normalizer.normalize(.init(text: text, keyCode: key, flags: flags, marker: 0))
            XCTAssertEqual(input.handle(event, focusIsSafe: true), .replace(.init(
                deleteKeyCount: 2, replacement: "да", delimiter: expected, targetLayout: .russian
            )), text)
            XCTAssertEqual(input.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        }
    }

    func testShortEnglishWordCorrectsRussianGlyphAtEnglishPunctuationKey() throws {
        let normalizer = KeyboardEventNormalizer(syntheticMarker: 123)
        for (text, key, shifted, expected) in [("ю", 47, false, "."), ("б", 43, false, ","),
                                              (",", 44, true, "?"), ("ж", 41, false, ";"),
                                              ("Ж", 41, true, ":")] {
            var input = try pipeline(english: ["yes"])
            for character in "нуы" { _ = input.handle(.character(character), focusIsSafe: true) }
            let event = normalizer.normalize(.init(text: text, keyCode: CGKeyCode(key),
                                                   flags: shifted ? .maskShift : [], marker: 0))
            XCTAssertEqual(input.handle(event, focusIsSafe: true), .replace(.init(
                deleteKeyCount: 3, replacement: "yes", delimiter: expected, targetLayout: .english
            )), text)
        }
    }

    func testPunctuationAndBracketsSurvivePhysicalTypingWithoutManualSwitches() throws {
        let session = try TypingSessionDriver(initialLayout: .english)
        let expected = "(да!), yes? да; yes. да: yes) да yes: привет?! hello!\n"
        let trace = try session.type(expected, mode: .automatic)
        XCTAssertEqual(trace.editorText, expected, trace.firstDivergence)
    }

    func testRussianLetterAtPunctuationKeyStartsWholeWordBuffer() throws {
        let normalizer = KeyboardEventNormalizer(syntheticMarker: 123)
        var input = FocusedInputProcessor(pipeline: try pipeline())
        let first = normalizer.normalize(.init(text: "б", keyCode: 43, flags: [], marker: 0))
        _ = input.handle(first, focus: focus)
        for character in "юджет" { _ = input.handle(.character(character), focus: focus) }
        XCTAssertEqual(input.forceCorrection(focus: focus), .replace(.init(
            deleteKeyCount: 6, replacement: ",.l;tn", delimiter: "", targetLayout: .english
        )))
    }
}
