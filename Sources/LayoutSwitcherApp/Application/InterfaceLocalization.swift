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

    private var translations: (english: String, russian: String) {
        switch self {
        case .automaticCorrectionActive: return ("Automatic correction is active", "Автокоррекция включена")
        case .automaticCorrectionPaused: return ("Automatic correction is paused", "Автокоррекция приостановлена")
        case .permissionsRequired: return ("Permissions required", "Требуются разрешения")
        case .enableAutomaticCorrection: return ("Enable Automatic Correction", "Включить автокоррекцию")
        case .requestPermissions: return ("Request Required Permissions", "Запросить разрешения")
        case .openPrivacySettings: return ("Open Privacy Settings", "Открыть настройки конфиденциальности")
        case .restartMonitor: return ("Restart Monitor", "Перезапустить перехват клавиш")
        case .dictionaries: return ("Dictionaries", "Словари")
        case .rules: return ("Rules", "Правила")
        case .settings: return ("Settings", "Настройки")
        case .dictionariesMenu: return ("Dictionaries…", "Словари…")
        case .rulesMenu: return ("Rules…", "Правила…")
        case .settingsMenu: return ("Settings…", "Настройки…")
        case .quit: return ("Quit LayoutSwitcher", "Завершить LayoutSwitcher")
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
        case .modifiers: return ("Modifiers", "Модификаторы")
        case .key: return ("Key", "Клавиша")
        case .space: return ("Space", "Пробел")
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
        case .englishInputSourceUnavailable: return ("English input source is unavailable", "Английская раскладка недоступна")
        case .unableToPostReplacementEvents: return ("Unable to post replacement events", "Не удалось отправить события исправления")
        case .replacementInterrupted: return ("Replacement was interrupted", "Исправление прервано")
        case .undoReplacementInterrupted: return ("Undo replacement was interrupted", "Отмена исправления прервана")
        case .dictionaryStorageUnavailable: return ("Dictionary storage is unavailable", "Хранилище словарей недоступно")
        case .bundledFrequencyDictionariesUnavailable: return ("Bundled frequency dictionaries are unavailable or corrupt", "Встроенные частотные словари недоступны или повреждены")
        case .builtInComputerTermsUnavailable: return ("Built-in Computer Terms dictionary is unavailable", "Встроенный словарь компьютерных терминов недоступен")
        case .disabledUnreadableDictionary: return ("Disabled unreadable dictionary pack: %@", "Отключён нечитаемый пакет словаря: %@")
        case .disabledCorruptDictionary: return ("Disabled corrupt dictionary pack: %@", "Отключён повреждённый пакет словаря: %@")
        case .errorWithDetail: return ("Error: %@", "Ошибка: %@")
        }
    }

    public func localized(_ language: DisplayLanguage, _ arguments: CVarArg...) -> String {
        let format = language == .russian ? translations.russian : translations.english
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }

    public static func diagnostic(_ message: String, in language: DisplayLanguage) -> String {
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
