import XCTest
@testable import LayoutSwitcherCore

private struct PipelineLexicon: FrequencyLexicon {
    struct Entry: Sendable {
        let score: Int
        let subject: Bool
    }

    let entries: [Language: [String: Entry]]
    var maximumPhraseWords: Int { 3 }

    func lookup(_ text: String, language: Language) -> LexiconMatch {
        let key = TermNormalizer.normalize(text)
        let languageEntries = entries[language] ?? [:]
        let entry = languageEntries[key]
        let prefix = languageEntries.keys.contains { $0 != key && $0.hasPrefix(key) }
        return LexiconMatch(score: entry?.score, isSubjectTerm: entry?.subject ?? false, isStrictPrefix: prefix)
    }
}

private struct ForcedHelloRule: UserCorrectionRuleLookingUp {
    func disposition(source: String, candidate: String) -> UserCorrectionDisposition? {
        source == "hello" && candidate == "руддщ" ? .always : nil
    }
}

final class InputPipelineTests: XCTestCase {
    private func makePipeline(includeRussianDecoy: Bool = false) -> InputPipeline<PipelineLexicon, NoUserCorrectionRules> {
        var russianEntries: [String: PipelineLexicon.Entry] = [
            "и": .init(score: 7_400, subject: false),
            "привет": .init(score: 5_100, subject: false),
            "компьютер": .init(score: 5_000, subject: false),
            "бюджет": .init(score: 5_000, subject: false),
            "любой": .init(score: 5_000, subject: false),
            "мен": .init(score: 4_000, subject: false),
            "меню": .init(score: 5_000, subject: false),
            "сохраняет": .init(score: 5_000, subject: false),
            "хорошо": .init(score: 5_000, subject: false),
            "ёлка": .init(score: 5_000, subject: false),
            "объект": .init(score: 5_000, subject: false),
        ]
        if includeRussianDecoy {
            russianEntries["руддщю"] = .init(score: 5_000, subject: false)
        }
        return InputPipeline(
            converter: LayoutConverter(),
            detector: LanguageDetector(
                lexicon: PipelineLexicon(entries: [
                    .english: [
                        "hello": .init(score: 5_000, subject: false),
                        "linux": .init(score: 5_200, subject: true),
                        "windows": .init(score: 5_100, subject: true),
                        "windows server": .init(score: 4_900, subject: true),
                        ".net": .init(score: 3_500, subject: true),
                        "node": .init(score: 3_000, subject: true),
                        "node.js": .init(score: 4_200, subject: true),
                        "machine learning": .init(score: 4_100, subject: true),
                        "machine vision": .init(score: 4_000, subject: true),
                        "c++": .init(score: 4_000, subject: true),
                    ],
                    .russian: russianEntries,
                ]),
                rules: NoUserCorrectionRules()
            )
        )
    }

