import XCTest
@testable import LayoutSwitcherCore

final class TermNormalizerTests: XCTestCase {
    func testNormalizesCaseWhitespaceAndCurlyApostropheWithoutRemovingAccents() {
        XCTAssertEqual(TermNormalizer.normalize("  NODE.\u{2019}JS  SDK "), "node.'js sdk")
        XCTAssertEqual(TermNormalizer.normalize("\u{201C}Quoted\u{201D}"), "\"quoted\"")
        XCTAssertEqual(TermNormalizer.normalize("Ёлка"), "ёлка")
        XCTAssertNotEqual(TermNormalizer.normalize("café"), "cafe")
    }
}
