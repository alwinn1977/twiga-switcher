public struct BufferedWord: Equatable, Sendable {
    public let text: String
    public let physicalKeyCount: Int

    public init(text: String, physicalKeyCount: Int) {
        self.text = text
        self.physicalKeyCount = physicalKeyCount
    }
}

public enum WordBufferResult: Equatable, Sendable {
    case buffered
    case completed(BufferedWord, delimiter: String)
    case emptyBoundary(String)
    case blockedBoundary(String)
    case cleared
}

public struct WordBuffer: Sendable {
    private enum Script: Sendable {
        case latin
        case cyrillic
    }

    private enum State: Sendable {
        case idle
        case collecting(text: String, keyCount: Int, script: Script)
        case blocked
    }

    private var state: State = .idle

    public init() {}

    public mutating func handle(_ event: InputEvent) -> WordBufferResult {
        switch event {
        case let .character(character):
            append(character)
            return .buffered

        case let .boundary(delimiter):
            defer { state = .idle }
            switch state {
            case .idle:
                return .emptyBoundary(delimiter)
            case let .collecting(text, keyCount, _):
                return .completed(
                    BufferedWord(text: text, physicalKeyCount: keyCount),
                    delimiter: delimiter
                )
            case .blocked:
                return .blockedBoundary(delimiter)
            }

        case .backspace:
            removeLastCharacter()
            return .buffered

        case .reset:
            state = .idle
            return .cleared

        case .synthetic:
            return .buffered
        }
    }

    private mutating func append(_ character: Character) {
        guard let characterScript = script(of: character) else {
            state = .blocked
            return
        }

        switch state {
        case .idle:
            state = .collecting(text: String(character), keyCount: 1, script: characterScript)
        case let .collecting(text, keyCount, script) where script == characterScript:
            state = .collecting(
                text: text + String(character),
                keyCount: keyCount + 1,
                script: script
            )
        case .collecting, .blocked:
            state = .blocked
        }
    }

    private mutating func removeLastCharacter() {
        guard case let .collecting(text, keyCount, script) = state else {
            return
        }

        var shortened = text
        shortened.removeLast()
        if shortened.isEmpty {
            state = .idle
        } else {
            state = .collecting(text: shortened, keyCount: keyCount - 1, script: script)
        }
    }

    private func script(of character: Character) -> Script? {
        let lowered = String(character).lowercased()
        guard lowered.count == 1, let scalar = lowered.unicodeScalars.first,
              lowered.unicodeScalars.count == 1 else {
            return nil
        }

        switch scalar.value {
        case 0x61...0x7A:
            return .latin
        case 0x430...0x44F, 0x451:
            return .cyrillic
        default:
            return nil
        }
    }
}
