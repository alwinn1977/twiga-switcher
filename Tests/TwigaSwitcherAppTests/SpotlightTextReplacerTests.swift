import AppKit
import XCTest
import TwigaSwitcherCore
@testable import TwigaSwitcherApp

@MainActor
final class NativeSearchTextEditor: @preconcurrency FocusedTextEditing {
    let editor: NSTextView
    var readable = true
    var acceptsValue = true
    var reportsWriteTimeout = false
    var acceptsSelection = true

    init(_ editor: NSTextView) { self.editor = editor }

    func read(_ focus: FocusSnapshot) -> FocusedTextReadResult {
        readable ? .value(.init(value: editor.string, selection: editor.selectedRange())) : .failed
    }

    func setValue(_ value: String, in focus: FocusSnapshot) -> FocusedTextWriteResult {
        guard acceptsValue else { return .rejected }
        editor.string = value
        return reportsWriteTimeout ? .uncertain : .written
    }

    func setSelection(_ selection: NSRange, in focus: FocusSnapshot) -> Bool {
        guard acceptsSelection else { return false }
        editor.setSelectedRange(selection)
        return true
    }
}

private struct SearchFocusProvider: FocusSnapshotProviding {
    var bundleID = "com.apple.Spotlight"
    var elementIdentifier: String?

    func snapshot() -> FocusSnapshot? {
        .init(identity: .init(processID: 42, elementHash: 7), bundleID: bundleID, elementIdentifier: elementIdentifier)
    }
}

private final class SearchLayoutSelector: InputSourceManaging {
    func select(_ layout: KeyboardLayout) -> Bool { true }
}

final class SpotlightTextReplacerTests: XCTestCase {
    private let focus = FocusSnapshot(identity: .init(processID: 42, elementHash: 7), bundleID: "com.apple.Spotlight")

