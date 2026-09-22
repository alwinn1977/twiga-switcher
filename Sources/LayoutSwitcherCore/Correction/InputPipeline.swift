public struct InputPipeline<Lexicon: WordLexicon>: Sendable {
    private var buffer = WordBuffer()
    private let converter: LayoutConverter
    private let detector: LanguageDetector<Lexicon>

    public init(converter: LayoutConverter, detector: LanguageDetector<Lexicon>) {
        self.converter = converter; self.detector = detector
    }

    public mutating func handle(_ event: InputEvent, focusIsSafe: Bool) -> PipelineOutcome {
        guard event != .synthetic else { return .passThrough }
        let result = buffer.handle(event)
        guard case let .completed(word, delimiter) = result, focusIsSafe,
              let conversion = converter.convert(word.text) else { return .passThrough }
        guard case let .correct(text, layout) = detector.decision(original: word.text, conversion: conversion) else { return .passThrough }
        return .replace(.init(deleteKeyCount: word.physicalKeyCount, replacement: text, delimiter: delimiter, targetLayout: layout))
    }

    public mutating func reset() { _ = buffer.handle(.reset) }
}
