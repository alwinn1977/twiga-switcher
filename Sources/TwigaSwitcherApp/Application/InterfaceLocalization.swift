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

public enum InterfaceText: String, CaseIterable, Sendable {
    case automaticCorrectionActive, automaticCorrectionPaused, permissionsRequired
    case enableAutomaticCorrection, requestPermissions, openPrivacySettings, restartMonitor
    case dictionaries, rules, settings, dictionariesMenu, rulesMenu, settingsMenu, quit
    case about, aboutDescription, aboutVersion, aboutBuild
    case aboutLicense, aboutLicenseNotice
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
    case uncheckedMode, uncheckedWarning
    case addApplication, removeApplication, invalidApplication

    public func localized(_ language: DisplayLanguage, _ arguments: CVarArg...) -> String {
        let format = InterfaceStringResources.bundled.localizedString(forKey: "interface.\(rawValue)", in: language)
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
        for key in [Self.disabledUnreadableDictionary, .disabledCorruptDictionary] {
            let format = key.localized(.english)
            guard let placeholder = format.range(of: "%@") else { continue }
            let prefix = String(format[..<placeholder.lowerBound])
            let suffix = String(format[placeholder.upperBound...])
            guard message.hasPrefix(prefix), message.hasSuffix(suffix),
                  message.count >= prefix.count + suffix.count else { continue }
            return key.localized(language, String(message.dropFirst(prefix.count).dropLast(suffix.count)))
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
