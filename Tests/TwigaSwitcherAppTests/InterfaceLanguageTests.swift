import Foundation
@testable import TwigaSwitcherApp
import XCTest

final class InterfaceLanguageTests: XCTestCase {
    func testSystemChoiceUsesMacOSPrimaryLanguageAndEnglishFallback() {
        XCTAssertEqual(InterfaceLanguage.system.resolve(preferredLanguages: ["ru-RU", "en-US"]), .russian)
        XCTAssertEqual(InterfaceLanguage.system.resolve(preferredLanguages: ["en-US", "ru-RU"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolve(preferredLanguages: ["fr-FR", "ru-RU"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolve(preferredLanguages: []), .english)
    }

    func testExplicitChoiceOverridesSystemLanguage() {
        XCTAssertEqual(InterfaceLanguage.russian.resolve(preferredLanguages: ["en-US"]), .russian)
        XCTAssertEqual(InterfaceLanguage.english.resolve(preferredLanguages: ["ru-RU"]), .english)
        XCTAssertEqual(DisplayLanguage.russian.locale.identifier, "ru")
        XCTAssertEqual(DisplayLanguage.english.locale.identifier, "en")
    }

    func testEveryInterfaceTextHasTranslationsWithInvariantKeyboardNames() {
        let keyboardNames: Set<InterfaceText> = [
            .space, .option, .controlOption, .controlShift, .commandOption,
            .commandShift, .controlCommand, .optionShift,
        ]
        for key in InterfaceText.allCases {
            XCTAssertFalse(key.localized(.english).isEmpty, String(describing: key))
            XCTAssertFalse(key.localized(.russian).isEmpty, String(describing: key))
            XCTAssertNotEqual(key.localized(.english), "interface.\(key)")
            XCTAssertNotEqual(key.localized(.russian), "interface.\(key)")
            if keyboardNames.contains(key) {
                XCTAssertEqual(key.localized(.russian), key.localized(.english), String(describing: key))
            } else {
                XCTAssertNotEqual(key.localized(.russian), key.localized(.english), String(describing: key))
            }
        }
        XCTAssertEqual(InterfaceText.enableAutomaticCorrection.localized(.russian), "Включить автопереключение")
        XCTAssertEqual(InterfaceText.enableAutomaticCorrection.localized(.english), "Enable Automatic Correction")
    }

    func testStatusAndDynamicMenuLabelsUseSelectedLanguage() {
        XCTAssertEqual(AppState.active.title(in: .russian), "Автопереключение включено")
        XCTAssertEqual(AppState.paused.title(in: .english), "Automatic correction is paused")
        XCTAssertEqual(InterfaceText.alwaysCorrect.localized(.russian, "linux", "дштгч"),
                       "Всегда исправлять «linux» → «дштгч»")
        XCTAssertEqual(InterfaceStatus.removeRuleFailed("disk error").localized(.russian),
                       "Не удалось удалить правило: disk error")
    }

    func testKnownInputSourceDiagnosticIsTranslated() {
        XCTAssertEqual(
            AppState.error("Russian input source is unavailable").title(in: .russian),
            "Русская раскладка недоступна"
        )
        XCTAssertEqual(
            AppState.error("Event monitor stopped").title(in: .russian),
            "Перехват клавиш остановлен"
        )
        XCTAssertEqual(
            AppState.error("Bundled frequency dictionaries are unavailable or corrupt").title(in: .russian),
            "Встроенные частотные словари недоступны или повреждены"
        )
    }

    func testShortcutChoicesKeepEnglishKeyNamesInBothLanguages() {
        let choices: [(InterfaceText, String)] = [
            (.space, "Space"), (.option, "Option"),
            (.controlOption, "Control + Option"), (.controlShift, "Control + Shift"),
            (.commandOption, "Command + Option"), (.commandShift, "Command + Shift"),
            (.controlCommand, "Control + Command"), (.optionShift, "Option + Shift"),
        ]
        for (key, expected) in choices {
            XCTAssertEqual(key.localized(.english), expected)
            XCTAssertEqual(key.localized(.russian), expected)
        }
    }

    func testRepeatedLanguageChangesPreserveExplicitSelection() {
        XCTAssertEqual(InterfaceText.settings.localized(.english), "Settings")
        XCTAssertEqual(InterfaceText.settings.localized(.russian), "Настройки")
        XCTAssertEqual(InterfaceText.settings.localized(.english), "Settings")
        XCTAssertEqual(InterfaceText.settings.localized(.russian), "Настройки")
    }

    func testLocalizedFormatsPreserveNumbersQuotesAndUnicodeArguments() {
        XCTAssertEqual(InterfaceText.importedDictionaryDetail.localized(.russian, "My «Terms»", 123, "en, ru"),
                       "My «Terms» · записей: 123 · en, ru")
        XCTAssertEqual(InterfaceText.importedDictionaryDetail.localized(.english, "My «Terms»", 123, "en, ru"),
                       "My «Terms» · 123 entries · en, ru")
    }

    func testDictionaryDiagnosticsTranslatePrefixesAndKeepDetails() {
        XCTAssertEqual(InterfaceText.diagnostic(
            "Disabled unreadable dictionary pack: test.dictionary\nDisabled corrupt dictionary pack: My Terms", in: .russian
        ), "Отключён нечитаемый пакет словаря: test.dictionary\nОтключён повреждённый пакет словаря: My Terms")
    }

    func testResourceLookupUsesExplicitLanguageAndEnglishFallbackForMissingKey() throws {
        let resources = InterfaceStringResources(bundle: try fixtureBundle(
            russianStrings: #"""
            "interface.settings" = "Настройки из ресурса";
            """#
        ))
        XCTAssertEqual(resources.localizedString(forKey: "interface.settings", in: .english), "Settings from resource")
        XCTAssertEqual(resources.localizedString(forKey: "interface.settings", in: .russian), "Настройки из ресурса")
        XCTAssertEqual(resources.localizedString(forKey: "interface.notice", in: .russian), "Notice from resource")
        XCTAssertEqual(resources.localizedString(forKey: "interface.missing", in: .russian), "interface.missing")
    }

    func testMissingRussianResourceFallsBackToEnglish() throws {
        let resources = InterfaceStringResources(bundle: try fixtureBundle(russianStrings: nil))
        XCTAssertEqual(resources.localizedString(forKey: "interface.settings", in: .russian), "Settings from resource")
    }

    private func fixtureBundle(russianStrings: String?) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InterfaceStrings-\(UUID().uuidString).bundle")
        let resourceRoot = root.appendingPathComponent("Contents/Resources")
        let english = resourceRoot.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let info = ["CFBundleIdentifier": "test.interface-strings.\(UUID().uuidString)", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        try #"""
        "interface.settings" = "Settings from resource";
        "interface.notice" = "Notice from resource";
        """#.write(to: english.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        if let russianStrings {
            let russian = resourceRoot.appendingPathComponent("ru.lproj")
            try FileManager.default.createDirectory(at: russian, withIntermediateDirectories: true)
            try russianStrings.write(to: russian.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        }
        return try XCTUnwrap(Bundle(url: root))
    }
}
