import CoreGraphics
import AppKit
import LayoutSwitcherCore
import XCTest
@testable import LayoutSwitcherApp

private final class PosterInputSources: InputSourceManaging {
    func select(_ layout: KeyboardLayout) -> Bool { true }
}

final class EventPosterTests: XCTestCase {
    @MainActor
    func testManualCorrectionKeepsPreviousWordsInNativeTextView() async throws {
        let editor = NSTextView(frame: .init(x: 0, y: 0, width: 500, height: 100))
        editor.string = "Several correct words qzq"
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let poster = EventPoster(makeKeyboardEvent: { source, keyCode, down in
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = [.maskAlternate]
            if keyCode == 51 {
                var backspace: UniChar = 0x7F
                event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &backspace)
            }
            return event
        }, sendEvent: { event in
            if event.type == .keyDown, let native = NSEvent(cgEvent: event) {
                editor.keyDown(with: native)
            }
        })
        let executor = ReplacementExecutor(eventPoster: poster, inputSources: PosterInputSources())
        XCTAssertEqual(executor.execute(.init(
            deleteKeyCount: 3, replacement: "йяй", delimiter: "", targetLayout: .russian
        )), .completed)
        XCTAssertEqual(editor.string, "Several correct words йяй")
    }

    func testCorrectionPostsUnmodifiedKeysWhileHotkeyModifiersAreHeld() throws {
        for held: CGEventFlags in [[.maskControl, .maskAlternate], [.maskCommand, .maskShift], [.maskAlphaShift]] {
            var sent: [CGEvent] = []
            let poster = EventPoster(makeKeyboardEvent: { source, keyCode, down in
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
                // HID-created events can carry the modifiers still held by the user.
                event?.flags = held
                return event
            }, sendEvent: { sent.append($0) })
            let executor = ReplacementExecutor(eventPoster: poster, inputSources: PosterInputSources())
            XCTAssertEqual(executor.execute(.init(
                deleteKeyCount: 3, replacement: "йяй", delimiter: " ", targetLayout: .russian
            )), .completed)

            XCTAssertEqual(sent.count, 10)
            XCTAssertEqual(sent.filter { $0.type == .keyDown && $0.getIntegerValueField(.keyboardEventKeycode) == 51 }.count, 3)
            for event in sent {
                XCTAssertEqual(event.flags, [], "Synthetic deletion/insertion must not inherit shortcut modifiers")
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), EventPoster.syntheticMarker)
            }
            var length = 0
            var units = [UniChar](repeating: 0, count: 16)
            sent[6].keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
            XCTAssertEqual(String(utf16CodeUnits: units, count: length), "йяй")

            sent.removeAll()
            XCTAssertEqual(executor.reverse(.init(
                deleteKeyCount: 4, replacement: "qzq", delimiter: " ", targetLayout: .english
            )), .completed)
            XCTAssertEqual(sent.count, 12)
            XCTAssertTrue(sent.allSatisfy { $0.flags.isEmpty }, "Undo must also use ordinary Backspace")
        }
    }
}
