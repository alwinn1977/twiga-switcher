import Carbon
import CoreGraphics
import TwigaSwitcherCore
import TwigaSwitcherLexicon
import XCTest
@testable import TwigaSwitcherApp

final class InputSourceRecoveryTests: XCTestCase {
    private final class Editor: EventPosting {
        var text = ""
        var isAvailable = true
        func postBackspaces(count: Int) -> Bool {
            guard count <= text.count else { return false }
            text.removeLast(count)
            return true
        }
        func postUnicode(_ value: String) -> Bool { text += value; return true }
    }

    private struct FixedFocus: FocusSnapshotProviding {
        func snapshot() -> FocusSnapshot? {
            .init(identity: .init(processID: 42, elementHash: 7))
        }
    }

    private final class Poster: EventPosting {
        var isAvailable = true
        var deletions: [Int] = []
        var insertions: [String] = []
        func postBackspaces(count: Int) -> Bool { deletions.append(count); return true }
        func postUnicode(_ text: String) -> Bool { insertions.append(text); return true }
    }

    private final class Sources {
        var current: TISInputSource?
        var available: [TISInputSource]
        var listReads = 0
        let english: TISInputSource
        let russian: TISInputSource

        init() throws {
            let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
            func source(_ language: String) -> TISInputSource? {
                list.first { source in
                    guard TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil,
                          let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return false }
                    let languages = unsafeBitCast(property, to: CFArray.self) as! [String]
                    return languages.first == language
                }
            }
            guard let english = source("en"), let russian = source("ru") else {
                throw XCTSkip("Recovery fixtures require enabled English and Russian layouts")
            }
            self.english = english
            self.russian = russian
            current = english
            available = [english, russian]
        }

