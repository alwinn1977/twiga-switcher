import XCTest
import CoreGraphics
import LayoutSwitcherCore
@testable import LayoutSwitcherApp

private struct ProcessorLexicon: FrequencyLexicon {
    func lookup(_ text: String, language: Language) -> LexiconMatch {
        let key = TermNormalizer.normalize(text)
        let entries: [String: Int] = language == .english
            ? ["hello": 5_000, ".net": 4_200, "machine learning": 4_100]
            : ["привет": 5_100, "бюджет": 5_000]
        return LexiconMatch(
            score: entries[key],
            isSubjectTerm: key == "machine learning",
            isStrictPrefix: entries.keys.contains { $0 != key && $0.hasPrefix(key) }
        )
    }
}

final class FocusedInputProcessorTests: XCTestCase {
    private let normalizer = KeyboardEventNormalizer(syntheticMarker: 0x4C535743)

    private func makeProcessor() -> FocusedInputProcessor<ProcessorLexicon, NoUserCorrectionRules> {
        FocusedInputProcessor(pipeline: InputPipeline(
            converter: LayoutConverter(),
            detector: LanguageDetector(lexicon: ProcessorLexicon(), rules: NoUserCorrectionRules())
        ))
    }

    func testForceCanReverseAutomaticBoundaryCorrection() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))
        for character in "ghbdtn" { _ = processor.handle(.character(character), focus: focus) }
        _ = processor.handle(.boundary(" "), focus: focus)
        XCTAssertEqual(processor.forceCorrection(focus: focus), .replace(.init(
            deleteKeyCount: 7, replacement: "ghbdtn", delimiter: " ", targetLayout: .english
        )))
    }

    func testForceCanBeRepeatedWithoutRetypingWord() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))
        for character in "qzq" { _ = processor.handle(.character(character), focus: focus) }
        _ = processor.forceCorrection(focus: focus)
        XCTAssertEqual(processor.forceCorrection(focus: focus), .replace(.init(
            deleteKeyCount: 3, replacement: "qzq", delimiter: "", targetLayout: .english
        )))
    }

    func testBlockedWordDoesNotDisableFollowingWords() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))
        for character in "abc🙂" { _ = processor.handle(.character(character), focus: focus) }
        _ = processor.handle(.boundary(" "), focus: focus)
        for character in "ghbdtn" { _ = processor.handle(.character(character), focus: focus) }
        XCTAssertEqual(processor.handle(.boundary(" "), focus: focus), .replace(.init(
            deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian
        )))
    }

    func testShiftTransitionsDoNotDiscardTitleCaseWord() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))

        XCTAssertEqual(processor.handle(.character("G"), focus: focus), .passThrough)
        "hbdtn".forEach { XCTAssertEqual(processor.handle(.character($0), focus: nil), .passThrough) }

        XCTAssertEqual(
            processor.handle(.boundary(" "), focus: focus),
            .replace(.init(deleteKeyCount: 6, replacement: "Привет", delimiter: " ", targetLayout: .russian))
        )
    }

    func testShiftReleaseDoesNotDiscardUppercaseWord() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))

        "GHBDTN".enumerated().forEach { index, character in
            _ = processor.handle(.character(character), focus: index == 0 ? focus : nil)
        }

        XCTAssertEqual(
            processor.handle(.boundary(" "), focus: focus),
            .replace(.init(deleteKeyCount: 6, replacement: "ПРИВЕТ", delimiter: " ", targetLayout: .russian))
        )
    }

    func testSafeFocusChangeCannotDeleteTextFromAnotherField() {
        var processor = makeProcessor()
        let first = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))
        let second = FocusSnapshot(identity: .init(processID: 10, elementHash: 21))

        XCTAssertEqual(processor.handle(.character("g"), focus: first), .passThrough)
        "hbdtn".forEach { _ = processor.handle(.character($0), focus: nil) }

        XCTAssertEqual(processor.handle(.boundary(" "), focus: second), .passThrough)
    }

    func testTapDisableClearsPotentiallyStaleText() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))

        "ghb".enumerated().forEach { index, character in
            _ = processor.handle(.character(character), focus: index == 0 ? focus : nil)
        }
        processor.reset()
        "dtn".enumerated().forEach { index, character in
            _ = processor.handle(.character(character), focus: index == 0 ? focus : nil)
        }

        XCTAssertEqual(processor.handle(.boundary(" "), focus: focus), .passThrough)
    }

    func testCommandModifierClearsPotentiallyStaleText() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))

        "ghb".enumerated().forEach { index, character in
            _ = processor.handle(.character(character), focus: index == 0 ? focus : nil)
        }
        _ = processor.handle(
            normalizer.normalize(.init(text: "c", keyCode: 8, flags: [.maskCommand], marker: 0)),
            focus: nil
        )
        "dtn".enumerated().forEach { index, character in
            _ = processor.handle(.character(character), focus: index == 0 ? focus : nil)
        }

        XCTAssertEqual(processor.handle(.boundary(" "), focus: focus), .passThrough)
    }

    func testDeferredPhrasePreservesFocusIdentityAcrossSpace() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))

        "ьфсршту".enumerated().forEach { index, character in
            _ = processor.handle(.character(character), focus: index == 0 ? focus : nil)
        }
        XCTAssertEqual(processor.handle(.boundary(" "), focus: focus), .passThrough)
        XCTAssertFalse(processor.needsFocusSnapshot(for: .character("д")))
        "дуфктштп".forEach { _ = processor.handle(.character($0), focus: nil) }

        XCTAssertEqual(
            processor.handle(.boundary(" "), focus: focus),
            .replace(.init(
                deleteKeyCount: 16,
                replacement: "machine learning",
                delimiter: " ",
                targetLayout: .english
            ))
        )
    }

    func testLeadingPeriodCanStartTechnicalTermWithoutLosingFocus() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))

        XCTAssertEqual(processor.handle(.boundary("."), focus: focus), .passThrough)
        "NET".forEach { _ = processor.handle(.character($0), focus: nil) }
        XCTAssertEqual(processor.handle(.boundary(" "), focus: focus), .passThrough)
    }

    func testLeadingCommaAndDotKeepFocusForWrongLayoutBudget() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))

        XCTAssertEqual(processor.handle(.boundary(","), focus: focus), .passThrough)
        XCTAssertEqual(processor.handle(.boundary("."), focus: focus), .passThrough)
        _ = processor.handle(.character("l"), focus: nil)
        XCTAssertEqual(processor.handle(.boundary(";"), focus: focus), .passThrough)
        "tn".forEach { _ = processor.handle(.character($0), focus: nil) }
        XCTAssertEqual(
            processor.handle(.boundary(" "), focus: focus),
            .replace(.init(deleteKeyCount: 6, replacement: "бюджет", delimiter: " ", targetLayout: .russian))
        )
    }

    func testForceCorrectionRequiresSameEditableField() {
        var processor = makeProcessor()
        let first = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))
        let second = FocusSnapshot(identity: .init(processID: 10, elementHash: 21))
        "ghbdtn".enumerated().forEach { index, character in
            _ = processor.handle(.character(character), focus: index == 0 ? first : nil)
        }

        XCTAssertEqual(processor.forceCorrection(focus: second), .passThrough)
        XCTAssertEqual(processor.forceCorrection(focus: first), .passThrough)
    }

    func testForceCorrectionAfterSpaceUsesLastWordInSameField() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))
        "qzq".enumerated().forEach { index, character in
            _ = processor.handle(.character(character), focus: index == 0 ? focus : nil)
        }
        XCTAssertEqual(processor.handle(.boundary(" "), focus: focus), .passThrough)

        XCTAssertEqual(
            processor.forceCorrection(focus: focus),
            .replace(.init(deleteKeyCount: 4, replacement: "йяй", delimiter: " ", targetLayout: .russian))
        )
    }
}
