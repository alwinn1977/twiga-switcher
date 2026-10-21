public struct InputPipeline<Lexicon: FrequencyLexicon, Rules: UserCorrectionRuleLookingUp>: Sendable {
    private struct RecentWord: Sendable {
        let candidate: BufferedCandidate
        let delimiter: String
    }

    private var buffer = PhraseBuffer()
    private var recentWord: RecentWord?
    private var converter: LayoutConverter
    private let detector: LanguageDetector<Lexicon, Rules>
    private var automaticCorrectionEnabled = true
    public private(set) var latestDecisionPair: CorrectionPair?

    public init(converter: LayoutConverter, detector: LanguageDetector<Lexicon, Rules>) {
        self.converter = converter; self.detector = detector
    }

    public mutating func setAutomaticCorrectionEnabled(_ enabled: Bool) {
        automaticCorrectionEnabled = enabled
        reset()
    }

    public var hasPendingText: Bool { buffer.hasPendingText }
    public var hasRecentWord: Bool { recentWord != nil }
    public var hasCurrentWord: Bool { buffer.currentWord != nil }

    public func wouldCorrectWhileTyping(_ event: InputEvent) -> Bool {
        guard automaticCorrectionEnabled, case .character = event else { return false }
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
        let previousRecentWord = recentWord
        recentWord = nil
        let result = buffer.handle(event)
        if !automaticCorrectionEnabled, case .emptyBoundary(" ") = result,
           let previousRecentWord,
           previousRecentWord.delimiter.allSatisfy({ ".,;".contains($0) }) {
            recentWord = RecentWord(candidate: previousRecentWord.candidate,
                                    delimiter: previousRecentWord.delimiter + " ")
            return .passThrough
        }
        if case .character = event, automaticCorrectionEnabled, focusIsSafe,
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

        guard automaticCorrectionEnabled else {
            if let last = candidates.last {
                recentWord = separatingTrailingPunctuation(from: last, delimiter: delimiter)
            }
            buffer.resolve(result, disposition: .discard)
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
                switch detector.decision(original: candidate.text, conversion: conversion) {
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
                    if let last = candidates.last {
                        recentWord = RecentWord(candidate: last, delimiter: delimiter)
                    }
                    buffer.resolve(result, disposition: .deferForPhrase(candidate))
                    return .passThrough
                case .unchanged:
                    break
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

    private func isRecognizedCorrection(_ text: String) -> Bool {
        guard let conversion = converter.convert(text),
              case .correct = detector.decision(original: text, conversion: conversion) else { return false }
        return true
    }

    private func separatingTrailingPunctuation(from candidate: BufferedCandidate, delimiter: String) -> RecentWord {
        var text = candidate.text
        var punctuation = ""
        while let last = text.last, ".,;".contains(last), !isRecognizedCorrection(text) {
            text.removeLast()
            punctuation.insert(last, at: punctuation.startIndex)
        }
        return RecentWord(candidate: .init(
            text: text, physicalKeyCount: candidate.physicalKeyCount - punctuation.count
        ), delimiter: punctuation + delimiter)
    }

    public mutating func forceCorrection(focusIsSafe: Bool) -> PipelineOutcome {
        guard focusIsSafe else { return .passThrough }
        let word: RecentWord
        if let current = buffer.currentWord {
            word = separatingTrailingPunctuation(from: current, delimiter: "")
        } else if let recentWord {
            word = separatingTrailingPunctuation(from: recentWord.candidate, delimiter: recentWord.delimiter)
        } else {
            return .passThrough
        }
        let candidate = word.candidate
        let delimiter = word.delimiter
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
        if automaticCorrectionEnabled, focusIsSafe, case let .candidates(candidates, _) = result {
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
                physicalKeyCount: plan.replacement.count), delimiter: plan.delimiter)
        }
    }

    public mutating func reset() {
        _ = buffer.handle(.reset)
        recentWord = nil
        latestDecisionPair = nil
    }
}
