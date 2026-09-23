import CoreGraphics
import LayoutSwitcherCore
@testable import LayoutSwitcherApp
import XCTest

private struct FixedFocus: FocusSnapshotProviding {
    let value = FocusSnapshot(identity: .init(processID: 42, elementHash: 7))
    func snapshot() -> FocusSnapshot? { value }
}

private final class RecordingPoster: EventPosting {
    var isAvailable = true
    var backspaces: [Int] = []
    var unicode: [String] = []
    func postBackspaces(count: Int) -> Bool { backspaces.append(count); return true }
    func postUnicode(_ text: String) -> Bool { unicode.append(text); return true }
}

private final class RecordingInputSources: InputSourceManaging {
    var selected: [KeyboardLayout] = []
    func select(_ layout: KeyboardLayout) -> Bool { selected.append(layout); return true }
}

private final class RecordingSound: LayoutSwitchSoundPlaying {
    var count = 0
    func play() { count += 1 }
}

final class KeyboardMonitorHotkeyTests: XCTestCase {
    func testForceShortcutCorrectsWordAndOnlyThenOffersManualRule() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        var published: [CorrectionPair?] = []
        fixture.monitor.onLatestDecision = { published.append($0) }

        for character in "qzq" { send(String(character), to: fixture.monitor) }
        send(" ", keyCode: 49, to: fixture.monitor)
        XCTAssertFalse(published.contains { $0 != nil })

        XCTAssertFalse(send("", keyCode: 37, flags: [.maskControl, .maskAlternate], to: fixture.monitor))

        XCTAssertEqual(fixture.poster.backspaces, [4])
        XCTAssertEqual(fixture.poster.unicode, ["йяй", " "])
        XCTAssertEqual(fixture.sources.selected, [.russian])
        XCTAssertEqual(published.last!, .init(source: "qzq", candidate: "йяй"))
        XCTAssertEqual(fixture.sound.count, 1)

        let mouseSource = CGEventSource(stateID: .hidSystemState)!
        let mouse = CGEvent(
            mouseEventSource: mouseSource,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: 1, y: 1),
            mouseButton: .left
        )!
        _ = fixture.monitor.handle(type: .leftMouseDown, event: mouse)
        XCTAssertEqual(published.last!, .init(source: "qzq", candidate: "йяй"))
    }

    func testDedicatedUndoSurvivesModifierPressAndLearnsNeverRule() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        var published: [CorrectionPair?] = []
        fixture.monitor.onLatestDecision = { published.append($0) }

        for character in "ghbdtn" { send(String(character), to: fixture.monitor) }
        send(" ", keyCode: 49, to: fixture.monitor)
        XCTAssertEqual(fixture.poster.unicode, ["привет", " "])
        XCTAssertFalse(published.contains { $0 != nil })

        sendModifier([.maskControl], to: fixture.monitor)
        sendModifier([.maskControl, .maskAlternate], to: fixture.monitor)
        XCTAssertFalse(send("", keyCode: 6, flags: [.maskControl, .maskAlternate], to: fixture.monitor))

        XCTAssertEqual(fixture.poster.backspaces, [6, 7])
        XCTAssertEqual(Array(fixture.poster.unicode.suffix(2)), ["ghbdtn", " "])
        XCTAssertEqual(fixture.sources.selected, [.russian, .english])
        XCTAssertEqual(fixture.rules.disposition(source: "ghbdtn", candidate: "привет"), .never)
        XCTAssertEqual(fixture.sound.count, 2)
    }

    func testCommandZRemainsAvailableToTextEditAfterAutomaticCorrection() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        for character in "ghbdtn" { send(String(character), to: fixture.monitor) }
        send(" ", keyCode: 49, to: fixture.monitor)

        XCTAssertTrue(send("z", keyCode: 6, flags: [.maskCommand], to: fixture.monitor))

        XCTAssertEqual(fixture.poster.backspaces, [6])
        XCTAssertNil(fixture.rules.disposition(source: "ghbdtn", candidate: "привет"))
    }

    func testUndoDoesNotReverseStaleCorrectionAfterAnotherBoundary() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        for character in "ghbdtn" { send(String(character), to: fixture.monitor) }
        send(" ", keyCode: 49, to: fixture.monitor)
        send(" ", keyCode: 49, to: fixture.monitor)

        XCTAssertTrue(send("", keyCode: 6, flags: [.maskControl, .maskAlternate], to: fixture.monitor))
        XCTAssertEqual(fixture.poster.backspaces, [6])
        XCTAssertNil(fixture.rules.disposition(source: "ghbdtn", candidate: "привет"))
    }

    func testUndoDoesNotReverseStaleCorrectionAfterBackspace() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        for character in "ghbdtn" { send(String(character), to: fixture.monitor) }
        send(" ", keyCode: 49, to: fixture.monitor)
        send("", keyCode: 51, to: fixture.monitor)

        XCTAssertTrue(send("", keyCode: 6, flags: [.maskControl, .maskAlternate], to: fixture.monitor))
        XCTAssertEqual(fixture.poster.backspaces, [6])
        XCTAssertNil(fixture.rules.disposition(source: "ghbdtn", candidate: "привет"))
    }

    @discardableResult
    private func send(
        _ text: String,
        keyCode: CGKeyCode = 0,
        flags: CGEventFlags = [],
        to monitor: KeyboardMonitor
    ) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)!
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)!
        let units = Array(text.utf16)
        units.withUnsafeBufferPointer {
            event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
        }
        event.flags = flags
        return monitor.handle(type: .keyDown, event: event) != nil
    }

    private func sendModifier(_ flags: CGEventFlags, to monitor: KeyboardMonitor) {
        let source = CGEventSource(stateID: .hidSystemState)!
        let event = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: true)!
        event.flags = flags
        _ = monitor.handle(type: .flagsChanged, event: event)
    }

    private func makeFixture() throws -> (
        monitor: KeyboardMonitor,
        poster: RecordingPoster,
        sources: RecordingInputSources,
        sound: RecordingSound,
        rules: UserRuleStore,
        cleanup: () -> Void
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("monitor-hotkeys-\(UUID().uuidString)")
        let rules = try UserRuleStore(fileURL: root.appendingPathComponent("rules.json"))
        let poster = RecordingPoster()
        let sources = RecordingInputSources()
        let sound = RecordingSound()
        let service = LexiconService()
        try service.start()
        let monitor = KeyboardMonitor(
            lexiconService: service,
            ruleStore: rules,
            focusProvider: FixedFocus(),
            executor: ReplacementExecutor(eventPoster: poster, inputSources: sources),
            sound: sound
        )
        return (monitor, poster, sources, sound, rules, { try? FileManager.default.removeItem(at: root) })
    }
}
