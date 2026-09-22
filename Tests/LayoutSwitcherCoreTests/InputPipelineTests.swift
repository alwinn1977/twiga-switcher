import XCTest
@testable import LayoutSwitcherCore

private struct PipelineLexicon: WordLexicon {
    let english: Set<String>; let russian: Set<String>
    func contains(_ word: String, language: Language) -> Bool { language == .english ? english.contains(word.lowercased()) : russian.contains(word.lowercased()) }
}

final class InputPipelineTests: XCTestCase {
    private func makePipeline() -> InputPipeline<PipelineLexicon, NoUserCorrectionRules> {
        InputPipeline(
            converter: LayoutConverter(),
            detector: LanguageDetector(
                lexicon: PipelineLexicon(english: ["hello"], russian: ["привет"]),
                rules: NoUserCorrectionRules()
            )
        )
    }
    func testSafeBoundaryBuildsReplacementPlan() {
        var pipeline = makePipeline(); "ghbdtn".forEach { _ = pipeline.handle(.character($0), focusIsSafe: true) }
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .replace(.init(deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian)))
    }
    func testUnsafeFocusNeverCreatesReplacement() {
        var pipeline = makePipeline(); "ghbdtn".forEach { _ = pipeline.handle(.character($0), focusIsSafe: false) }
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: false), .passThrough)
    }
    func testSyntheticDoesNotMutateBufferedText() {
        var pipeline = makePipeline(); "ghbdtn".forEach { _ = pipeline.handle(.character($0), focusIsSafe: true) }
        XCTAssertEqual(pipeline.handle(.synthetic, focusIsSafe: true), .passThrough)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .replace(.init(deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian)))
    }
}
