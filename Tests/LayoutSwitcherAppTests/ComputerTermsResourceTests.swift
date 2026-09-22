import LayoutSwitcherCore
import LayoutSwitcherLexicon
import XCTest

final class ComputerTermsResourceTests: XCTestCase {
    func testComputerTermsPackCoversRequiredWordsPhrasesAndPunctuation() throws {
        let pack = try BundledLexiconResources.loadComputerTerms()

        for term in ["kubernetes", "typescript", "node.js", ".net", "c++", "postgresql"] {
            XCTAssertTrue(pack.lookup(term, language: .english).isSubjectTerm, term)
        }
        for term in ["машинное обучение", "база данных"] {
            XCTAssertTrue(pack.lookup(term, language: .russian).isSubjectTerm, term)
        }
        XCTAssertGreaterThanOrEqual(pack.maximumPhraseWords, 2)
    }
}
