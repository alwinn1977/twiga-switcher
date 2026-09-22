public struct LayoutConverter: Sendable {
    private static let english = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,.")
    private static let russian = Array("ёйцукенгшщзхъфывапролджэячсмитьбю")
    private static let englishToRussian = Dictionary(uniqueKeysWithValues: zip(english, russian))
    private static let russianToEnglish = Dictionary(uniqueKeysWithValues: zip(russian, english))

    public init() {}

    public func convert(_ source: String) -> LayoutConversion? {
        guard !source.isEmpty else { return nil }

        var sourceLayout: KeyboardLayout?
        var result = ""

        for character in source {
            let loweredText = String(character).lowercased()
            guard loweredText.count == 1, let lowered = loweredText.first else {
                return nil
            }

            let mapped: Character
            let characterLayout: KeyboardLayout

            if let value = Self.englishToRussian[lowered] {
                mapped = value
                characterLayout = .english
            } else if let value = Self.russianToEnglish[lowered] {
                mapped = value
                characterLayout = .russian
            } else {
                return nil
            }

            guard sourceLayout == nil || sourceLayout == characterLayout else {
                return nil
            }

            sourceLayout = characterLayout
            let isUppercase = String(character) != loweredText
                && String(character) == String(character).uppercased()
            result += isUppercase ? String(mapped).uppercased() : String(mapped)
        }

        let targetLayout: KeyboardLayout = sourceLayout == .english ? .russian : .english
        return LayoutConversion(text: result, targetLayout: targetLayout)
    }
}
