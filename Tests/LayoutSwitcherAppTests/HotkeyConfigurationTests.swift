import CoreGraphics
@testable import LayoutSwitcherApp
import XCTest

final class HotkeyConfigurationTests: XCTestCase {
    func testDefaultShortcutsMatchPhysicalKeysAndExactModifiers() {
        let shortcuts = HotkeyConfiguration.defaults

        XCTAssertEqual(shortcuts.action(keyCode: 6, flags: [.maskControl, .maskAlternate]), .undoCorrection)
        XCTAssertEqual(shortcuts.action(keyCode: 37, flags: [.maskControl, .maskAlternate]), .forceCorrection)
        XCTAssertNil(shortcuts.action(keyCode: 6, flags: [.maskCommand]))
        XCTAssertNil(shortcuts.action(keyCode: 6, flags: [.maskControl, .maskAlternate, .maskShift]))
    }

    func testCustomShortcutPersistsAndDuplicateIsRejected() throws {
        let suiteName = "HotkeyConfigurationTests-\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = HotkeyStore(defaults: suite)
        let custom = Hotkey(keyCode: 35, modifiers: [.maskCommand, .maskShift], label: "P")

        XCTAssertTrue(store.set(custom, for: .undoCorrection))
        XCTAssertEqual(HotkeyStore(defaults: suite).configuration.undo, custom)
        XCTAssertFalse(store.set(store.configuration.force, for: .undoCorrection))
        XCTAssertFalse(store.set(
            Hotkey(keyCode: 37, modifiers: [.maskControl, .maskAlternate], label: "Д"),
            for: .undoCorrection
        ))
        XCTAssertEqual(store.configuration.undo, custom)
    }
}