    @MainActor
    func testSpotlightHostedBySiriUsesSearchFieldReplacement() {
        let editor = NSTextView()
        editor.string = "проверка цштв completion"
        editor.setSelectedRange(.init(location: "проверка цштв".utf16.count, length: " completion".utf16.count))
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        let siriFocus = FocusSnapshot(
            identity: focus.identity, bundleID: "com.apple.campo", elementIdentifier: "SpotlightSearchField"
        )
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 3, replacement: "wind", delimiter: "", targetLayout: .english
        ), focus: siriFocus, sourceText: "цштв"), .replaced)
        XCTAssertEqual(editor.string, "проверка wind")
    }

    @MainActor
    func testSiriConversationKeepsKeyboardReplacement() {
        let editor = NSTextView()
        editor.string = "b"
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        XCTAssertNil(replacer.replace(.init(
            deleteKeyCount: 1, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: .init(identity: focus.identity, bundleID: "com.apple.campo", elementIdentifier: "ConversationInput")))
        XCTAssertEqual(editor.string, "b")
    }

    @MainActor
    func testAlreadyDeliveredTriggerRemovesEntireObservedSource() {
        let editor = NSTextView()
        editor.string = "проверка цштв completion"
        editor.setSelectedRange(.init(location: "проверка цштв".utf16.count, length: " completion".utf16.count))
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 3, replacement: "wind", delimiter: "", targetLayout: .english
        ), focus: focus, sourceText: "цштв"), .replaced)
        XCTAssertEqual(editor.string, "проверка wind")
    }

    @MainActor
    func testAlreadyDeliveredBoundaryKeyDoesNotLeaveSourceOrDuplicateSpace() {
        let editor = NSTextView()
        editor.string = "проверка b "
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 1, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: focus, sourceText: "b"), .replaced)
        XCTAssertEqual(editor.string, "проверка и ")
    }

    @MainActor
    func testBoundaryCorrectionPreservesBufferedPunctuationBeforeAndAfterTriggerDelivery() {
        for (query, deleteCount, delimiter, expected) in [
            ("проверка b;", 2, "; ", "проверка и; "),
            ("проверка b; ", 2, "; ", "проверка и; "),
            ("проверка b., ", 3, "., ", "проверка и., ")
        ] {
            let editor = NSTextView()
            editor.string = query
            editor.setSelectedRange(.init(location: query.utf16.count, length: 0))
            let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
            XCTAssertEqual(replacer.replace(.init(
                deleteKeyCount: deleteCount, replacement: "и", delimiter: delimiter, targetLayout: .russian
            ), focus: focus, sourceText: "b"), .replaced)
            XCTAssertEqual(editor.string, expected, query)
        }
    }

    @MainActor
    func testForceCorrectionAndUndoWithPunctuationValidateSourceBeforeMutation() {
        for source in ["b", "и"] {
            let editor = NSTextView()
            editor.string = "проверка x; "
            editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
            let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
            XCTAssertEqual(replacer.replace(.init(
                deleteKeyCount: 3, replacement: source == "b" ? "и" : "b",
                delimiter: "; ", targetLayout: source == "b" ? .russian : .english
            ), focus: focus, sourceText: source), .failedBeforeMutation)
            XCTAssertEqual(editor.string, "проверка x; ")
        }
    }

    @MainActor
    func testForceCorrectionAndUndoPreservePunctuation() {
        let editor = NSTextView()
        editor.string = "проверка b; "
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 3, replacement: "и", delimiter: "; ", targetLayout: .russian
        ), focus: focus, sourceText: "b"), .replaced)
        XCTAssertEqual(editor.string, "проверка и; ")
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 3, replacement: "b", delimiter: "; ", targetLayout: .english
        ), focus: focus, sourceText: "и"), .replaced)
        XCTAssertEqual(editor.string, "проверка b; ")
    }

    @MainActor
    func testKeyboardMonitorReplacesMixedSearchQueryWithActiveCompletions() throws {
        for alreadyDelivered in [false, true] {
            try checkMixedQuery(alreadyDelivered: alreadyDelivered)
        }
    }

    @MainActor
    func testKeyboardMonitorReplacesMixedQueryInSiriHostedSpotlight() throws {
        for alreadyDelivered in [false, true] {
            try checkMixedQuery(alreadyDelivered: alreadyDelivered, focusProvider: .init(
                bundleID: "com.apple.campo", elementIdentifier: "SpotlightSearchField"
            ))
        }
    }

    @MainActor
    private func checkMixedQuery(alreadyDelivered: Bool, focusProvider: SearchFocusProvider = .init()) throws {
        let editor = NSTextView()
        editor.string = "проверка "
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let poster = nativePoster(editor)
        let service = LexiconService()
        try service.start()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = KeyboardMonitor(
            lexiconService: service, ruleStore: try UserRuleStore(fileURL: root.appendingPathComponent("rules.json")),
            focusProvider: focusProvider,
            executor: ReplacementExecutor(
                eventPoster: poster, inputSources: SearchLayoutSelector(),
                spotlightTextReplacer: .init(editor: NativeSearchTextEditor(editor))
            ), hotkeys: .defaults, soundEnabled: false
        )

        for character in "цштвows b дштгч " {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: character == " " ? 49 : 0, keyDown: true))
            event.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(getpid()))
            let units = Array(String(character).utf16)
            units.withUnsafeBufferPointer {
                event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
            }
            if alreadyDelivered { insertWithCompletion(character, in: editor) }
            if monitor.handle(type: .keyDown, event: event) != nil, !alreadyDelivered {
                insertWithCompletion(character, in: editor)
            }
        }
        XCTAssertEqual(editor.string, "проверка windows и linux ", "alreadyDelivered=\(alreadyDelivered)")
    }

    @MainActor
    private func insertWithCompletion(_ character: Character, in editor: NSTextView) {
        editor.insertText(String(character), replacementRange: editor.selectedRange())
        if character != " " {
            let caret = editor.string.utf16.count
            editor.string += " completion"
            editor.setSelectedRange(.init(location: caret, length: " completion".utf16.count))
        }
    }

    @MainActor
    func testUnexpectedFieldTextDoesNotDeleteNeighbouringQuery() {
        let editor = NSTextView()
        editor.string = "проверка xyz"
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 3, replacement: "wind", delimiter: "", targetLayout: .english
        ), focus: focus, sourceText: "цштв"), .failedBeforeMutation)
        XCTAssertEqual(editor.string, "проверка xyz")
    }

    @MainActor
    func testReportedMixedQueryHasNoLeftoverFirstLetters() {
        let editor = NSTextView()
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        editor.string = "проверка "
        for (source, replacement, continued) in [("цшт", "wind", "ows "), ("b", "и ", ""), ("дшт", "linu", "x ")] {
            editor.string += source
            let caret = editor.string.utf16.count
            editor.string += " completion"
            editor.setSelectedRange(.init(location: caret, length: " completion".utf16.count))
            XCTAssertEqual(replacer.replace(.init(
                deleteKeyCount: source.count, replacement: replacement, delimiter: "",
                targetLayout: source == "b" ? .russian : .english
            ), focus: focus), .replaced)
            editor.insertText(continued, replacementRange: editor.selectedRange())
        }
        XCTAssertEqual(editor.string, "проверка windows и linux ")
        XCTAssertEqual(editor.selectedRange(), .init(location: editor.string.utf16.count, length: 0))
    }

    @MainActor
    func testCollapsedCaretPreservesTextOnBothSidesAndUsesUTF16Position() {
        let editor = NSTextView()
        editor.string = "🦒 проверка цшт suffix"
        editor.setSelectedRange(.init(location: "🦒 проверка цшт".utf16.count, length: 0))
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 3, replacement: "wind", delimiter: "", targetLayout: .english
        ), focus: focus), .replaced)
        XCTAssertEqual(editor.string, "🦒 проверка wind suffix")
        XCTAssertEqual(editor.selectedRange(), .init(location: "🦒 проверка wind".utf16.count, length: 0))
    }

    @MainActor
    func testBoundaryCorrectionAndReversalPreservePreviousWords() {
        let editor = NSTextView()
        editor.string = "проверка b"
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 1, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: focus), .replaced)
        XCTAssertEqual(editor.string, "проверка и ")
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 2, replacement: "b", delimiter: " ", targetLayout: .english
        ), focus: focus), .replaced)
        XCTAssertEqual(editor.string, "проверка b ")
    }

    @MainActor
    func testOtherApplicationsKeepKeyboardReplacement() {
        let editor = NSTextView()
        editor.string = "b"
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        XCTAssertNil(replacer.replace(.init(
            deleteKeyCount: 1, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: .init(identity: focus.identity, bundleID: "com.apple.TextEdit")))
        XCTAssertEqual(editor.string, "b")
    }

    @MainActor
    func testUnreadableFieldAndInsufficientSourceTextDoNotMutateQuery() {
        let editor = NSTextView()
        editor.string = "b"
        editor.setSelectedRange(.init(location: 1, length: 0))
        let access = NativeSearchTextEditor(editor)
        let replacer = SpotlightTextReplacer(editor: access)
        access.readable = false
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 1, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: focus), .failedBeforeMutation)
        access.readable = true
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 2, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: focus), .failedBeforeMutation)
        XCTAssertEqual(editor.string, "b")
    }

    @MainActor
    func testRejectedValueWriteLeavesQueryIntact() {
        let editor = NSTextView()
        editor.string = "проверка b"
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let access = NativeSearchTextEditor(editor)
        access.acceptsValue = false
        let replacer = SpotlightTextReplacer(editor: access)
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 1, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: focus), .failedBeforeMutation)
        XCTAssertEqual(editor.string, "проверка b")
    }

    @MainActor
    func testCaretWriteFailureReportsMutationWithoutRepeatingText() {
        let editor = NSTextView()
        editor.string = "проверка b"
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let access = NativeSearchTextEditor(editor)
        access.acceptsSelection = false
        let executor = ReplacementExecutor(
            eventPoster: nativePoster(editor), inputSources: SearchLayoutSelector(),
            spotlightTextReplacer: .init(editor: access)
        )
        XCTAssertEqual(executor.execute(.init(
            deleteKeyCount: 1, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: focus), .partialFailure)
        XCTAssertEqual(editor.string, "проверка и ")
    }

    @MainActor
    func testWriteTimeoutCannotRetryOverAlreadyReplacedQuery() {
        let editor = NSTextView()
        editor.string = "проверка b"
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let access = NativeSearchTextEditor(editor)
        access.reportsWriteTimeout = true
        let executor = ReplacementExecutor(
            eventPoster: nativePoster(editor), inputSources: SearchLayoutSelector(),
            spotlightTextReplacer: .init(editor: access)
        )
        XCTAssertEqual(executor.execute(.init(
            deleteKeyCount: 1, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: focus), .partialFailure)
        XCTAssertEqual(editor.string, "проверка и ")
    }

    @MainActor
    func testSelectionInMiddleOfQueryIsNotTreatedAsCompletion() {
        let editor = NSTextView()
        editor.string = "b completion suffix"
        editor.setSelectedRange(.init(location: 1, length: " completion".utf16.count))
        let replacer = SpotlightTextReplacer(editor: NativeSearchTextEditor(editor))
        XCTAssertEqual(replacer.replace(.init(
            deleteKeyCount: 1, replacement: "и", delimiter: " ", targetLayout: .russian
        ), focus: focus), .failedBeforeMutation)
        XCTAssertEqual(editor.string, "b completion suffix")
    }

    @MainActor
    private func nativePoster(_ editor: NSTextView) -> EventPoster {
        EventPoster(makeKeyboardEvent: { source, keyCode, down in
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            if keyCode == 51 {
                var backspace: UniChar = 0x7F
                event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &backspace)
            }
            return event
        }, sendEvent: { event in
            if event.type == .keyDown, let native = NSEvent(cgEvent: event) { editor.keyDown(with: native) }
        })
    }
}
