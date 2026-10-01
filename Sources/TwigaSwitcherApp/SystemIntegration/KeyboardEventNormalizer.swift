import CoreGraphics
import TwigaSwitcherCore

public struct RawKeyEvent: Sendable {
    public let text: String
    public let keyCode: CGKeyCode
    public let flags: CGEventFlags
    public let marker: Int64

    public init(text: String, keyCode: CGKeyCode, flags: CGEventFlags, marker: Int64) {
        self.text = text; self.keyCode = keyCode; self.flags = flags; self.marker = marker
    }
}

public struct KeyboardEventNormalizer: Sendable {
    private let syntheticMarker: Int64
    public init(syntheticMarker: Int64) { self.syntheticMarker = syntheticMarker }

    public func normalize(_ event: RawKeyEvent) -> InputEvent {
        normalize(event, tables: nil)
    }

    func normalize(_ event: RawKeyEvent, tables: KeyboardLayoutTables?, currentLayout: KeyboardLayout? = nil) -> InputEvent {
        if event.marker == syntheticMarker { return .synthetic }
        if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { return .reset }
        if event.keyCode == 51 { return .backspace }
        if event.keyCode == 36 || event.keyCode == 76 { return .boundary("\n") }
        if let tables {
            let shifted = event.flags.contains(.maskShift)
            let capsLocked = event.flags.contains(.maskAlphaShift)
            let english = tables.text(keyCode: event.keyCode, shifted: shifted, capsLocked: capsLocked, layout: .english)
            let russian = tables.text(keyCode: event.keyCode, shifted: shifted, capsLocked: capsLocked, layout: .russian)
            var text = event.text
            // A physical event's Unicode payload can retain the previous layout
            // while AppKit translates its keycode in the current layout. Only
            // reconcile known layout glyphs; preserve composed/custom Unicode.
            if let currentLayout,
               [english, russian].compactMap({ $0 }).contains(text),
               let translated = currentLayout == .english ? english : russian {
                text = translated
            }
            if let english, let russian,
               english != russian, english.count == 1, russian.count == 1,
               [english, russian].contains(text),
               (!english.first!.isLetter || !russian.first!.isLetter),
               [english, russian].contains(where: { ".,!?;:".contains($0) }) {
                return .punctuation(text: text, english: english, russian: russian)
            }
            return plainInput(text)
        }
        // Fallback for callers without system layout tables (e.g. core fixtures).
        let shifted = event.flags.contains(.maskShift)
        let punctuation: (String, String)?
        switch (event.keyCode, shifted) {
        case (44, false): punctuation = ("/", ".")
        case (44, true): punctuation = ("?", ",")
        case (26, true): punctuation = ("&", "?")
        case (21, true): punctuation = ("$", ";")
        case (22, true): punctuation = ("^", ":")
        case (47, false) where event.text == "ю": punctuation = (".", "ю")
        case (43, false) where event.text == "б": punctuation = (",", "б")
        case (41, false) where event.text == "ж": punctuation = (";", "ж")
        case (41, true) where event.text == "Ж": punctuation = (":", "Ж")
        default: punctuation = nil
        }
        if let (english, russian) = punctuation, [english, russian].contains(event.text) {
            return .punctuation(text: event.text, english: english, russian: russian)
        }
        return plainInput(event.text)
    }

    private func plainInput(_ text: String) -> InputEvent {
        if text == " " || text == "\n" || (!text.isEmpty && ".,!?;:()}".contains(text)) {
            return .boundary(text)
        }
        guard text.count == 1, let character = text.first else { return .reset }
        return .character(character)
    }
}
