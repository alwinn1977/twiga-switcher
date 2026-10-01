public struct InputPipeline<Lexicon: FrequencyLexicon, Rules: UserCorrectionRuleLookingUp>: Sendable {
    private struct RecentWord: Sendable {
        let candidate: BufferedCandidate
        let delimiter: String
    }

    private var buffer = PhraseBuffer()
    private var recentWord: RecentWord?
    private var converter: LayoutConverter
    private let detector: LanguageDetector<Lexicon, Rules>
    public private(set) var latestDecisionPair: CorrectionPair?

    public init(converter: LayoutConverter, detector: LanguageDetector<Lexicon, Rules>) {
        self.converter = converter; self.detector = detector
    }

    public var hasPendingText: Bool { buffer.hasPendingText }
    public var hasRecentWord: Bool { recentWord != nil }
    public var hasCurrentWord: Bool { buffer.currentWord != nil }

    public func wouldCorrectWhileTyping(_ event: InputEvent) -> Bool {
        guard case .character = event else { return false }
        var preview = buffer
        _ = preview.handle(event)
        return liveConversion(in: preview) != nil
    }

    private func liveConversion(in buffer: PhraseBuffer) -> (BufferedCandidate, LayoutConversion)? {
        guard let word = buffer.unfinishedWord,
              let conversion = converter.convert(word.text),
              detector.shouldCorrectWhileTyping(original: word.text, conversion: conversion) else { return nil }
        return (word, conversion)
    }

    public mutating func handle(_ event: InputEvent, focusIsSafe: Bool) -> PipelineOutcome {
        guard event != .synthetic else { return .passThrough }
        if case let .punctuation(text, english, russian) = event {
            return handlePunctuation(text: text, english: english, russian: russian, focusIsSafe: focusIsSafe)
        }
        latestDecisionPair = nil
        recentWord = nil
        let result = buffer.handle(event)
        if case .character = event, focusIsSafe,
           let (word, conversion) = liveConversion(in: buffer) {
            latestDecisionPair = .init(source: word.text, candidate: conversion.text)
            buffer.replaceUnfinishedWord(with: conversion.text)
            // The triggering key has not reached the editor and will be suppressed.
            return .replace(.init(deleteKeyCount: word.physicalKeyCount - 1,
                                  replacement: conversion.text, delimiter: "",
                                  targetLayout: conversion.targetLayout))
        }
        guard case let .candidates(candidates, delimiter) = result else {
            return .passThrough
        }
        guard focusIsSafe else {
            buffer.resolve(result, disposition: .discard)
            return .passThrough
        }

        if [".", ",", ";"].contains(delimiter),
           let longest = candidates.first,
           let last = candidates.last {
            recentWord = RecentWord(candidate: last, delimiter: delimiter)
            buffer.resolve(result, disposition: .deferForPhrase(longest))
            return .passThrough
        }

        for candidate in candidates {
            let trailingPunctuation = String(candidate.text.reversed()
                .prefix(while: { ".,;".contains($0) }).reversed())
            let bareText = String(candidate.text.dropLast(trailingPunctuation.count))
            let bareConversion = trailingPunctuation.isEmpty ? nil : converter.convert(bareText)
            if let bareConversion,
               detector.hasAlwaysRule(bareText, conversion: bareConversion),
               case let .correct(text, layout) = detector.decision(
                original: bareText, conversion: bareConversion
               ) {
                latestDecisionPair = .init(source: bareText, candidate: bareConversion.text)
                buffer.resolve(result, disposition: .corrected)
                return .replace(.init(
                    deleteKeyCount: candidate.physicalKeyCount,
                    replacement: text,
                    delimiter: trailingPunctuation + delimiter,
                    targetLayout: layout
                ))
            }
            if let bareConversion,
               detector.hasRecognizedOriginal(bareText, conversion: bareConversion) {
                buffer.resolve(result, disposition: .discard)
                return .passThrough
            }
            if let conversion = converter.convert(candidate.text) {
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
                }
            }
            if let bareConversion,
               case let .correct(text, layout) = detector.decision(
                original: bareText, conversion: bareConversion
               ) {
                latestDecisionPair = .init(source: bareText, candidate: bareConversion.text)
                buffer.resolve(result, disposition: .corrected)
                return .replace(.init(
                    deleteKeyCount: candidate.physicalKeyCount,
                    replacement: text,
                    delimiter: trailingPunctuation + delimiter,
                    targetLayout: layout
                ))
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
            if let recentWord,
               [".", ",", ";"].contains(recentWord.delimiter),
               current.text.hasSuffix(recentWord.candidate.text + recentWord.delimiter) {
                let fullConversion = converter.convert(current.text)
                let fullIsRecognizedCorrection = fullConversion.map {
                    if case .correct = detector.decision(original: current.text, conversion: $0) {
                        return true
                    }
                    return false
                } ?? false
                if fullIsRecognizedCorrection {
                    candidate = current
                    delimiter = ""
                } else {
                    candidate = .init(
                        text: String(current.text.dropLast(recentWord.delimiter.count)),
                        physicalKeyCount: current.physicalKeyCount - recentWord.delimiter.count,
                        tokenCount: current.tokenCount
                    )
                    delimiter = recentWord.delimiter
                }
            } else {
                candidate = current
                delimiter = ""
            }
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

    private mutating func handlePunctuation(
        text: String, english: String, russian: String, focusIsSafe: Bool
    ) -> PipelineOutcome {
        latestDecisionPair = nil
        recentWord = nil
        // A Cyrillic glyph on an English punctuation key may still continue a real word.
        if text.first?.isLetter == true, let word = buffer.currentWord,
           let conversion = converter.convert(word.text + text),
           detector.hasOriginalCompletion(word.text + text, conversion: conversion),
           let character = text.first {
            return handle(.character(character), focusIsSafe: focusIsSafe)
        }
        var preview = buffer
        let result = preview.handle(.boundary(text))
        if focusIsSafe, case let .candidates(candidates, _) = result {
            for word in candidates {
                guard let conversion = converter.convert(word.text),
                      case let .correct(replacement, layout) = detector.decision(
                        original: word.text, conversion: conversion
                      ) else { continue }
                let delimiter = layout == .english ? english : russian
                guard !delimiter.contains(where: { $0.isLetter }) else { continue }
                latestDecisionPair = .init(source: word.text, candidate: conversion.text)
                buffer.resolve(result, disposition: .corrected)
                return .replace(.init(deleteKeyCount: word.physicalKeyCount,
                                      replacement: replacement,
                                      delimiter: delimiter,
                                      targetLayout: layout))
            }
        }
        // A slash can belong to a path; preserve its existing buffering behavior.
        if let character = text.first, text == "/" || character.isLetter {
            return handle(.character(character), focusIsSafe: focusIsSafe)
        }
        return handle(.boundary(text), focusIsSafe: focusIsSafe)
    }

    public mutating func updateConverter(_ converter: LayoutConverter) {
        self.converter = converter
        reset()
    }

    // Keep the text that was actually inserted available to the explicit shortcut.
    public mutating func rememberReplacement(_ plan: ReplacementPlan) {
        _ = buffer.handle(.reset)
        if plan.delimiter.isEmpty {
            for character in plan.replacement { _ = buffer.handle(.character(character)) }
            recentWord = nil
        } else {
            recentWord = RecentWord(candidate: .init(text: plan.replacement,
                physicalKeyCount: plan.replacement.count, tokenCount: 1), delimiter: plan.delimiter)
        }
    }

    public mutating func reset() {
        _ = buffer.handle(.reset)
        recentWord = nil
        latestDecisionPair = nil
    }
}
