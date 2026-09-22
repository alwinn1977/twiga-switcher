public enum CorrectionDecision: Equatable, Sendable {
    case unchanged
    case correct(text: String, targetLayout: KeyboardLayout)
}

public struct LanguageDetector<Lexicon: WordLexicon>: Sendable {
    private let lexicon: Lexicon
    private let allowlist: Set<String>

    public init(lexicon: Lexicon, allowlist: Set<String>) {
        self.lexicon = lexicon
        self.allowlist = Set(allowlist.map { $0.lowercased() })
    }

    public func decision(original: String, conversion: LayoutConversion) -> CorrectionDecision {
        let original = original.lowercased()
        let candidate = conversion.text.lowercased()
        guard !allowlist.contains(original) else { return .unchanged }
        let originalLanguage: Language = conversion.targetLayout == .russian ? .english : .russian
        let targetLanguage: Language = conversion.targetLayout == .russian ? .russian : .english
        guard !lexicon.contains(original, language: originalLanguage),
              lexicon.contains(candidate, language: targetLanguage) else { return .unchanged }
        return .correct(text: conversion.text, targetLayout: conversion.targetLayout)
    }
}
