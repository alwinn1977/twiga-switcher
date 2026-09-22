import XCTest
@testable import LayoutSwitcherCore

private struct SetLexicon: WordLexicon {
    let english: Set<String>; let russian: Set<String>
    func contains(_ word: String, language: Language) -> Bool {
        language == .english ? english.contains(word.lowercased()) : russian.contains(word.lowercased())
    }
}

final class LanguageDetectorTests: XCTestCase {
    func testCorrectsOnlyInvalidOriginalToValidCandidate() {
        let detector = LanguageDetector(lexicon: SetLexicon(english: ["hello"], russian: ["привет"]), allowlist: ["docker"])
        XCTAssertEqual(detector.decision(original: "ghbdtn", conversion: .init(text: "привет", targetLayout: .russian)), .correct(text: "привет", targetLayout: .russian))
    }

    func testLeavesAllowlistedValidAndAmbiguousWordsUnchanged() {
        let detector = LanguageDetector(lexicon: SetLexicon(english: ["docker", "a"], russian: ["ф"]), allowlist: ["docker"])
        XCTAssertEqual(detector.decision(original: "docker", conversion: .init(text: "вщслук", targetLayout: .russian)), .unchanged)
        XCTAssertEqual(detector.decision(original: "a", conversion: .init(text: "ф", targetLayout: .russian)), .unchanged)
        XCTAssertEqual(detector.decision(original: "zzz", conversion: .init(text: "яяя", targetLayout: .russian)), .unchanged)
    }
}
