public struct InputPipeline<Lexicon: FrequencyLexicon, Rules: UserCorrectionRuleLookingUp>: Sendable {
    private var buffer = PhraseBuffer()
    private let converter: LayoutConverter
    private let detector: LanguageDetector<Lexicon, Rules>

    public init(converter: LayoutConverter, detector: LanguageDetector<Lexicon, Rules>) {
        self.converter = converter; self.detector = detector
    }

    public var hasPendingText: Bool { buffer.hasPendingText }

    public mutating func handle(_ event: InputEvent, focusIsSafe: Bool) -> PipelineOutcome {
        guard event != .synthetic else { return .passThrough }
        let result = buffer.handle(event)
        guard case let .candidates(candidates, delimiter) = result else {
            return .passThrough
        }
        guard focusIsSafe else {
            buffer.resolve(result, disposition: .discard)
            return .passThrough
        }

        for candidate in candidates {
            guard let conversion = converter.convert(candidate.text) else { continue }
            switch detector.decision(original: candidate.text, conversion: conversion) {
            case let .correct(text, layout):
                buffer.resolve(result, disposition: .corrected)
                return .replace(.init(
                    deleteKeyCount: candidate.physicalKeyCount,
                    replacement: text,
                    delimiter: delimiter,
                    targetLayout: layout
                ))
            case .deferred:
                buffer.resolve(result, disposition: .deferForPhrase(candidate))
                return .passThrough
            case .unchanged:
                continue
            }
        }
        buffer.resolve(result, disposition: .discard)
        return .passThrough
    }

    public mutating func reset() { _ = buffer.handle(.reset) }
}
