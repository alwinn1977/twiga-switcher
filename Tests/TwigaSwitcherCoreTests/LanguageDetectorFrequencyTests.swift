import XCTest
@testable import TwigaSwitcherCore

private struct FixtureLexiconEntry: Sendable {
    let text: String
    let language: Language
    let match: LexiconMatch
}

private struct FixtureFrequencyLexicon: FrequencyLexicon {
    let entries: [FixtureLexiconEntry]

    func lookup(_ text: String, language: Language) -> LexiconMatch {
        entries.first { $0.text == text && $0.language == language }?.match ?? .missing
    }
}

private struct FixtureRules: UserCorrectionRuleLookingUp {
    let dispositionValue: UserCorrectionDisposition?

    func disposition(source: String, candidate: String) -> UserCorrectionDisposition? {
        dispositionValue
    }
}

final class LanguageDetectorFrequencyTests: XCTestCase {
    func testLowercaseSingleLetterUsesFrequencyDespiteInitialismPrefixes() {
        let detector = shortWordDetector()
        XCTAssertEqual(
            detector.decision(original: "b", conversion: .init(text: "и", targetLayout: .russian)),
            .correct(text: "и", targetLayout: .russian)
        )
        XCTAssertEqual(
            detector.decision(original: "и", conversion: .init(text: "b", targetLayout: .english)),
            .unchanged
        )
    }

    func testLowercaseSingleLetterRespectsNeverRule() {
        let detector = shortWordDetector(rules: ShortWordNeverRule())
        XCTAssertEqual(
            detector.decision(original: "b", conversion: .init(text: "и", targetLayout: .russian)),
            .unchanged
        )
    }

    func testRepeatedUppercaseInitialsKeepWaitingForContext() {
        let detector = shortWordDetector()
        XCTAssertEqual(
            detector.decision(original: "B B", conversion: .init(text: "И И", targetLayout: .russian)),
            .deferred
        )
    }

    func testSingleLetterPhraseUsesFollowingWordWithoutDictionaryPhraseEntry() {
        let detector = shortWordDetector()
        XCTAssertEqual(
            detector.decision(original: "B ghbdtn", conversion: .init(text: "И привет", targetLayout: .russian)),
            .correct(text: "И привет", targetLayout: .russian)
        )
        XCTAssertEqual(
            detector.decision(original: "B", conversion: .init(text: "И", targetLayout: .russian)),
            .deferred
        )
    }

    func testSingleLetterPhraseDoesNotConvertRecognizedOrUnknownFollowingWord() {
        let detector = shortWordDetector()
        for (source, candidate) in [("B hello", "И руддщ"), ("B qzq", "И йяй")] {
            XCTAssertEqual(
                detector.decision(original: source, conversion: .init(text: candidate, targetLayout: .russian)),
                .unchanged
            )
        }
    }

    func testSingleLetterPhraseRespectsPerWordNeverRule() {
        let detector = shortWordDetector(rules: ShortWordNeverRule())
        XCTAssertEqual(
            detector.decision(original: "B ghbdtn", conversion: .init(text: "И привет", targetLayout: .russian)),
            .unchanged
        )
    }

    private func shortWordDetector<Rules: UserCorrectionRuleLookingUp>(
        rules: Rules = NoUserCorrectionRules()
    ) -> LanguageDetector<FixtureFrequencyLexicon, Rules> {
        LanguageDetector(lexicon: FixtureFrequencyLexicon(entries: [
            .init(text: "b", language: .english, match: .init(score: 5_350, isSubjectTerm: false, isStrictPrefix: true)),
            .init(text: "и", language: .russian, match: .init(score: 7_470, isSubjectTerm: false, isStrictPrefix: true)),
            .init(text: "привет", language: .russian, match: .init(score: 5_100, isSubjectTerm: false, isStrictPrefix: false)),
            .init(text: "hello", language: .english, match: .init(score: 5_100, isSubjectTerm: false, isStrictPrefix: false))
        ]), rules: rules)
    }

