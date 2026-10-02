public enum InputEvent: Equatable, Sendable {
    case character(Character)
    case boundary(String)
    case punctuation(text: String, english: String, russian: String)
    case backspace
    case reset
    case synthetic
}

public struct CorrectionPair: Equatable, Sendable {
    public let source: String
    public let candidate: String

    public init(source: String, candidate: String) {
        self.source = source
        self.candidate = candidate
    }
}

public struct BufferedCandidate: Equatable, Sendable {
    public let text: String
    public let physicalKeyCount: Int

    public init(text: String, physicalKeyCount: Int) {
        self.text = text
        self.physicalKeyCount = physicalKeyCount
    }
}

public enum PhraseBufferResult: Equatable, Sendable {
    case buffered
    case candidates([BufferedCandidate], delimiter: String)
    case emptyBoundary(String)
    case blockedBoundary(String)
    case cleared
}

public enum PhraseBufferDisposition: Equatable, Sendable {
    case deferForPhrase(BufferedCandidate)
    case discard
    case corrected
}
