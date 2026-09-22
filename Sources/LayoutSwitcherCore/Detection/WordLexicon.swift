public enum Language: Equatable, Sendable { case english, russian }

public protocol WordLexicon: Sendable {
    func contains(_ word: String, language: Language) -> Bool
}
