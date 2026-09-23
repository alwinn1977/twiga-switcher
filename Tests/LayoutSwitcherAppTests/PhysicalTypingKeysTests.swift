import CoreGraphics
import LayoutSwitcherCore
import XCTest

final class PhysicalTypingKeysTests: XCTestCase {
    func testCorpusHasTwentyFourMixedLinesAndFinalNewline() {
        let lines = MixedTypingCorpus.expected.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 25)
        XCTAssertEqual(String(lines.last ?? ""), "")
        XCTAssertTrue(lines.dropLast().allSatisfy { line in
            line.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
                && line.unicodeScalars.contains {
                    (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
                }
        })
        XCTAssertEqual(lines.first, "компьютер запускает Linux, затем browser показывает страницу проекта.")
        XCTAssertEqual(lines.dropLast().last, "Финальная строка содержит Node.js, компьютер, English words.")
        XCTAssertEqual(MixedTypingCorpus.expectedLinePrefixes.count, 24)
        XCTAssertEqual(MixedTypingCorpus.expectedLinePrefixes.last, MixedTypingCorpus.expected)
    }

    func testWrongLayoutPunctuationKeysHaveIndependentLiteralExpectations() {
        let cases = [
            ("компьютер", "rjvgm.nth"), ("меню", "vty."),
            ("люди", "k.lb"), ("бюджет", ",.l;tn"),
            ("любой", "k.,jq"), ("ключ", "rk.x"),
            ("мьютекс", "vm.ntrc"), ("плюс", "gk.c")
        ]
        for (word, literalRaw) in cases {
            XCTAssertEqual(
                PhysicalTypingKeys.rawKeys(for: word, intendedLayout: .russian, activeLayout: .english),
                literalRaw,
                word
            )
        }
    }

    func testTermPunctuationAndSentencePunctuationUsePhysicalPositions() {
        XCTAssertEqual(PhysicalTypingKeys.rawKeys(for: "Node.js", intendedLayout: .english, activeLayout: .english), "Node.js")
        XCTAssertEqual(PhysicalTypingKeys.rawKeys(for: ".NET", intendedLayout: .english, activeLayout: .english), ".NET")
        XCTAssertEqual(PhysicalTypingKeys.rawKeys(for: "C++", intendedLayout: .english, activeLayout: .english), "C++")
        XCTAssertEqual(PhysicalTypingKeys.render(PhysicalTypingKeys.stroke(for: ".", language: .russian)!, in: .russian), ".")
        XCTAssertEqual(PhysicalTypingKeys.render(PhysicalTypingKeys.stroke(for: ",", language: .russian)!, in: .russian), ",")
        XCTAssertEqual(PhysicalTypingKeys.render(PhysicalTypingKeys.stroke(for: ".", language: .english)!, in: .russian), "ю")
    }
}
