import Foundation
import LayoutSwitcherCore

public final class LexiconCatalogSnapshot: @unchecked Sendable, FrequencyLexicon {
    private let baseLexicons: [any FrequencyLexicon]
    private let subjectLexicons: [any FrequencyLexicon]
    public let maximumPhraseWords: Int

    public init(
        baseLexicons: [any FrequencyLexicon],
        subjectLexicons: [any FrequencyLexicon]
    ) {
        self.baseLexicons = baseLexicons
        self.subjectLexicons = subjectLexicons
        self.maximumPhraseWords = (baseLexicons + subjectLexicons)
            .map(\.maximumPhraseWords)
            .max() ?? 1
    }

    public func lookup(_ text: String, language: Language) -> LexiconMatch {
        let subject = aggregate(text, language: language, lexicons: subjectLexicons)
        if let score = subject.score {
            return LexiconMatch(
                score: score,
                isSubjectTerm: true,
                isStrictPrefix: subject.isStrictPrefix
            )
        }

        let base = aggregate(text, language: language, lexicons: baseLexicons)
        return LexiconMatch(
            score: base.score,
            isSubjectTerm: false,
            isStrictPrefix: subject.isStrictPrefix || base.isStrictPrefix
        )
    }

    private func aggregate(
        _ text: String,
        language: Language,
        lexicons: [any FrequencyLexicon]
    ) -> (score: Int?, isStrictPrefix: Bool) {
        var bestScore: Int?
        var isStrictPrefix = false
        for lexicon in lexicons {
            let match = lexicon.lookup(text, language: language)
            if let score = match.score, score > (bestScore ?? Int.min) {
                bestScore = score
            }
            isStrictPrefix = isStrictPrefix || match.isStrictPrefix
        }
        return (bestScore, isStrictPrefix)
    }
}
