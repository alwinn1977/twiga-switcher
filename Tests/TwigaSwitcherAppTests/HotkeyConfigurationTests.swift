import CoreGraphics
@testable import TwigaSwitcherApp
import XCTest

final class HotkeyConfigurationTests: XCTestCase {
    func testDefaultShortcutsMatchPhysicalKeysAndExactModifiers() {
        let shortcuts = HotkeyConfiguration.defaults

        XCTAssertEqual(shortcuts.action(keyCode: 6, flags: [.maskControl, .maskShift]), .undoCorrection)
        XCTAssertEqual(shortcuts.action(keyCode: 49, flags: [.maskControl, .maskShift]), .forceCorrection)
        XCTAssertNil(shortcuts.action(keyCode: 6, flags: [.maskCommand]))
        XCTAssertNil(shortcuts.action(keyCode: 6, flags: [.maskControl, .maskAlternate, .maskShift]))
    }

    func testLegacyDefaultsMigrateButCustomBindingsArePreserved() throws {
        let name = "HotkeyMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(try JSONEncoder().encode(HotkeyConfiguration.legacyDefaults), forKey: "hotkeyConfiguration")
        let store = HotkeyStore(defaults: defaults)
        XCTAssertEqual(store.configuration, .defaults)
        let custom = Hotkey(keyCode: 35, modifiers: [.maskControl, .maskShift], label: "P")
        XCTAssertTrue(store.set(custom, for: .forceCorrection))
        XCTAssertEqual(HotkeyStore(defaults: defaults).configuration.force, custom)
    }

    func testOptionSpaceDefaultsMigrateWithoutChangingCustomConfiguration() throws {
        let name = "OptionSpaceMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = HotkeyConfiguration(
            undo: Hotkey(keyCode: 49, modifiers: [.maskAlternate, .maskShift], label: "Space"),
            force: Hotkey(keyCode: 49, modifiers: [.maskAlternate], label: "Space")
        )
        defaults.set(try JSONEncoder().encode(previous), forKey: "hotkeyConfiguration")
        let store = HotkeyStore(defaults: defaults)
        XCTAssertEqual(store.configuration, .defaults)
        var customized = previous
        customized.force = Hotkey(keyCode: 35, modifiers: [.maskCommand, .maskShift], label: "P")
        defaults.set(try JSONEncoder().encode(customized), forKey: "hotkeyConfiguration")
        XCTAssertEqual(store.configuration, customized)
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
            Hotkey(keyCode: 49, modifiers: [.maskControl, .maskShift], label: "Пробел"),
            for: .undoCorrection
        ))
        XCTAssertEqual(store.configuration.undo, custom)
    }
}
