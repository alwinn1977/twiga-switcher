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

    func shouldCorrectWhileTyping(original: String, conversion: LayoutConversion) -> Bool {
        let source = TermNormalizer.normalize(original)
        let target = TermNormalizer.normalize(conversion.text)
        guard target.count >= 4,
              target.allSatisfy({ $0.isLetter }),
              !rules.preventsEarlyCorrection(source: source, candidate: target) else { return false }
        let sourceLanguage: Language = conversion.targetLayout == .russian ? .english : .russian
        let targetLanguage: Language = conversion.targetLayout == .russian ? .russian : .english
        guard lexicon.lookup(source, language: sourceLanguage).score == nil,
              !lexicon.hasCompletion(for: source, language: sourceLanguage, minimumScore: 0) else { return false }
        return lexicon.hasCompletion(for: target, language: targetLanguage, minimumScore: 4_000)
    }

    func hasRecognizedOriginal(_ original: String, conversion: LayoutConversion) -> Bool {
        let language: Language = conversion.targetLayout == .russian ? .english : .russian
        return lexicon.lookup(TermNormalizer.normalize(original), language: language).score != nil
    }

    func hasOriginalCompletion(_ original: String, conversion: LayoutConversion) -> Bool {
        let language: Language = conversion.targetLayout == .russian ? .english : .russian
        return hasRecognizedOriginal(original, conversion: conversion)
            || lexicon.hasCompletion(for: original, language: language, minimumScore: 0)
    }

    func hasAlwaysRule(_ original: String, conversion: LayoutConversion) -> Bool {
        rules.disposition(
            source: TermNormalizer.normalize(original),
            candidate: TermNormalizer.normalize(conversion.text)
        ) == .always
    }

    func evaluate(original: String, conversion: LayoutConversion) -> CorrectionEvaluation {
        let isLowercaseSingleLetter = original.count == 1 && original.first?.isLowercase == true
            && conversion.text.count == 1 && conversion.text.first?.isLetter == true
        let source = TermNormalizer.normalize(original)
        let candidate = TermNormalizer.normalize(conversion.text)
        let originalLanguage: Language = conversion.targetLayout == .russian ? .english : .russian
        let targetLanguage: Language = conversion.targetLayout == .russian ? .russian : .english

        switch rules.disposition(source: source, candidate: candidate) {
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

        let originalMatch = lexicon.lookup(source, language: originalLanguage)
        let candidateMatch = lexicon.lookup(candidate, language: targetLanguage)
        let originalScore = adjustedScore(originalMatch)
        let candidateScore = adjustedScore(candidateMatch)
        // Lowercase standalone letters use the usual frequency margin. Uppercase
        // initials still wait for context, and dotted abbreviations stay buffered.
        if !isLowercaseSingleLetter && (originalMatch.isStrictPrefix || candidateMatch.isStrictPrefix) {
            return .init(
                decision: .deferred,
                offersManualCorrection: !(originalScore != nil && candidateScore == nil)
            )
        }

        if originalScore == nil, candidateScore == nil,
           let decision = singleLetterPhraseDecision(original: original, conversion: conversion) {
            return .init(decision: decision, offersManualCorrection: true)
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

    private func singleLetterPhraseDecision(original: String, conversion: LayoutConversion) -> CorrectionDecision? {
        let sourceWords = original.split(separator: " ").map(String.init)
        let targetWords = conversion.text.split(separator: " ").map(String.init)
        let prefixCount = targetWords.dropLast().prefix { $0.count == 1 && $0.allSatisfy(\.isLetter) }.count
        guard prefixCount > 0, sourceWords.count == targetWords.count else { return nil }
        let sourceLanguage: Language = conversion.targetLayout == .russian ? .english : .russian
        let targetLanguage: Language = conversion.targetLayout == .russian ? .russian : .english

        // A one-letter word can also prefix an initialism (e.g. B.B).
        // Use the next word as evidence without requiring a dictionary phrase.
        for (sourceWord, targetWord) in zip(sourceWords.prefix(prefixCount), targetWords.prefix(prefixCount)) {
            let source = TermNormalizer.normalize(sourceWord)
            let target = TermNormalizer.normalize(targetWord)
            switch rules.disposition(source: source, candidate: target) {
            case .never: return nil
            case .always: continue
            case nil: break
            }
            guard let targetScore = adjustedScore(lexicon.lookup(target, language: targetLanguage)),
                  targetScore >= Self.minimumTargetScore else { return nil }
            if let sourceScore = adjustedScore(lexicon.lookup(source, language: sourceLanguage)),
               targetScore - sourceScore < Self.ambiguityMargin { return nil }
        }

        let following = evaluate(original: sourceWords.dropFirst(prefixCount).joined(separator: " "), conversion: .init(
            text: targetWords.dropFirst(prefixCount).joined(separator: " "), targetLayout: conversion.targetLayout
        ))
        switch following.decision {
        case .correct:
            return .correct(text: conversion.text, targetLayout: conversion.targetLayout)
        case .deferred:
            return .deferred
        case .unchanged:
            return nil
        }
    }

    private func adjustedScore(_ match: LexiconMatch) -> Int? {
        guard let score = match.score else { return nil }
        return score + (match.isSubjectTerm ? Self.subjectBoost : 0)
    }
}
