public enum InputEvent: Equatable, Sendable {
    case character(Character)
    case boundary(String)
    case backspace
    case reset
    case synthetic
}
