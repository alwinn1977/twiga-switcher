public enum KeyboardLayout: String, Equatable, Sendable {
    case english
    case russian
}

public struct LayoutConversion: Equatable, Sendable {
    public let text: String
    public let targetLayout: KeyboardLayout

    public init(text: String, targetLayout: KeyboardLayout) {
        self.text = text
        self.targetLayout = targetLayout
    }
}
