import Foundation

public enum DisplayLanguage: String, Sendable {
    case english
    case russian

    public var locale: Locale { Locale(identifier: self == .russian ? "ru" : "en") }
}

public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system
    case russian
    case english

    public func resolve(preferredLanguages: [String] = Locale.preferredLanguages) -> DisplayLanguage {
        switch self {
        case .russian: return .russian
        case .english: return .english
        case .system:
            let primary = preferredLanguages.first?.lowercased() ?? ""
            return primary == "ru" || primary.hasPrefix("ru-") || primary.hasPrefix("ru_")
                ? .russian : .english
        }
    }
}

public enum InterfaceText: CaseIterable, Sendable {
    case automaticCorrectionActive, automaticCorrectionPaused, permissionsRequired
    case enableAutomaticCorrection, requestPermissions, openPrivacySettings, restartMonitor
    case dictionaries, rules, settings, dictionariesMenu, rulesMenu, settingsMenu, quit
    case alwaysCorrect, neverCorrect
    case language, languageChoice, systemLanguage, russianLanguage, englishLanguage
    case keyboardShortcuts, undoLastCorrection, forceCorrectCurrentWord, shortcutHelp
    case feedback, playSound, modifiers, key, space
    case startup, launchAtLogin, launchAtLoginHelp, loginItemApprovalRequired
    case loginItemUnavailable, loginItemUpdateFailed
    case option, addRulePrompt, addRuleHelp, inputSources, addInputSourcesHelp
    case controlOption, controlShift, commandOption, commandShift, controlCommand, optionShift
    case remove, notice, importDictionary, cancel, removeDictionaryPrompt, dictionary
    case englishFrequencyDictionary, russianFrequencyDictionary, baseDictionaryDetail
    case computerTerms, builtInSubjectDictionary, importedDictionaryDetail
    case imported, importFailed, updateDictionaryFailed, removeDictionaryFailed
    case always, never, delete, forgetAllRules, forgetAllPrompt, forgetAll
    case removeRuleFailed, removeRulesFailed, shortcutConflict
    case eventMonitorNotRunning, unableToStartKeyboardMonitor, unableToSaveLearnedRule
    case eventMonitorStopped, matchingInputSourceUnavailable
    case russianInputSourceUnavailable, englishInputSourceUnavailable, unableToPostReplacementEvents
    case replacementInterrupted, undoReplacementInterrupted, dictionaryStorageUnavailable
    case bundledFrequencyDictionariesUnavailable
    case builtInComputerTermsUnavailable, disabledUnreadableDictionary, disabledCorruptDictionary
    case errorWithDetail
    case permissionsSection, permissionsHelp, accessibility, accessibilityHelp, inputMonitoring, inputMonitoringHelp
    case granted, missing, requestAccess, openSystemSettings, checkAgain, setupPermissions
    case applications, applicationsHelp, standardMode, disabledMode, compatibilityMode, compatibilityWarning
    case addApplication, removeApplication, invalidApplication