    func testSafeBoundaryBuildsReplacementPlan() {
        var pipeline = makePipeline()
        feed("ghbdtn", to: &pipeline)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian))
        )
    }

    func testRecognizesDotNetAtBufferStartAndNodeJSInsideSentence() {
        var pipeline = makePipeline()
        XCTAssertEqual(pipeline.handle(.boundary("."), focusIsSafe: true), .passThrough)
        feed("NET", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)

        feed("юТУЕ", to: &pipeline)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 4, replacement: ".NET", delimiter: " ", targetLayout: .english))
        )

        feed("hello", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        feed("тщвуюоы", to: &pipeline)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 7, replacement: "node.js", delimiter: " ", targetLayout: .english))
        )
    }

    func testCorrectNodeJSHoldsPeriodProvisionallyButSentencePeriodDoesNotLeak() {
        var pipeline = makePipeline()
        feed("Node", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary("."), focusIsSafe: true), .passThrough)
        feed("js", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)

        feed("hello", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary("."), focusIsSafe: true), .passThrough)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        feed("ghbdtn", to: &pipeline)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian))
        )
    }

    func testWrongLayoutWordsKeepDotCommaAndSemicolonUntilCompletion() {
        let cases: [(String, String, Int)] = [
            ("rjvgm.nth", "компьютер", 9),
            ("k.,jq", "любой", 5),
            (",.l;tn", "бюджет", 6)
        ]
        for (raw, expected, keyCount) in cases {
            var pipeline = makePipeline()
            for character in raw {
                let input: InputEvent = ",.;".contains(character)
                    ? .boundary(String(character)) : .character(character)
                _ = pipeline.handle(input, focusIsSafe: true)
            }
            XCTAssertEqual(
                pipeline.handle(.boundary(" "), focusIsSafe: true),
                .replace(.init(
                    deleteKeyCount: keyCount,
                    replacement: expected,
                    delimiter: " ",
                    targetLayout: .russian
                )),
                raw
            )
        }
    }

    func testFinalPhysicalDotCanBeRussianLetterRatherThanSentencePeriod() {
        var pipeline = makePipeline()
        feed("vty", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary("."), focusIsSafe: true), .passThrough)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 4, replacement: "меню", delimiter: " ", targetLayout: .russian))
        )
    }

    func testSentenceCommaAfterWrongLayoutWordRemainsPunctuation() {
        var pipeline = makePipeline()
        feed("ghbdtn", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(","), focusIsSafe: true), .passThrough)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 7, replacement: "привет", delimiter: ", ", targetLayout: .russian))
        )
    }

    func testRussianRawWordBeforeLiteralCommaConvertsWithoutTreatingCommaAsLetter() {
        var pipeline = makePipeline()
        feed("Дштгч", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(","), focusIsSafe: true), .passThrough)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 6, replacement: "Linux", delimiter: ", ", targetLayout: .english))
        )
    }

    func testWrongLayoutBracketBacktickAndClosingBracketStayInsideWords() {
        let cases: [(String, String)] = [
            ("cj[hfyztn", "сохраняет"),
            ("[jhjij", "хорошо"),
            ("`krf", "ёлка"),
            ("j,]trn", "объект")
        ]
        for (raw, expected) in cases {
            var pipeline = makePipeline()
            for character in raw {
                let input: InputEvent = character == ","
                    ? .boundary(",") : .character(character)
                _ = pipeline.handle(input, focusIsSafe: true)
            }
            XCTAssertEqual(
                pipeline.handle(.boundary(" "), focusIsSafe: true),
                .replace(.init(
                    deleteKeyCount: raw.count,
                    replacement: expected,
                    delimiter: " ",
                    targetLayout: .russian
                )),
                raw
            )
        }
    }

    func testKnownEnglishWordWithSentencePeriodBeatsPlausibleRussianConversion() {
        var pipeline = makePipeline(includeRussianDecoy: true)
        feed("hello", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary("."), focusIsSafe: true), .passThrough)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
    }

    func testExplicitAlwaysRuleStillAppliesBeforeSentencePeriod() {
        var pipeline = InputPipeline(
            converter: LayoutConverter(),
            detector: LanguageDetector(
                lexicon: PipelineLexicon(entries: [
                    .english: ["hello": .init(score: 5_000, subject: false)]
                ]),
                rules: ForcedHelloRule()
            )
        )
        "hello".forEach { _ = pipeline.handle(.character($0), focusIsSafe: true) }
        XCTAssertEqual(pipeline.handle(.boundary("."), focusIsSafe: true), .passThrough)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 6, replacement: "руддщ", delimiter: ". ", targetLayout: .russian))
        )
    }

    func testCorrectPunctuationTermsAndSentenceMarksStayLiteral() {
        for word in ["Node.js", ".NET", "C++"] {
            var pipeline = makePipeline()
            for character in word {
                let input: InputEvent = character == "."
                    ? .boundary(".") : .character(character)
                _ = pipeline.handle(input, focusIsSafe: true)
            }
            XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough, word)
        }
        var sentence = makePipeline()
        feed("hello", to: &sentence)
        XCTAssertEqual(sentence.handle(.boundary("."), focusIsSafe: true), .passThrough)
        XCTAssertEqual(sentence.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        feed("ghbdtn", to: &sentence)
        XCTAssertEqual(
            sentence.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian))
        )
    }

    func testDeferredTwoWordPhraseIsReplacedAsOnePlan() {
        var pipeline = makePipeline()
        feed("ьфсршту", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        feed("дуфктштп", to: &pipeline)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 16, replacement: "machine learning", delimiter: " ", targetLayout: .english))
        )
    }

    func testDeferredTwoWordPhraseSurvivesTerminalPunctuation() {
        for punctuation in [",", ".", ";"] {
            var pipeline = makePipeline()
            feed("ьфсршту", to: &pipeline)
            XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
            feed("дуфктштп", to: &pipeline)
            XCTAssertEqual(pipeline.handle(.boundary(punctuation), focusIsSafe: true), .passThrough)
            XCTAssertEqual(
                pipeline.handle(.boundary(" "), focusIsSafe: true),
                .replace(.init(
                    deleteKeyCount: 17,
                    replacement: "machine learning",
                    delimiter: punctuation + " ",
                    targetLayout: .english
                )),
                punctuation
            )
        }
    }

    func testUsesShorterSuffixWhenLongerPhraseMisses() {
        var pipeline = makePipeline()
        feed("ьфсршту", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        feed("юТУЕ", to: &pipeline)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 4, replacement: ".NET", delimiter: " ", targetLayout: .english))
        )
    }

    func testUnsafeFocusNeverCreatesReplacement() {
        var pipeline = makePipeline()
        feed("ghbdtn", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: false), .passThrough)
    }

    func testSyntheticDoesNotMutateBufferedText() {
        var pipeline = makePipeline()
        feed("ghbdtn", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.synthetic, focusIsSafe: true), .passThrough)
        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian))
        )
    }

    func testRecognizedSourceWithMissingCandidateDoesNotOfferReverseManualRule() {
        var pipeline = makePipeline()
        feed("linux", to: &pipeline)

        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        XCTAssertNil(pipeline.latestDecisionPair)
    }

    func testUnknownPairRemainsAvailableForManualLearning() {
        var pipeline = makePipeline()
        feed("qzq", to: &pipeline)

        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        XCTAssertEqual(
            pipeline.latestDecisionPair,
            CorrectionPair(source: "qzq", candidate: "йяй")
        )
    }

    func testExactReportedContextStillCorrectsRussianLinuxTyping() {
        var pipeline = makePipeline()
        feed("windows", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        XCTAssertNil(pipeline.latestDecisionPair)
        feed("и", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)
        feed("дштгч", to: &pipeline)

        XCTAssertEqual(
            pipeline.handle(.boundary(" "), focusIsSafe: true),
            .replace(.init(
                deleteKeyCount: 5,
                replacement: "linux",
                delimiter: " ",
                targetLayout: .english
            ))
        )
        XCTAssertEqual(
            pipeline.latestDecisionPair,
            CorrectionPair(source: "дштгч", candidate: "linux")
        )
    }

    func testResetClearsStaleManualCorrectionPair() {
        var pipeline = makePipeline()
        feed("qzq", to: &pipeline)
        _ = pipeline.handle(.boundary(" "), focusIsSafe: true)
        XCTAssertNotNil(pipeline.latestDecisionPair)

        pipeline.reset()

        XCTAssertNil(pipeline.latestDecisionPair)
    }

    func testForceCorrectsCurrentWordWithoutDelimiter() {
        var pipeline = makePipeline()
        feed("дштгч", to: &pipeline)

        XCTAssertEqual(
            pipeline.forceCorrection(focusIsSafe: true),
            .replace(.init(deleteKeyCount: 5, replacement: "linux", delimiter: "", targetLayout: .english))
        )
        XCTAssertEqual(pipeline.latestDecisionPair, .init(source: "дштгч", candidate: "linux"))
    }

    func testForcePreservesTerminalCommaAsPunctuation() {
        var pipeline = makePipeline()
        feed("qzq", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(","), focusIsSafe: true), .passThrough)

        XCTAssertEqual(
            pipeline.forceCorrection(focusIsSafe: true),
            .replace(.init(deleteKeyCount: 4, replacement: "йяй", delimiter: ",", targetLayout: .russian))
        )
    }

    func testForceCanCorrectRecognizedWordEndingInPhysicalDot() {
        var pipeline = makePipeline()
        feed("vty", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary("."), focusIsSafe: true), .passThrough)

        XCTAssertEqual(
            pipeline.forceCorrection(focusIsSafe: true),
            .replace(.init(deleteKeyCount: 4, replacement: "меню", delimiter: "", targetLayout: .russian))
        )
    }

    func testForceCorrectsLastCompletedWordAndKeepsSpace() {
        var pipeline = makePipeline()
        feed("qzq", to: &pipeline)
        XCTAssertEqual(pipeline.handle(.boundary(" "), focusIsSafe: true), .passThrough)

        XCTAssertEqual(
            pipeline.forceCorrection(focusIsSafe: true),
            .replace(.init(deleteKeyCount: 4, replacement: "йяй", delimiter: " ", targetLayout: .russian))
        )
        XCTAssertEqual(pipeline.forceCorrection(focusIsSafe: true), .passThrough)
    }

    func testForceDoesNotUseStaleWordAfterNewInputOrUnsafeFocus() {
        var pipeline = makePipeline()
        feed("qzq", to: &pipeline)
        _ = pipeline.handle(.boundary(" "), focusIsSafe: true)
        XCTAssertEqual(pipeline.forceCorrection(focusIsSafe: false), .passThrough)
        _ = pipeline.handle(.character("a"), focusIsSafe: true)
        XCTAssertEqual(
            pipeline.forceCorrection(focusIsSafe: true),
            .replace(.init(deleteKeyCount: 1, replacement: "ф", delimiter: "", targetLayout: .russian))
        )
    }

    private func feed(
        _ text: String,
        to pipeline: inout InputPipeline<PipelineLexicon, NoUserCorrectionRules>
    ) {
        text.forEach { _ = pipeline.handle(.character($0), focusIsSafe: true) }
    }
}
