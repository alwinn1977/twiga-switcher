import CoreGraphics
import XCTest
import TwigaSwitcherCore
@testable import TwigaSwitcherApp

final class KeyboardEventNormalizerTests: XCTestCase {
    func testNormalizerMapsTextBoundariesModifiersAndMarker() {
        let normalizer = KeyboardEventNormalizer(syntheticMarker: 0x4C535743)
        XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [], marker: 0)), .character("g"))
        XCTAssertEqual(normalizer.normalize(.init(text: " ", keyCode: 49, flags: [], marker: 0)), .boundary(" "))
        XCTAssertEqual(normalizer.normalize(.init(text: "\n", keyCode: 36, flags: [], marker: 0)), .boundary("\n"))
        XCTAssertEqual(normalizer.normalize(.init(text: ".", keyCode: 47, flags: [], marker: 0)), .boundary("."))
        XCTAssertEqual(normalizer.normalize(.init(text: ",", keyCode: 43, flags: [], marker: 0)), .boundary(","))
        XCTAssertEqual(normalizer.normalize(.init(text: ";", keyCode: 41, flags: [], marker: 0)), .boundary(";"))
        XCTAssertEqual(normalizer.normalize(.init(text: "+", keyCode: 24, flags: [.maskShift], marker: 0)), .character("+"))
        XCTAssertEqual(normalizer.normalize(.init(text: "", keyCode: 51, flags: [], marker: 0)), .backspace)
        XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [.maskCommand], marker: 0)), .reset)
        XCTAssertEqual(normalizer.normalize(.init(text: "z", keyCode: 6, flags: [.maskCommand], marker: 0)), .reset)
        XCTAssertEqual(normalizer.normalize(.init(text: "z", keyCode: 6, flags: [.maskCommand, .maskShift], marker: 0)), .reset)
        XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [], marker: 0x4C535743)), .synthetic)
    }

    func testNativeReturnAndKeypadEnterAreBoundaries() {
        let normalizer = KeyboardEventNormalizer(syntheticMarker: 0x4C535743)
        XCTAssertEqual(normalizer.normalize(.init(text: "\r", keyCode: 36, flags: [], marker: 0)), .boundary("\n"))
        XCTAssertEqual(normalizer.normalize(.init(text: "\u{3}", keyCode: 76, flags: [], marker: 0)), .boundary("\n"))
    }

}
