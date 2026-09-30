import Foundation

public struct LayoutConverter: Sendable {
    private static let english = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,.")
    private static let russian = Array("ёйцукенгшщзхъфывапролджэячсмитьбю")
    private static let englishToRussian = Dictionary(uniqueKeysWithValues: zip(english, russian))
    private static let russianToEnglish = Dictionary(uniqueKeysWithValues: zip(russian, english))

    private let customEnglishToRussian: [Character: Character]?
    private let customRussianToEnglish: [Character: Character]?

    public init() {
        customEnglishToRussian = nil
        customRussianToEnglish = nil
    }

    public init(englishToRussian: [Character: Character], russianToEnglish: [Character: Character]) {
        customEnglishToRussian = englishToRussian
        customRussianToEnglish = russianToEnglish
    }


    public func convert(_ source: String) -> LayoutConversion? {
        guard !source.isEmpty else { return nil }
        if let forward = customEnglishToRussian, let reverse = customRussianToEnglish {
            let hasRussian = source.unicodeScalars.contains { (0x410...0x44F).contains($0.value) || $0.value == 0x401 || $0.value == 0x451 }
            let hasEnglish = source.unicodeScalars.contains { (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value) }
            guard hasRussian != hasEnglish else { return nil }
            let mapping = hasRussian ? reverse : forward
            var result = ""
            for character in source {
                if let mapped = mapping[character] { result.append(mapped) }
                else if Self.isNeutral(character) { result.append(character) }
                else { return nil }
            }
            return LayoutConversion(text: result, targetLayout: hasRussian ? .english : .russian)
        }

        var sourceLayout: KeyboardLayout?
        var result = ""

        for character in source {
            let loweredText = String(character).lowercased()
            guard loweredText.count == 1, let lowered = loweredText.first else {
                return nil
            }

            let mapped: Character
            let characterLayout: KeyboardLayout?

            if let value = Self.englishToRussian[lowered] {
                mapped = value
                characterLayout = .english
            } else if let value = Self.russianToEnglish[lowered] {
                mapped = value
                characterLayout = .russian
            } else if Self.isNeutral(character) {
                result.append(character)
                continue
            } else {
                return nil
            }

            guard let characterLayout,
                  sourceLayout == nil || sourceLayout == characterLayout else {
                return nil
            }

            sourceLayout = characterLayout
            let isUppercase = String(character) != loweredText
                && String(character) == String(character).uppercased()
            result += isUppercase ? String(mapped).uppercased() : String(mapped)
        }

        guard let sourceLayout else { return nil }
        let targetLayout: KeyboardLayout = sourceLayout == .english ? .russian : .english
        return LayoutConversion(text: result, targetLayout: targetLayout)
    }

    private static func isNeutral(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        return CharacterSet.decimalDigits.contains(scalar)
            || CharacterSet(charactersIn: " +#-_/\\@").contains(scalar)
    }
}
