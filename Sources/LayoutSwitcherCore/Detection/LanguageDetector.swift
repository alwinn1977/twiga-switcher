public enum CorrectionDecision: Equatable, Sendable {
    case unchanged
    case deferred
    case correct(text: String, targetLayout: KeyboardLayout)
}

struct CorrectionEvaluation: Sendable {
    let decision: CorrectionDecision
    let offersManualCorrection: Bool
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
        evaluate(original: original, conversion: conversion).decision
    }

    func evaluate(original: String, conversion: LayoutConversion) -> CorrectionEvaluation {
        let original = TermNormalizer.normalize(original)
        let candidate = TermNormalizer.normalize(conversion.text)
        let originalLanguage: Language = conversion.targetLayout == .russian ? .english : .russian
        let targetLanguage: Language = conversion.targetLayout == .russian ? .russian : .english

        switch rules.disposition(source: original, candidate: candidate) {
        case .never:
            return .init(decision: .unchanged, offersManualCorrection: true)
        case .always:
            return .init(
                decision: .correct(text: conversion.text, targetLayout: conversion.targetLayout),
                offersManualCorrection: true
            )
        case nil:
            break
        }

        let originalMatch = lexicon.lookup(original, language: originalLanguage)
        let candidateMatch = lexicon.lookup(candidate, language: targetLanguage)
        let originalScore = adjustedScore(originalMatch)
        let candidateScore = adjustedScore(candidateMatch)
        if originalMatch.isStrictPrefix || candidateMatch.isStrictPrefix {
            return .init(
                decision: .deferred,
                offersManualCorrection: !(originalScore != nil && candidateScore == nil)
            )
        }

        guard let candidateScore,
              candidateScore >= Self.minimumTargetScore else {
            return .init(
                decision: .unchanged,
                offersManualCorrection: originalScore == nil
            )
        }
        if let originalScore,
           candidateScore - originalScore < Self.ambiguityMargin {
            return .init(decision: .unchanged, offersManualCorrection: true)
        }
        return .init(
            decision: .correct(text: conversion.text, targetLayout: conversion.targetLayout),
            offersManualCorrection: true
        )
    }

    private func adjustedScore(_ match: LexiconMatch) -> Int? {
        guard let score = match.score else { return nil }
        return score + (match.isSubjectTerm ? Self.subjectBoost : 0)
    }
}
