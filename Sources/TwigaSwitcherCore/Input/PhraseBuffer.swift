import Foundation

public struct PhraseBuffer: Sendable {
    private enum Script: Sendable {
        case latin
        case cyrillic
    }

    private enum CharacterKind: Sendable {
        case letter(Script)
        case neutral
    }

    private let maxTokens: Int
    private let maxScalars: Int
    private var text = ""
    private var script: Script?
    private var isBlocked = false

    public var hasPendingText: Bool { !text.isEmpty && !isBlocked }
    public var currentWord: BufferedCandidate? { makeCandidates().last }
    var unfinishedWord: BufferedCandidate? { text.contains(" ") ? nil : currentWord }

    mutating func replaceUnfinishedWord(with replacement: String) {
        text = replacement
        script = detectedScript(in: text)
    }

    public init(maxTokens: Int = 8, maxScalars: Int = 128) {
        precondition(maxTokens > 0 && maxScalars > 0)
        self.maxTokens = maxTokens
        self.maxScalars = maxScalars
    }

    public mutating func handle(_ event: InputEvent) -> PhraseBufferResult {
        switch event {
        case let .punctuation(text, _, _):
            return handle(.boundary(text))
        case let .character(character):
            append(character)
            return .buffered

        case let .boundary(delimiter):
            if isBlocked {
                clear()
                return .blockedBoundary(delimiter)
            }
            if script == nil,
               text.count < 2,
               text.allSatisfy({ ",.".contains($0) }),
               [",", "."].contains(delimiter) {
                text += delimiter
                enforceLimits()
                return .buffered
            }
            let candidates = makeCandidates()
            guard !candidates.isEmpty else {
                clear()
                return .emptyBoundary(delimiter)
            }
            return .candidates(candidates, delimiter: delimiter)

        case .backspace:
            removeLast()
            return .buffered

        case .reset:
            clear()
            return .cleared

        case .synthetic:
            return .buffered
        }
    }

    public mutating func resolve(
        _ result: PhraseBufferResult,
        disposition: PhraseBufferDisposition
    ) {
        guard case let .candidates(_, delimiter) = result else { return }
        switch disposition {
        case .discard, .corrected:
            clear()

        case let .deferForPhrase(candidate):
            guard text.hasSuffix(candidate.text), canRetain(delimiter: delimiter) else {
                clear()
                return
            }
            text = candidate.text
            script = detectedScript(in: text)
            guard appendDeferredDelimiter(delimiter) else { clear(); return }
            enforceLimits()
        }
    }

    private mutating func append(_ character: Character) {
        guard !isBlocked else { return }
        guard let classification = classify(character) else {
            block()
            return
        }
        if case let .letter(characterScript) = classification {
            if let script, script != characterScript {
                block()
                return
            }
            script = characterScript
        }
        text.append(character)
        enforceLimits()
    }

    private mutating func appendDeferredDelimiter(_ delimiter: String) -> Bool {
        guard delimiter.count == 1 else { return false }
        if delimiter == " " {
            text.append(" ")
            return true
        }
        guard [".", ",", ";"].contains(delimiter),
              text.reversed().prefix(while: { ".,;".contains($0) }).count < 2 else {
            return false
        }
        text += delimiter
        return true
    }

    private func canRetain(delimiter: String) -> Bool {
        delimiter == " " || delimiter == "." || delimiter == "," || delimiter == ";"
    }

    private mutating func removeLast() {
        guard !isBlocked, !text.isEmpty else { return }
        text.removeLast()
        script = detectedScript(in: text)
    }

    private mutating func enforceLimits() {
        let tokenCount = text.split(separator: " ").count
        if text.unicodeScalars.count > maxScalars || tokenCount > maxTokens {
            block()
        }
    }

    private mutating func block() {
        text = ""
        script = nil
        isBlocked = true
    }

    private mutating func clear() {
        text = ""
        script = nil
        isBlocked = false
    }

    private func makeCandidates() -> [BufferedCandidate] {
        guard script != nil, !text.isEmpty, text.last != " " else { return [] }
        var starts = [text.startIndex]
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == " " {
                let next = text.index(after: index)
                if next < text.endIndex { starts.append(next) }
            }
            index = text.index(after: index)
        }
        return starts.map { start in
            let suffix = String(text[start...])
            return BufferedCandidate(
                text: suffix,
                physicalKeyCount: suffix.count,
                tokenCount: suffix.split(separator: " ").count
            )
        }
    }

    private func classify(_ character: Character) -> CharacterKind? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return nil }
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A:
            return .letter(.latin)
        case 0x410...0x44F, 0x401, 0x451:
            return .letter(.cyrillic)
        default:
            let neutral = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "+#-_/\\@'\"`[]"))
            return neutral.contains(scalar) ? .neutral : nil
        }
    }

    private func detectedScript(in value: String) -> Script? {
        for character in value {
            guard let classification = classify(character) else { continue }
            if case let .letter(script) = classification { return script }
        }
        return nil
    }
}