        func manager() -> InputSourceManager {
            InputSourceManager(
                currentSource: { self.current },
                availableSources: { self.listReads += 1; return self.available },
                selectSource: { self.current = $0; return noErr }
            )
        }
    }

    func testMissingSelectionRecoversWithoutAnotherNotification() throws {
        let sources = try Sources()
        let manager = sources.manager()
        manager.refresh()
        sources.current = nil
        manager.refresh() // A notification observes an intermediate system state.
        XCTAssertNil(manager.currentLayout)
        sources.current = sources.english // No further notification arrives.

        XCTAssertTrue(manager.refreshIfNeeded(retryUnavailable: true))
        XCTAssertEqual(manager.currentLayout, .english)
        XCTAssertNotNil(manager.tables)
        XCTAssertTrue(manager.missingLayouts.isEmpty)
    }

    func testTemporarilyMissingCatalogRecoversEvenWhenSelectedIDIsUnchanged() throws {
        let sources = try Sources()
        let manager = sources.manager()
        manager.refresh()
        let selectedID = manager.currentID
        sources.available = []
        manager.refresh()
        XCTAssertEqual(manager.currentID, selectedID)
        XCTAssertNil(manager.currentLayout)
        sources.available = [sources.english, sources.russian]

        XCTAssertTrue(manager.refreshIfNeeded(retryUnavailable: true))
        XCTAssertEqual(manager.currentID, selectedID)
        XCTAssertEqual(manager.currentLayout, .english)
        XCTAssertTrue(manager.missingLayouts.isEmpty)
    }

    func testMissedSelectionNotificationIsDetectedBeforeNextKey() throws {
        let sources = try Sources()
        let manager = sources.manager()
        manager.refresh()
        sources.current = sources.russian

        XCTAssertTrue(manager.refreshIfNeeded())
        XCTAssertEqual(manager.currentLayout, .russian)
        XCTAssertFalse(manager.refreshIfNeeded())
    }

    func testOwnSelectionAndHealthChecksDoNotResetLiveWordOrRebuildTables() throws {
        let sources = try Sources()
        let manager = sources.manager()
        manager.refresh()
        XCTAssertTrue(manager.select(.russian))
        for _ in 0..<100 {
            XCTAssertFalse(manager.refreshIfNeeded(retryUnavailable: true))
        }
        XCTAssertEqual(sources.listReads, 1)
        XCTAssertEqual(manager.currentLayout, .russian)
        XCTAssertFalse(manager.refresh(), "Our delayed notification must not clear the live word")
    }

    func testHealthCheckRepairsInputSourcesEvenWithoutADisabledTap() throws {
        let sources = try Sources()
        sources.current = nil
        let manager = sources.manager()
        manager.refresh()
        let monitor = KeyboardMonitor(inputSources: manager)
        var notifications = 0
        monitor.onInputSourcesChanged = { notifications += 1 }
        sources.current = sources.english

        monitor.checkHealth()

        XCTAssertEqual(manager.currentLayout, .english)
        XCTAssertEqual(notifications, 1)
        monitor.checkHealth()
        XCTAssertEqual(notifications, 1, "Unchanged health checks must not repeatedly publish UI state")
    }

    func testHealthChecksAndDelayedOwnNotificationPreserveActualWordForForceCorrection() throws {
        let sources = try Sources()
        let manager = sources.manager()
        let poster = Poster()
        let service = LexiconService()
        try service.start()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = try UserRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
        let monitor = KeyboardMonitor(lexiconService: service, ruleStore: rules,
            focusProvider: FixedFocus(),
            executor: ReplacementExecutor(eventPoster: poster, inputSources: manager),
            inputSources: manager, hotkeys: .defaults, soundEnabled: false)
        monitor.refreshInputSources()

        func send(_ text: String, key: CGKeyCode = 0, flags: CGEventFlags = []) throws {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true))
            let units = Array(text.utf16)
            units.withUnsafeBufferPointer {
                event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
            }
            event.flags = flags
            _ = monitor.handle(type: .keyDown, event: event)
        }

        for character in "ghbd" { try send(String(character)) }
        XCTAssertEqual(poster.insertions, ["прив"])
        XCTAssertEqual(manager.currentLayout, .russian)
        monitor.checkHealth()
        monitor.refreshInputSources() // Delayed notification for our own switch.
        for character in "ет" {
            try send(String(character))
            monitor.checkHealth()
        }
        try send(" ", key: 49)
        try send("", key: 49, flags: [.maskControl, .maskShift])

        XCTAssertEqual(poster.deletions, [3, 7], "Force must still see the entire six-letter word and space")
        XCTAssertEqual(poster.insertions, ["прив", "ghbdtn", " "])
        XCTAssertEqual(manager.currentLayout, .english)
    }

    func testStaleEventUnicodeDoesNotStopCorrectionAcrossSeveralWords() throws {
        let sources = try Sources()
        let manager = sources.manager()
        let editor = Editor()
        let service = LexiconService()
        try service.start()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = try UserRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
        let monitor = KeyboardMonitor(lexiconService: service, ruleStore: rules,
            focusProvider: FixedFocus(),
            executor: ReplacementExecutor(eventPoster: editor, inputSources: manager),
            inputSources: manager, hotkeys: .defaults, soundEnabled: false)
        monitor.refreshInputSources()
        let tables = try XCTUnwrap(manager.tables)

        // TextEdit translates the physical key in the current layout; the tap's
        // Unicode payload can still contain a valid word in the previous layout.
        for (phrase, intended) in [("привет ", KeyboardLayout.russian), ("hello ", .english),
                                   ("привет ", .russian), ("hello ", .english)] {
            let target = intended == .english ? tables.english : tables.russian
            for character in phrase {
                let key = try XCTUnwrap(target.keys.sorted().first {
                    target[$0] == String(character) && tables.english[$0] != nil && tables.russian[$0] != nil
                })
                let rendered = try XCTUnwrap(tables.text(keyCode: key % 128, shifted: key >= 128,
                                                        layout: try XCTUnwrap(manager.currentLayout)))
                let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: key % 128, keyDown: true))
                event.flags = key >= 128 ? .maskShift : []
                event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
                let stale = Array(String(character).utf16)
                stale.withUnsafeBufferPointer {
                    event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
                }
                if monitor.handle(type: .keyDown, event: event) != nil { editor.text += rendered }
                monitor.checkHealth()
            }
        }

        XCTAssertEqual(editor.text, "привет hello привет hello ")
    }
}
