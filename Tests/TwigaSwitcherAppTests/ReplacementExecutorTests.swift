import XCTest
import TwigaSwitcherCore
@testable import TwigaSwitcherApp

private final class RecordingEventPoster: EventPosting {
    enum Action: Equatable { case backspace(count: Int), unicode(String) }
    private(set) var actions: [Action] = []
    var isAvailable = true
    var backspaceResult = true
    var unicodeResults: [Bool] = []
    func postBackspaces(count: Int) -> Bool { actions.append(.backspace(count: count)); return backspaceResult }
    func postUnicode(_ text: String) -> Bool {
        actions.append(.unicode(text))
        return unicodeResults.isEmpty ? true : unicodeResults.removeFirst()
    }
}

private final class RecordingInputSourceManager: InputSourceManaging {
    let result: Bool
    private(set) var selectedLayouts: [KeyboardLayout] = []
    init(result: Bool) { self.result = result }
    func select(_ layout: KeyboardLayout) -> Bool { selectedLayouts.append(layout); return result }
}

final class ReplacementExecutorTests: XCTestCase {
    func testExecutorPostsExactlyOnceThenSelectsLayout() {
        let events = RecordingEventPoster(); let sources = RecordingInputSourceManager(result: true)
        let executor = ReplacementExecutor(eventPoster: events, inputSources: sources)
        XCTAssertEqual(executor.execute(.init(deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian)), .completed)
        XCTAssertEqual(events.actions, [.backspace(count: 6), .unicode("привет"), .unicode(" ")])
        XCTAssertEqual(sources.selectedLayouts, [.russian])
    }

    func testForceCorrectionWithoutDelimiterDoesNotPostEmptyKeyEvent() {
        let events = RecordingEventPoster()
        let sources = RecordingInputSourceManager(result: true)
        let executor = ReplacementExecutor(eventPoster: events, inputSources: sources)

        XCTAssertEqual(
            executor.execute(.init(deleteKeyCount: 3, replacement: "йяй", delimiter: "", targetLayout: .russian)),
            .completed
        )
        XCTAssertEqual(events.actions, [.backspace(count: 3), .unicode("йяй")])
        XCTAssertEqual(sources.selectedLayouts, [.russian])
    }

    func testMissingInputSourceDoesNotRepeatText() {
        let events = RecordingEventPoster(); let sources = RecordingInputSourceManager(result: false)
        let executor = ReplacementExecutor(eventPoster: events, inputSources: sources)
        XCTAssertEqual(executor.execute(.init(deleteKeyCount: 5, replacement: "hello", delimiter: " ", targetLayout: .english)), .textReplacedLayoutUnavailable)
        XCTAssertEqual(events.actions, [.backspace(count: 5), .unicode("hello"), .unicode(" ")])
    }


    func testFailureBeforeMutationCanPreserveOriginalDelimiter() {
        let events = RecordingEventPoster()
        events.isAvailable = false
        let executor = ReplacementExecutor(eventPoster: events, inputSources: RecordingInputSourceManager(result: true))

        XCTAssertEqual(executor.execute(.init(deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian)), .failedBeforeMutation)
        XCTAssertEqual(events.actions, [])
    }

    func testFailureAfterMutationSuppressesOriginalAndNeverRetries() {
        let events = RecordingEventPoster()
        events.unicodeResults = [false]
        let executor = ReplacementExecutor(eventPoster: events, inputSources: RecordingInputSourceManager(result: true))

        XCTAssertEqual(executor.execute(.init(deleteKeyCount: 6, replacement: "привет", delimiter: " ", targetLayout: .russian)), .partialFailure)
        XCTAssertEqual(events.actions, [.backspace(count: 6), .unicode("привет")])
    }

    func testReverseUsesTheSameSinglePassSafetyContract() {
        let events = RecordingEventPoster()
        let sources = RecordingInputSourceManager(result: true)
        let executor = ReplacementExecutor(eventPoster: events, inputSources: sources)

        XCTAssertEqual(
            executor.reverse(.init(deleteKeyCount: 7, replacement: "ghbdtn", delimiter: " ", targetLayout: .english)),
            .completed
        )
        XCTAssertEqual(events.actions, [.backspace(count: 7), .unicode("ghbdtn"), .unicode(" ")])
        XCTAssertEqual(sources.selectedLayouts, [.english])
    }
}
