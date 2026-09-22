import CoreGraphics

public protocol EventPosting: AnyObject {
    var isAvailable: Bool { get }
    func postBackspaces(count: Int) -> Bool
    func postUnicode(_ text: String) -> Bool
}

public final class EventPoster: EventPosting {
    public static let syntheticMarker: Int64 = 0x4C535743
    private let source = CGEventSource(stateID: .hidSystemState)
    public init() {}

    public var isAvailable: Bool { source != nil }

    public func postBackspaces(count: Int) -> Bool {
        guard let source else { return false }
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) else { return false }
            post(down); post(up)
        }
        return true
    }

    public func postUnicode(_ text: String) -> Bool {
        guard let source,
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return false }
        let units = Array(text.utf16)
        units.withUnsafeBufferPointer {
            down.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
            up.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
        }
        post(down); post(up)
        return true
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }
}
