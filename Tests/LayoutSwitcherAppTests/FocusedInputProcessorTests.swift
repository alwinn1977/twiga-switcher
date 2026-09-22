import XCTest
import CoreGraphics
import LayoutSwitcherCore
@testable import LayoutSwitcherApp

private struct ProcessorLexicon: WordLexicon {
    func contains(_ word: String, language: Language) -> Bool {
        switch language {
        case .english: return ["hello"].contains(word.lowercased())
        case .russian: return ["привет"].contains(word.lowercased())
        }
    }
}

final class FocusedInputProcessorTests: XCTestCase {
    private let normalizer = KeyboardEventNormalizer(syntheticMarker: 0x4C535743)

    private func makeProcessor() -> FocusedInputProcessor<ProcessorLexicon> {
        FocusedInputProcessor(pipeline: InputPipeline(
            converter: LayoutConverter(),
            detector: LanguageDetector(lexicon: ProcessorLexicon(), allowlist: [])
        ))
    }

    func testShiftTransitionsDoNotDiscardTitleCaseWord() {
        var processor = makeProcessor()
        let focus = FocusSnapshot(identity: .init(processID: 10, elementHash: 20))

        XCTAssertEqual(processor.handle(.character("G"), focus: focus), .passThrough)
        if let modifierEvent = normalizer.normalizeModifierChange(flags: .maskShift) {
            _ = processor.handle(modifierEvent, focus: nil)
        }
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
        if let modifierEvent = normalizer.normalizeModifierChange(flags: []) {
            _ = processor.handle(modifierEvent, focus: nil)
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
        if let modifierEvent = normalizer.normalizeModifierChange(flags: .maskCommand) {
            _ = processor.handle(modifierEvent, focus: nil)
        }
        "dtn".enumerated().forEach { index, character in
            _ = processor.handle(.character(character), focus: index == 0 ? focus : nil)
        }

        XCTAssertEqual(processor.handle(.boundary(" "), focus: focus), .passThrough)
    }
}
