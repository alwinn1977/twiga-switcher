import XCTest
@testable import LayoutSwitcherCore

private struct SetLexicon: FrequencyLexicon {
    let english: Set<String>; let russian: Set<String>
    func lookup(_ word: String, language: Language) -> LexiconMatch {
        let contains = language == .english
            ? english.contains(word.lowercased())
            : russian.contains(word.lowercased())
        return LexiconMatch(score: contains ? 3_000 : nil, isSubjectTerm: false, isStrictPrefix: false)
    }
}

final class LanguageDetectorTests: XCTestCase {
    func testCorrectsOnlyInvalidOriginalToValidCandidate() {
        let detector = LanguageDetector(
            lexicon: SetLexicon(english: ["hello"], russian: ["привет"]),
            rules: NoUserCorrectionRules()
        )
        XCTAssertEqual(detector.decision(original: "ghbdtn", conversion: .init(text: "привет", targetLayout: .russian)), .correct(text: "привет", targetLayout: .russian))
    }

    func testLeavesValidAmbiguousAndUnknownWordsUnchanged() {
        let detector = LanguageDetector(
            lexicon: SetLexicon(english: ["docker", "a"], russian: ["ф"]),
            rules: NoUserCorrectionRules()
        )
        XCTAssertEqual(detector.decision(original: "docker", conversion: .init(text: "вщслук", targetLayout: .russian)), .unchanged)
        XCTAssertEqual(detector.decision(original: "a", conversion: .init(text: "ф", targetLayout: .russian)), .unchanged)
        XCTAssertEqual(detector.decision(original: "zzz", conversion: .init(text: "яяя", targetLayout: .russian)), .unchanged)
    }
}
