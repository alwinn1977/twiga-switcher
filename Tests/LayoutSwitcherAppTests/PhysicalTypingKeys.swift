import CoreGraphics
import LayoutSwitcherCore

struct PhysicalStroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let expectedLanguage: KeyboardLayout
}

enum PhysicalTypingKeys {
    // ABC and RussianWin glyphs at the same physical key positions.
    private static let positions: [(CGKeyCode, Character, Character)] = [
        (50, "`", "ё"), (12, "q", "й"), (13, "w", "ц"), (14, "e", "у"), (15, "r", "к"),
        (17, "t", "е"), (16, "y", "н"), (32, "u", "г"), (34, "i", "ш"), (31, "o", "щ"),
        (35, "p", "з"), (33, "[", "х"), (30, "]", "ъ"), (0, "a", "ф"), (1, "s", "ы"),
        (2, "d", "в"), (3, "f", "а"), (5, "g", "п"), (4, "h", "р"), (38, "j", "о"),
        (40, "k", "л"), (37, "l", "д"), (41, ";", "ж"), (39, "'", "э"), (6, "z", "я"),
        (7, "x", "ч"), (8, "c", "с"), (9, "v", "м"), (11, "b", "и"), (45, "n", "т"),
        (46, "m", "ь"), (43, ",", "б"), (47, ".", "ю")
    ]

    static func stroke(for intended: Character, language: KeyboardLayout) -> PhysicalStroke? {
        if intended == " " { return .init(keyCode: 49, flags: [], expectedLanguage: language) }
        if intended == "\n" { return .init(keyCode: 36, flags: [], expectedLanguage: language) }
        if intended == "+" { return .init(keyCode: 24, flags: .maskShift, expectedLanguage: language) }
        let shiftedSigns: [(CGKeyCode, Character, Character)] = [
            (18, "!", "!"), (21, "$", ";"), (22, "^", ":"),
            (26, "&", "?"), (25, "(", "("), (29, ")", ")")
        ]
        if let sign = shiftedSigns.first(where: { (language == .english ? $0.1 : $0.2) == intended }) {
            return .init(keyCode: sign.0, flags: .maskShift, expectedLanguage: language)
        }
        if language == .english && intended == "?" {
            return .init(keyCode: 44, flags: .maskShift, expectedLanguage: language)
        }
        if language == .english && intended == ":" {
            return .init(keyCode: 41, flags: .maskShift, expectedLanguage: language)
        }
        if language == .russian && intended == "." {
            return .init(keyCode: 44, flags: [], expectedLanguage: language)
        }
        if language == .russian && intended == "," {
            return .init(keyCode: 44, flags: .maskShift, expectedLanguage: language)
        }
        let lower = Character(String(intended).lowercased())
        guard let position = positions.first(where: {
            language == .english ? $0.1 == lower : $0.2 == lower
        }) else { return nil }
        let flags: CGEventFlags = String(intended) == String(lower) ? [] : .maskShift
        return .init(keyCode: position.0, flags: flags, expectedLanguage: language)
    }

    static func render(_ stroke: PhysicalStroke, in activeLayout: KeyboardLayout) -> String {
        if stroke.keyCode == 49 { return " " }
        if stroke.keyCode == 36 { return "\n" }
        if stroke.keyCode == 24 && stroke.flags.contains(.maskShift) { return "+" }
        if stroke.flags.contains(.maskShift) {
            switch stroke.keyCode {
            case 18: return "!"
            case 21: return activeLayout == .english ? "$" : ";"
            case 22: return activeLayout == .english ? "^" : ":"
            case 26: return activeLayout == .english ? "&" : "?"
            case 25: return "("
            case 29: return ")"
            case 41: return activeLayout == .english ? ":" : "Ж"
            default: break
            }
        }
        if stroke.keyCode == 44 {
            if activeLayout == .russian { return stroke.flags.contains(.maskShift) ? "," : "." }
            return stroke.flags.contains(.maskShift) ? "?" : "/"
        }
        guard let position = positions.first(where: { $0.0 == stroke.keyCode }) else { return "\u{FFFD}" }
        let character = activeLayout == .english ? position.1 : position.2
        return stroke.flags.contains(.maskShift) ? String(character).uppercased() : String(character)
    }

    static func rawKeys(
        for word: String,
        intendedLayout: KeyboardLayout,
        activeLayout: KeyboardLayout
    ) -> String {
        word.map { character in
            guard let stroke = stroke(for: character, language: intendedLayout) else { return "\u{FFFD}" }
            return render(stroke, in: activeLayout)
        }.joined()
    }
}
