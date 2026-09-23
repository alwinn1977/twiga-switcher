public struct InputPipeline<Lexicon: FrequencyLexicon, Rules: UserCorrectionRuleLookingUp>: Sendable {
    private struct RecentWord: Sendable {
        let candidate: BufferedCandidate
        let delimiter: String
    }

    private var buffer = PhraseBuffer()
    private var recentWord: RecentWord?
    private let converter: LayoutConverter
    private let detector: LanguageDetector<Lexicon, Rules>
    public private(set) var latestDecisionPair: CorrectionPair?

    public init(converter: LayoutConverter, detector: LanguageDetector<Lexicon, Rules>) {
        self.converter = converter; self.detector = detector
    }

    public var hasPendingText: Bool { buffer.hasPendingText }
    public var hasRecentWord: Bool { recentWord != nil }
    public var hasCurrentWord: Bool { buffer.currentWord != nil }

    public mutating func handle(_ event: InputEvent, focusIsSafe: Bool) -> PipelineOutcome {
        guard event != .synthetic else { return .passThrough }
        latestDecisionPair = nil
        recentWord = nil
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
                if let last = candidates.last {
                    recentWord = RecentWord(candidate: last, delimiter: delimiter)
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
        if let last = candidates.last {
            recentWord = RecentWord(candidate: last, delimiter: delimiter)
        }
        buffer.resolve(result, disposition: .discard)
        return .passThrough
    }

    public mutating func forceCorrection(focusIsSafe: Bool) -> PipelineOutcome {
        guard focusIsSafe else { return .passThrough }
        let candidate: BufferedCandidate
        let delimiter: String
        if let current = buffer.currentWord {
            candidate = current
            delimiter = ""
        } else if let recentWord {
            candidate = recentWord.candidate
            delimiter = recentWord.delimiter
        } else {
            return .passThrough
        }
        guard let conversion = converter.convert(candidate.text) else { return .passThrough }
        reset()
        latestDecisionPair = CorrectionPair(source: candidate.text, candidate: conversion.text)
        return .replace(.init(
            deleteKeyCount: candidate.physicalKeyCount + delimiter.count,
            replacement: conversion.text,
            delimiter: delimiter,
            targetLayout: conversion.targetLayout
        ))
    }

    public mutating func reset() {
        _ = buffer.handle(.reset)
        recentWord = nil
        latestDecisionPair = nil
    }
}