    func testFrequencyPolicyUsesThresholdAndAmbiguityMargin() {
        assertDecision(
            original: "ghbdtn", originalScore: nil,
            candidate: "привет", candidateScore: 2_500,
            expected: .correct(text: "привет", targetLayout: .russian)
        )
        assertDecision(
            original: "a", originalScore: 5_000,
            candidate: "ф", candidateScore: 5_999,
            expected: .unchanged
        )
        assertDecision(
            original: "a", originalScore: 5_000,
            candidate: "ф", candidateScore: 6_000,
            expected: .correct(text: "ф", targetLayout: .russian)
        )
        assertDecision(
            original: "zzz", originalScore: nil,
            candidate: "яяя", candidateScore: 2_499,
            expected: .unchanged
        )
    }

    func testSubjectBoostRaisesCandidateToMinimumScore() {
        assertDecision(
            original: "тщвуоы", originalScore: nil,
            candidate: "node.js", candidateScore: 1_000,
            candidateIsSubjectTerm: true,
            expected: .correct(text: "node.js", targetLayout: .english)
        )
    }

    func testUserRuleTakesPriorityOverLexiconScores() {
        assertDecision(
            original: "node.js", originalScore: 1_800,
            candidate: "тщвуоы", candidateScore: 7_000,
            rule: .never,
            expected: .unchanged
        )
        assertDecision(
            original: "custom", originalScore: 7_000,
            candidate: "сгыещь", candidateScore: nil,
            rule: .always,
            expected: .correct(text: "сгыещь", targetLayout: .russian)
        )
    }

    func testStrictPhrasePrefixDefersInsteadOfCorrectingShorterSuffix() {
        let lexicon = FixtureFrequencyLexicon(entries: [
            .init(
                text: "machine", language: .english,
                match: .init(score: 4_000, isSubjectTerm: true, isStrictPrefix: true)
            )
        ])
        let detector = LanguageDetector(lexicon: lexicon, rules: NoUserCorrectionRules())

        XCTAssertEqual(
            detector.decision(
                original: "ьфсршту",
                conversion: .init(text: "machine", targetLayout: .english)
            ),
            .deferred
        )
    }

    private func assertDecision(
        original: String,
        originalScore: Int?,
        candidate: String,
        candidateScore: Int?,
        candidateIsSubjectTerm: Bool = false,
        rule: UserCorrectionDisposition? = nil,
        expected: CorrectionDecision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let targetLayout: KeyboardLayout = candidate.unicodeScalars.contains { (0x430...0x44F).contains($0.value) }
            ? .russian
            : .english
        let originalLanguage: Language = targetLayout == .russian ? .english : .russian
        let targetLanguage: Language = targetLayout == .russian ? .russian : .english
        let lexicon = FixtureFrequencyLexicon(entries: [
            .init(
                text: TermNormalizer.normalize(original), language: originalLanguage,
                match: .init(score: originalScore, isSubjectTerm: false, isStrictPrefix: false)
            ),
            .init(
                text: TermNormalizer.normalize(candidate), language: targetLanguage,
                match: .init(
                    score: candidateScore,
                    isSubjectTerm: candidateIsSubjectTerm,
                    isStrictPrefix: false
                )
            )
        ])
        let detector = LanguageDetector(
            lexicon: lexicon,
            rules: FixtureRules(dispositionValue: rule)
        )

        XCTAssertEqual(
            detector.decision(
                original: original,
                conversion: .init(text: candidate, targetLayout: targetLayout)
            ),
            expected,
            file: file,
            line: line
        )
    }
}

private struct ShortWordNeverRule: UserCorrectionRuleLookingUp {
    func disposition(source: String, candidate: String) -> UserCorrectionDisposition? {
        source == "b" && candidate == "и" ? .never : nil
    }
}
