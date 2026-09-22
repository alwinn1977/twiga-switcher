public struct LexiconMatch: Equatable, Sendable {
    public let score: Int?
    public let isSubjectTerm: Bool
    public let isStrictPrefix: Bool

    public init(score: Int?, isSubjectTerm: Bool, isStrictPrefix: Bool) {
        self.score = score
        self.isSubjectTerm = isSubjectTerm
        self.isStrictPrefix = isStrictPrefix
    }

    public static let missing = LexiconMatch(
        score: nil,
        isSubjectTerm: false,
        isStrictPrefix: false
    )
}

public protocol FrequencyLexicon: Sendable {
    var maximumPhraseWords: Int { get }
    func lookup(_ text: String, language: Language) -> LexiconMatch
}

public extension FrequencyLexicon {
    var maximumPhraseWords: Int { 1 }
}
