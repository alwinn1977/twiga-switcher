public enum CorrectionDecision: Equatable, Sendable {
    case unchanged
    case deferred
    case correct(text: String, targetLayout: KeyboardLayout)
}

public struct LanguageDetector<Lexicon: FrequencyLexicon, Rules: UserCorrectionRuleLookingUp>: Sendable {
    private static var minimumTargetScore: Int { 2_500 }
    private static var ambiguityMargin: Int { 1_000 }
    private static var subjectBoost: Int { 1_500 }

    private let lexicon: Lexicon
    private let rules: Rules

    public init(lexicon: Lexicon, rules: Rules) {
        self.lexicon = lexicon
        self.rules = rules
    }

    public func decision(original: String, conversion: LayoutConversion) -> CorrectionDecision {
        let original = TermNormalizer.normalize(original)
        let candidate = TermNormalizer.normalize(conversion.text)
        let originalLanguage: Language = conversion.targetLayout == .russian ? .english : .russian
        let targetLanguage: Language = conversion.targetLayout == .russian ? .russian : .english

        switch rules.disposition(source: original, candidate: candidate) {
        case .never:
            return .unchanged
        case .always:
            return .correct(text: conversion.text, targetLayout: conversion.targetLayout)
        case nil:
            break
        }

        let originalMatch = lexicon.lookup(original, language: originalLanguage)
        let candidateMatch = lexicon.lookup(candidate, language: targetLanguage)
        if originalMatch.isStrictPrefix || candidateMatch.isStrictPrefix {
            return .deferred
        }

        guard let candidateScore = adjustedScore(candidateMatch),
              candidateScore >= Self.minimumTargetScore else {
            return .unchanged
        }
        if let originalScore = adjustedScore(originalMatch),
           candidateScore - originalScore < Self.ambiguityMargin {
            return .unchanged
        }
        return .correct(text: conversion.text, targetLayout: conversion.targetLayout)
    }

    private func adjustedScore(_ match: LexiconMatch) -> Int? {
        guard let score = match.score else { return nil }
        return score + (match.isSubjectTerm ? Self.subjectBoost : 0)
    }
}