    private var translations: (english: String, russian: String) {
        switch self {
        case .automaticCorrectionActive: return ("Automatic correction is active", "Автопереключение включено")
        case .automaticCorrectionPaused: return ("Automatic correction is paused", "Автопереключение приостановлено")
        case .permissionsRequired: return ("Permissions required", "Требуются разрешения")
        case .enableAutomaticCorrection: return ("Enable Automatic Correction", "Включить автопереключение")
        case .requestPermissions: return ("Request Required Permissions", "Запросить разрешения")
        case .openPrivacySettings: return ("Open Privacy Settings", "Открыть настройки конфиденциальности")
        case .restartMonitor: return ("Restart Monitor", "Перезапустить перехват клавиш")
        case .dictionaries: return ("Dictionaries", "Словари")
        case .rules: return ("Rules", "Правила")
        case .settings: return ("Settings", "Настройки")
        case .dictionariesMenu: return ("Dictionaries…", "Словари…")
        case .rulesMenu: return ("Rules…", "Правила…")
        case .settingsMenu: return ("Settings…", "Настройки…")
        case .quit: return ("Quit Twiga Switcher", "Завершить Twiga Switcher")
        case .alwaysCorrect: return ("Always correct “%@” → “%@”", "Всегда исправлять «%@» → «%@»")
        case .neverCorrect: return ("Never correct “%@” → “%@”", "Никогда не исправлять «%@» → «%@»")
        case .language: return ("Language", "Язык")
        case .languageChoice: return ("Interface language", "Язык интерфейса")
        case .systemLanguage: return ("Use macOS language", "Как в macOS")
        case .russianLanguage: return ("Russian", "Русский")
        case .englishLanguage: return ("English", "Английский")
        case .keyboardShortcuts: return ("Keyboard shortcuts", "Сочетания клавиш")
        case .undoLastCorrection: return ("Undo last correction", "Отменить последнее исправление")
        case .forceCorrectCurrentWord: return ("Force-correct current word", "Принудительно исправить текущее слово")
        case .shortcutHelp: return ("Shortcuts work in supported editable fields. Force correction also works immediately after a space.", "Сочетания работают в поддерживаемых полях ввода. Принудительное исправление доступно и сразу после пробела.")
        case .feedback: return ("Feedback", "Отклик")
        case .playSound: return ("Play sound when layout changes", "Воспроизводить звук при смене раскладки")
        case .startup: return ("Startup", "Автозапуск")
        case .launchAtLogin: return ("Launch at login", "Запускать при входе в систему")
        case .launchAtLoginHelp: return ("Start Twiga Switcher automatically when you sign in to your Mac. Off by default.", "Автоматически запускать Twiga Switcher при входе в учётную запись macOS. По умолчанию выключено.")
        case .loginItemApprovalRequired: return ("Allow Twiga Switcher in macOS Login Items to finish enabling automatic startup.", "Чтобы включить автозапуск, разрешите Twiga Switcher в объектах входа в настройках macOS.")
        case .loginItemUnavailable: return ("Automatic startup is unavailable. Launch the built Twiga Switcher.app and try again.", "Автозапуск недоступен. Запустите собранное приложение Twiga Switcher.app и попробуйте снова.")
        case .loginItemUpdateFailed: return ("Unable to change automatic startup: %@", "Не удалось изменить автозапуск: %@")
        case .modifiers: return ("Modifiers", "Модификаторы")
        case .key: return ("Key", "Клавиша")
        case .space: return ("Space", "Пробел")
        case .addRulePrompt: return ("Remember this correction?", "Запомнить это исправление?")
        case .addRuleHelp: return ("Choose how Twiga Switcher should handle this pair next time.", "Выберите, как Twiga Switcher должен обрабатывать эту пару в следующий раз.")
        case .inputSources: return ("Keyboard layouts", "Раскладки клавиатуры")
        case .addInputSourcesHelp: return ("Add the missing layout in System Settings → Keyboard → Text Input → Edit. Correction resumes automatically when both languages are available.", "Добавьте недостающую раскладку: Настройки macOS → Клавиатура → Ввод текста → Изменить. Исправления возобновятся автоматически, когда будут доступны оба языка.")
        case .option: return ("Option", "Опция")
        case .controlOption: return ("Control + Option", "Контроль + Опция")
        case .controlShift: return ("Control + Shift", "Контроль + Шифт")
        case .commandOption: return ("Command + Option", "Команда + Опция")
        case .commandShift: return ("Command + Shift", "Команда + Шифт")
        case .controlCommand: return ("Control + Command", "Контроль + Команда")
        case .optionShift: return ("Option + Shift", "Опция + Шифт")
        case .remove: return ("Remove", "Удалить")
        case .notice: return ("Notice", "Уведомление")
        case .importDictionary: return ("Import…", "Импортировать…")
        case .cancel: return ("Cancel", "Отмена")
        case .removeDictionaryPrompt: return ("Remove %@?", "Удалить %@?")
        case .dictionary: return ("dictionary", "словарь")
        case .englishFrequencyDictionary: return ("English Frequency Dictionary", "Частотный словарь английского языка")
        case .russianFrequencyDictionary: return ("Russian Frequency Dictionary", "Частотный словарь русского языка")
        case .baseDictionaryDetail: return ("Base dictionary · always enabled", "Базовый словарь · всегда включён")
        case .computerTerms: return ("Computer Terms", "Компьютерные термины")
        case .builtInSubjectDictionary: return ("Built-in subject dictionary", "Встроенный предметный словарь")
        case .importedDictionaryDetail: return ("%@ · %d entries · %@", "%@ · записей: %d · %@")
        case .imported: return ("Imported %@", "Импортирован %@")
        case .importFailed: return ("Import failed: %@", "Ошибка импорта: %@")
        case .updateDictionaryFailed: return ("Unable to update dictionary: %@", "Не удалось обновить словарь: %@")
        case .removeDictionaryFailed: return ("Unable to remove dictionary: %@", "Не удалось удалить словарь: %@")
        case .always: return ("Always", "Всегда")
        case .never: return ("Never", "Никогда")
        case .delete: return ("Delete", "Удалить")
        case .forgetAllRules: return ("Forget All Rules", "Забыть все правила")
        case .forgetAllPrompt: return ("Forget all learned rules?", "Забыть все изученные правила?")
        case .forgetAll: return ("Forget All", "Забыть все")
        case .removeRuleFailed: return ("Unable to remove rule: %@", "Не удалось удалить правило: %@")
        case .removeRulesFailed: return ("Unable to remove rules: %@", "Не удалось удалить правила: %@")
        case .shortcutConflict: return ("Choose a valid shortcut that differs from the other action.", "Выберите допустимое сочетание, отличное от другого действия.")
        case .eventMonitorNotRunning: return ("Event monitor is not running", "Перехват клавиш не работает")
        case .unableToStartKeyboardMonitor: return ("Unable to start keyboard monitor", "Не удалось запустить перехват клавиш")
        case .unableToSaveLearnedRule: return ("Unable to save learned rule", "Не удалось сохранить изученное правило")
        case .eventMonitorStopped: return ("Event monitor stopped", "Перехват клавиш остановлен")
        case .matchingInputSourceUnavailable: return ("Matching input source is unavailable", "Нужная раскладка недоступна")
        case .russianInputSourceUnavailable: return ("Russian input source is unavailable", "Русская раскладка недоступна")
        case .englishInputSourceUnavailable: return ("English input source is unavailable", "Английская раскладка (US/ABC/British) недоступна")
        case .unableToPostReplacementEvents: return ("Unable to post replacement events", "Не удалось отправить события исправления")
        case .replacementInterrupted: return ("Replacement was interrupted", "Исправление прервано")
        case .undoReplacementInterrupted: return ("Undo replacement was interrupted", "Отмена исправления прервана")
        case .dictionaryStorageUnavailable: return ("Dictionary storage is unavailable", "Хранилище словарей недоступно")
        case .bundledFrequencyDictionariesUnavailable: return ("Bundled frequency dictionaries are unavailable or corrupt", "Встроенные частотные словари недоступны или повреждены")
        case .builtInComputerTermsUnavailable: return ("Built-in Computer Terms dictionary is unavailable", "Встроенный словарь компьютерных терминов недоступен")
        case .disabledUnreadableDictionary: return ("Disabled unreadable dictionary pack: %@", "Отключён нечитаемый пакет словаря: %@")
        case .disabledCorruptDictionary: return ("Disabled corrupt dictionary pack: %@", "Отключён повреждённый пакет словаря: %@")
        case .errorWithDetail: return ("Error: %@", "Ошибка: %@")
        case .permissionsSection: return ("Permissions", "Доступы")
        case .permissionsHelp: return ("Twiga Switcher needs both permissions to read typing and check whether the focused field is safe to edit. After granting access, return here and check again. macOS may require restarting the app.", "Для работы нужны оба доступа: читать нажатия клавиш и проверять, можно ли безопасно исправлять текст в активном поле. После выдачи доступа вернитесь сюда и проверьте снова. macOS может потребовать перезапуск приложения.")
        case .accessibility: return ("Accessibility", "Универсальный доступ")
        case .accessibilityHelp: return ("Checks the focused field and sends corrected text.", "Проверяет активное поле и вводит исправленный текст.")
        case .inputMonitoring: return ("Input Monitoring", "Мониторинг ввода")
        case .inputMonitoringHelp: return ("Reads keystrokes so a wrong layout can be detected.", "Читает нажатия клавиш, чтобы определить неверную раскладку.")
        case .granted: return ("Granted", "Разрешён")
        case .missing: return ("Not granted", "Не разрешён")
        case .requestAccess: return ("Request Access", "Запросить доступ")
        case .openSystemSettings: return ("Open System Settings", "Открыть настройки macOS")
        case .checkAgain: return ("Check Again", "Проверить снова")
        case .setupPermissions: return ("Set Up Permissions…", "Настроить доступы…")
        case .applications: return ("Applications", "Приложения")
        case .applicationsHelp: return ("Unlisted apps use Standard. Standard: correct only in editable fields confirmed by macOS. Off: never correct. Compatibility: also allow editable groups and apps that do not report a focused field.", "Для приложений вне списка действует обычный режим. Обычный: исправлять только в редактируемых полях, подтверждённых macOS. Выключен: никогда не исправлять. Совместимость: также разрешать редактируемые группы и приложения, которые не сообщают активное поле.")
        case .standardMode: return ("Standard", "Обычный")
        case .disabledMode: return ("Off", "Выключен")
        case .compatibilityMode: return ("Compatibility", "Совместимость")
        case .compatibilityWarning: return ("Compatibility may affect search or password fields if the app does not identify them. Fields explicitly marked as secure remain blocked.", "Режим совместимости может затронуть поиск или пароль, если приложение не сообщает тип поля. Поля, явно помеченные как защищённые, остаются заблокированы.")
        case .addApplication: return ("Add Application…", "Добавить приложение…")
        case .removeApplication: return ("Remove application", "Удалить приложение")
        case .invalidApplication: return ("Choose a macOS app with a bundle identifier.", "Выберите приложение macOS с идентификатором пакета.")
        }
    }

