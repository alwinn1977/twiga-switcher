import XCTest
@testable import TwigaSwitcherCore

final class PhraseBufferTests: XCTestCase {
    func testRetainsDeferredPrefixAndReturnsLongestPhraseWithSpaces() throws {
        var buffer = PhraseBuffer(maxTokens: 8, maxScalars: 128)
        feed("ьфсршту", to: &buffer)
        let first = buffer.handle(.boundary(" "))
        let firstCandidate = try XCTUnwrap(first.candidates.first)
        buffer.resolve(first, disposition: .deferForPhrase(firstCandidate))

        feed("дуфктштп", to: &buffer)
        let candidates = buffer.handle(.boundary(" ")).candidates

        XCTAssertEqual(candidates.first?.text, "ьфсршту дуфктштп")
        XCTAssertEqual(candidates.first?.physicalKeyCount, 16)
        XCTAssertEqual(candidates.first?.tokenCount, 2)
        XCTAssertEqual(candidates.last?.text, "дуфктштп")
    }

    func testBackspaceCrossesProvisionalPunctuation() throws {
        var buffer = PhraseBuffer()
        feed("Node", to: &buffer)
        let period = buffer.handle(.boundary("."))
        buffer.resolve(period, disposition: .deferForPhrase(try XCTUnwrap(period.candidates.first)))
        feed("j", to: &buffer)
        _ = buffer.handle(.backspace)
        feed("js", to: &buffer)

        XCTAssertEqual(buffer.handle(.boundary(" ")).candidates.first?.text, "Node.js")
    }

    func testLeadingCommaPeriodAndDeferredSemicolonFormBudgetCandidate() throws {
        var buffer = PhraseBuffer()
        _ = buffer.handle(.boundary(","))
        _ = buffer.handle(.boundary("."))
        _ = buffer.handle(.character("l"))
        let semicolon = buffer.handle(.boundary(";"))
        let prefix = try XCTUnwrap(semicolon.candidates.first)
        buffer.resolve(semicolon, disposition: .deferForPhrase(prefix))
        for letter in "tn" { _ = buffer.handle(.character(letter)) }
        XCTAssertEqual(buffer.handle(.boundary(" ")).candidates.first?.text, ",.l;tn")
    }

    func testDeferredPeriodThenCommaFormsAnyCandidate() throws {
        var buffer = PhraseBuffer()
        _ = buffer.handle(.character("k"))
        let dot = buffer.handle(.boundary("."))
        buffer.resolve(dot, disposition: .deferForPhrase(try XCTUnwrap(dot.candidates.first)))
        let comma = buffer.handle(.boundary(","))
        buffer.resolve(comma, disposition: .deferForPhrase(try XCTUnwrap(comma.candidates.first)))
        for letter in "jq" { _ = buffer.handle(.character(letter)) }
        XCTAssertEqual(buffer.handle(.boundary(" ")).candidates.first?.text, "k.,jq")
    }

    func testIsolatedPunctuationDoesNotBecomeAWordOrRunUnbounded() {
        var comma = PhraseBuffer()
        _ = comma.handle(.boundary(","))
        XCTAssertTrue(comma.handle(.boundary(" ")).candidates.isEmpty)
        var dot = PhraseBuffer()
        _ = dot.handle(.boundary("."))
        XCTAssertTrue(dot.handle(.boundary(" ")).candidates.isEmpty)
        var run = PhraseBuffer()
        _ = run.handle(.boundary(","))
        _ = run.handle(.boundary("."))
        _ = run.handle(.boundary("."))
        _ = run.handle(.character("l"))
        XCTAssertEqual(run.handle(.boundary(" ")).candidates.first?.text, "l")
    }

    func testDeferredShorterSuffixDropsStalePrefix() throws {
        var buffer = PhraseBuffer()
        feed("alpha", to: &buffer)
        let alpha = buffer.handle(.boundary(" "))
        buffer.resolve(alpha, disposition: .deferForPhrase(try XCTUnwrap(alpha.candidates.first)))
        feed("beta", to: &buffer)
        let result = buffer.handle(.boundary(" "))
        let beta = try XCTUnwrap(result.candidates.last)
        buffer.resolve(result, disposition: .deferForPhrase(beta))
        feed("gamma", to: &buffer)

        XCTAssertEqual(buffer.handle(.boundary(" ")).candidates.first?.text, "beta gamma")
    }

    func testHardLimitsAndMixedScriptsBlockUntilBoundary() throws {
        var scalars = PhraseBuffer(maxTokens: 8, maxScalars: 128)
        feed(String(repeating: "a", count: 129), to: &scalars)
        XCTAssertTrue(scalars.handle(.boundary(" ")).candidates.isEmpty)

        var tokens = PhraseBuffer(maxTokens: 8, maxScalars: 128)
        for index in 0..<8 {
            feed("a", to: &tokens)
            let result = tokens.handle(.boundary(" "))
            tokens.resolve(result, disposition: .deferForPhrase(try XCTUnwrap(result.candidates.first)))
            XCTAssertEqual(index + 1, result.candidates.first?.tokenCount)
        }
        feed("a", to: &tokens)
        XCTAssertTrue(tokens.handle(.boundary(" ")).candidates.isEmpty)

        var mixed = PhraseBuffer()
        feed("abcд", to: &mixed)
        XCTAssertTrue(mixed.handle(.boundary(" ")).candidates.isEmpty)
        feed("новое", to: &mixed)
        XCTAssertEqual(mixed.handle(.boundary(" ")).candidates.first?.text, "новое")
    }

    private func feed(_ text: String, to buffer: inout PhraseBuffer) {
        text.forEach { _ = buffer.handle(.character($0)) }
    }
}

private extension PhraseBufferResult {
    var candidates: [BufferedCandidate] {
        guard case let .candidates(candidates, _) = self else { return [] }
        return candidates
    }
}
