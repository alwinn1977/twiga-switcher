import XCTest
@testable import LayoutSwitcherCore

final class LayoutConverterTests: XCTestCase {
    private let converter = LayoutConverter()

    func testConvertsBothDirections() {
        XCTAssertEqual(
            converter.convert("ghbdtn"),
            LayoutConversion(text: "привет", targetLayout: .russian)
        )
        XCTAssertEqual(
            converter.convert("руддщ"),
            LayoutConversion(text: "hello", targetLayout: .english)
        )
    }

    func testPreservesTitleAndUppercasePerCharacter() {
        XCTAssertEqual(converter.convert("Ghbdtn")?.text, "Привет")
        XCTAssertEqual(converter.convert("GHBDTN")?.text, "ПРИВЕТ")
        XCTAssertEqual(converter.convert("Руддщ")?.text, "Hello")
        XCTAssertEqual(converter.convert("РУДДЩ")?.text, "HELLO")
    }

    func testRoundTripsEveryMappedKeyPosition() {
        let english = "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
        let russian = "ёйцукенгшщзхъфывапролджэячсмитьбю"
        XCTAssertEqual(converter.convert(english)?.text, russian)
        XCTAssertEqual(converter.convert(russian)?.text, english)
    }

    func testRejectsMixedScriptsDigitsAndEmptyInput() {
        XCTAssertNil(converter.convert("ghбdtn"))
        XCTAssertNil(converter.convert("hello2"))
        XCTAssertNil(converter.convert(""))
    }
}
