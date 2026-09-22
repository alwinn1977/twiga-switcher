public struct InputPipeline<Lexicon: FrequencyLexicon, Rules: UserCorrectionRuleLookingUp>: Sendable {
    private var buffer = PhraseBuffer()
    private let converter: LayoutConverter
    private let detector: LanguageDetector<Lexicon, Rules>
    public private(set) var latestDecisionPair: CorrectionPair?

    public init(converter: LayoutConverter, detector: LanguageDetector<Lexicon, Rules>) {
        self.converter = converter; self.detector = detector
    }

    public var hasPendingText: Bool { buffer.hasPendingText }

    public mutating func handle(_ event: InputEvent, focusIsSafe: Bool) -> PipelineOutcome {
        guard event != .synthetic else { return .passThrough }
        latestDecisionPair = nil
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
            let pair = CorrectionPair(source: candidate.text, candidate: conversion.text)
            let evaluation = detector.evaluate(original: candidate.text, conversion: conversion)
            switch evaluation.decision {
            case let .correct(text, layout):
                latestDecisionPair = pair
                buffer.resolve(result, disposition: .corrected)
                return .replace(.init(
                    deleteKeyCount: candidate.physicalKeyCount,
                    replacement: text,
                    delimiter: delimiter,
                    targetLayout: layout
                ))
            case .deferred:
                if evaluation.offersManualCorrection {
                    latestDecisionPair = pair
                }
                buffer.resolve(result, disposition: .deferForPhrase(candidate))
                return .passThrough
            case .unchanged:
                if latestDecisionPair == nil, evaluation.offersManualCorrection {
                    latestDecisionPair = pair
                }
                continue
            }
        }
        buffer.resolve(result, disposition: .discard)
        return .passThrough
    }

    public mutating func reset() {
        _ = buffer.handle(.reset)
        latestDecisionPair = nil
    }
}
