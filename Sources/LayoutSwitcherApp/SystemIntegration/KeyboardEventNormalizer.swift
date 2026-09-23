import CoreGraphics
import LayoutSwitcherCore

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
        if event.marker == syntheticMarker { return .synthetic }
        if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { return .reset }
        if event.keyCode == 51 { return .backspace }
        if event.keyCode == 36 || event.keyCode == 76 { return .boundary("\n") }
        if event.text == " " || event.text == "\n" || ".,!?;:".contains(event.text) { return .boundary(event.text) }
        guard event.text.count == 1, let character = event.text.first else { return .reset }
        return .character(character)
    }
}
