import CoreGraphics
import XCTest
import LayoutSwitcherCore
@testable import LayoutSwitcherApp

final class KeyboardEventNormalizerTests: XCTestCase {
    func testNormalizerMapsTextBoundariesModifiersAndMarker() {
        let normalizer = KeyboardEventNormalizer(syntheticMarker: 0x4C535743)
        XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [], marker: 0)), .character("g"))
        XCTAssertEqual(normalizer.normalize(.init(text: " ", keyCode: 49, flags: [], marker: 0)), .boundary(" "))
        XCTAssertEqual(normalizer.normalize(.init(text: "\n", keyCode: 36, flags: [], marker: 0)), .boundary("\n"))
        XCTAssertEqual(normalizer.normalize(.init(text: ".", keyCode: 47, flags: [], marker: 0)), .boundary("."))
        XCTAssertEqual(normalizer.normalize(.init(text: "", keyCode: 51, flags: [], marker: 0)), .backspace)
        XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [.maskCommand], marker: 0)), .reset)
        XCTAssertEqual(normalizer.normalize(.init(text: "g", keyCode: 5, flags: [], marker: 0x4C535743)), .synthetic)
    }
}
