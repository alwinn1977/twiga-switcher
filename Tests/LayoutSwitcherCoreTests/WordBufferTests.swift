import XCTest
@testable import LayoutSwitcherCore

final class WordBufferTests: XCTestCase {
    func testBoundaryReturnsWordAndClearsBuffer() {
        var buffer = WordBuffer()
        "ghbdtn".forEach { _ = buffer.handle(.character($0)) }
        XCTAssertEqual(
            buffer.handle(.boundary(" ")),
            .completed(BufferedWord(text: "ghbdtn", physicalKeyCount: 6), delimiter: " ")
        )
        XCTAssertEqual(buffer.handle(.boundary(" ")), .emptyBoundary(" "))
    }

    func testBackspaceRemovesLastCapturedKey() {
        var buffer = WordBuffer()
        "ghbdto".forEach { _ = buffer.handle(.character($0)) }
        _ = buffer.handle(.backspace)
        XCTAssertEqual(
            buffer.handle(.boundary(".")),
            .completed(BufferedWord(text: "ghbdt", physicalKeyCount: 5), delimiter: ".")
        )
    }

    func testMixedScriptBlocksSuffixUntilBoundary() {
        var buffer = WordBuffer()
        "ghбdtn".forEach { _ = buffer.handle(.character($0)) }
        XCTAssertEqual(buffer.handle(.boundary(" ")), .blockedBoundary(" "))
        "ghbdtn".forEach { _ = buffer.handle(.character($0)) }
        XCTAssertEqual(
            buffer.handle(.boundary(" ")),
            .completed(BufferedWord(text: "ghbdtn", physicalKeyCount: 6), delimiter: " ")
        )
    }

    func testDigitEmojiAndResetNeverCompleteOldText() {
        var buffer = WordBuffer()
        "gh2dtn".forEach { _ = buffer.handle(.character($0)) }
        XCTAssertEqual(buffer.handle(.boundary(" ")), .blockedBoundary(" "))
        "gh🙂dtn".forEach { _ = buffer.handle(.character($0)) }
        XCTAssertEqual(buffer.handle(.boundary(" ")), .blockedBoundary(" "))
        "gh#dtn".forEach { _ = buffer.handle(.character($0)) }
        XCTAssertEqual(buffer.handle(.boundary(" ")), .blockedBoundary(" "))
        "ghbdtn".forEach { _ = buffer.handle(.character($0)) }
        XCTAssertEqual(buffer.handle(.reset), .cleared)
        XCTAssertEqual(buffer.handle(.boundary(" ")), .emptyBoundary(" "))
    }
}