    public func localized(_ language: DisplayLanguage, _ arguments: CVarArg...) -> String {
        let format = language == .russian ? translations.russian : translations.english
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }

    public static func diagnostic(_ message: String, in language: DisplayLanguage) -> String {
        if message.contains("\n") {
            return message.components(separatedBy: "\n").map { diagnostic($0, in: language) }.joined(separator: "\n")
        }
        for key in [
            Self.eventMonitorNotRunning, .unableToStartKeyboardMonitor, .unableToSaveLearnedRule,
            .eventMonitorStopped, .matchingInputSourceUnavailable,
            .russianInputSourceUnavailable, .englishInputSourceUnavailable, .unableToPostReplacementEvents,
            .replacementInterrupted, .undoReplacementInterrupted, .dictionaryStorageUnavailable,
            .bundledFrequencyDictionariesUnavailable,
            .builtInComputerTermsUnavailable
        ] where message == key.localized(.english) {
            return key.localized(language)
        }
        for (prefix, key) in [
            ("Disabled unreadable dictionary pack: ", Self.disabledUnreadableDictionary),
            ("Disabled corrupt dictionary pack: ", .disabledCorruptDictionary)
        ] where message.hasPrefix(prefix) {
            return key.localized(language, String(message.dropFirst(prefix.count)))
        }
        return language == .russian ? Self.errorWithDetail.localized(language, message) : message
    }
}

enum InterfaceStatus: Equatable {
    case imported(String)
    case importFailed(String)
    case updateDictionaryFailed(String)
    case removeDictionaryFailed(String)
    case removeRuleFailed(String)
    case removeRulesFailed(String)

    func localized(_ language: DisplayLanguage) -> String {
        switch self {
        case let .imported(name): return InterfaceText.imported.localized(language, name)
        case let .importFailed(detail): return InterfaceText.importFailed.localized(language, detail)
        case let .updateDictionaryFailed(detail): return InterfaceText.updateDictionaryFailed.localized(language, detail)
        case let .removeDictionaryFailed(detail): return InterfaceText.removeDictionaryFailed.localized(language, detail)
        case let .removeRuleFailed(detail): return InterfaceText.removeRuleFailed.localized(language, detail)
        case let .removeRulesFailed(detail): return InterfaceText.removeRulesFailed.localized(language, detail)
        }
    }
}
