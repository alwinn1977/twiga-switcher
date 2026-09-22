public enum Language: Equatable, Sendable { case english, russian }

public protocol WordLexicon: FrequencyLexicon {
    func contains(_ word: String, language: Language) -> Bool
}

public extension WordLexicon {
    func lookup(_ text: String, language: Language) -> LexiconMatch {
        LexiconMatch(
            score: contains(text, language: language) ? 3_000 : nil,
            isSubjectTerm: false,
            isStrictPrefix: false
        )
    }
}
