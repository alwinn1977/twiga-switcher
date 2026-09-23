import Foundation
@testable import LayoutSwitcherApp
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

    func testEveryInterfaceTextHasDistinctRussianTranslation() {
        for key in InterfaceText.allCases {
            XCTAssertFalse(key.localized(.english).isEmpty, String(describing: key))
            XCTAssertFalse(key.localized(.russian).isEmpty, String(describing: key))
            XCTAssertNotEqual(key.localized(.russian), key.localized(.english), String(describing: key))
        }
        XCTAssertEqual(InterfaceText.enableAutomaticCorrection.localized(.russian), "Включить автокоррекцию")
        XCTAssertEqual(InterfaceText.enableAutomaticCorrection.localized(.english), "Enable Automatic Correction")
    }

    func testStatusAndDynamicMenuLabelsUseSelectedLanguage() {
        XCTAssertEqual(AppState.active.title(in: .russian), "Автокоррекция включена")
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

    func testShortcutModifierChoicesAreTranslated() {
        XCTAssertEqual(InterfaceText.controlOption.localized(.russian), "Контроль + Опция")
        XCTAssertEqual(InterfaceText.controlShift.localized(.russian), "Контроль + Шифт")
        XCTAssertEqual(InterfaceText.commandOption.localized(.russian), "Команда + Опция")
        XCTAssertEqual(InterfaceText.commandShift.localized(.russian), "Команда + Шифт")
        XCTAssertEqual(InterfaceText.controlCommand.localized(.russian), "Контроль + Команда")
        XCTAssertEqual(InterfaceText.optionShift.localized(.russian), "Опция + Шифт")
    }
}
