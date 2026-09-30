import CoreGraphics

public protocol EventPosting: AnyObject {
    var isAvailable: Bool { get }
    func postBackspaces(count: Int) -> Bool
    func postUnicode(_ text: String) -> Bool
}

public final class EventPoster: EventPosting {
    public static let syntheticMarker: Int64 = 0x4C535743
    private let source = CGEventSource(stateID: .hidSystemState)
    private let makeKeyboardEvent: (CGEventSource, CGKeyCode, Bool) -> CGEvent?
    private let sendEvent: (CGEvent) -> Void

    public convenience init() {
        self.init(
            makeKeyboardEvent: { CGEvent(keyboardEventSource: $0, virtualKey: $1, keyDown: $2) },
            sendEvent: { $0.post(tap: .cghidEventTap) }
        )
    }

    init(
        makeKeyboardEvent: @escaping (CGEventSource, CGKeyCode, Bool) -> CGEvent?,
        sendEvent: @escaping (CGEvent) -> Void
    ) {
        self.makeKeyboardEvent = makeKeyboardEvent
        self.sendEvent = sendEvent
    }

    public var isAvailable: Bool { source != nil }

    public func postBackspaces(count: Int) -> Bool {
        guard let source else { return false }
        for _ in 0..<count {
            guard let down = makeKeyboardEvent(source, 51, true),
                  let up = makeKeyboardEvent(source, 51, false) else { return false }
            post(down); post(up)
        }
        return true
    }

    public func postUnicode(_ text: String) -> Bool {
        guard let source,
              let down = makeKeyboardEvent(source, 0, true),
              let up = makeKeyboardEvent(source, 0, false) else { return false }
        let units = Array(text.utf16)
        units.withUnsafeBufferPointer {
            down.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
            up.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
        }
        post(down); post(up)
        return true
    }

    private func post(_ event: CGEvent) {
        // Hotkey modifiers may still be held. Option/Command + Backspace would
        // delete whole words/lines instead of the requested number of characters.
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        sendEvent(event)
    }
}
