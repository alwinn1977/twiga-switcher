import XCTest
import LayoutSwitcherCore
@testable import LayoutSwitcherApp

private final class RecordingEventPoster: EventPosting {
    enum Action: Equatable { case backspace(count: Int), unicode(String) }
    private(set) var actions: [Action] = []
    func postBackspaces(count: Int) -> Bool { actions.append(.backspace(count: count)); return true }
    func postUnicode(_ text: String) -> Bool { actions.append(.unicode(text)); return true }
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

    func testMissingInputSourceDoesNotRepeatText() {
        let events = RecordingEventPoster(); let sources = RecordingInputSourceManager(result: false)
        let executor = ReplacementExecutor(eventPoster: events, inputSources: sources)
        XCTAssertEqual(executor.execute(.init(deleteKeyCount: 5, replacement: "hello", delimiter: " ", targetLayout: .english)), .textReplacedLayoutUnavailable)
        XCTAssertEqual(events.actions, [.backspace(count: 5), .unicode("hello"), .unicode(" ")])
    }
}
