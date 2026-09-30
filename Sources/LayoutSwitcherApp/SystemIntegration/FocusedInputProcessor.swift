import LayoutSwitcherCore

public struct FocusedInputProcessor<Lexicon: FrequencyLexicon, Rules: UserCorrectionRuleLookingUp> {
    private var pipeline: InputPipeline<Lexicon, Rules>
    private var bufferedFocus: FocusIdentity?
    private var recentWordFocus: FocusIdentity?

    public init(pipeline: InputPipeline<Lexicon, Rules>) {
        self.pipeline = pipeline
    }

    public var latestDecisionPair: CorrectionPair? { pipeline.latestDecisionPair }

    public func needsFocusSnapshot(for event: InputEvent) -> Bool {
        switch event {
        case .character:
            return bufferedFocus == nil || pipeline.wouldCorrectWhileTyping(event)
        case .boundary, .punctuation:
            return true
        case .backspace, .reset, .synthetic:
            return false
        }
    }

    public mutating func updateConverter(_ converter: LayoutConverter) {
        pipeline.updateConverter(converter)
        resetBufferFocus()
    }

    public mutating func handle(_ event: InputEvent, focus: FocusSnapshot?) -> PipelineOutcome {
        let outcome = process(event, focus: focus)
        if case let .replace(plan) = outcome, let focus {
            remember(plan, focus: focus)
        }
        return outcome
    }

    private mutating func remember(_ plan: ReplacementPlan, focus: FocusSnapshot) {
        pipeline.rememberReplacement(plan)
        bufferedFocus = plan.delimiter.isEmpty ? focus.identity : nil
        recentWordFocus = plan.delimiter.isEmpty ? nil : focus.identity
    }

    private mutating func process(_ event: InputEvent, focus: FocusSnapshot?) -> PipelineOutcome {
        switch event {
        case .character:
            recentWordFocus = nil
            if pipeline.wouldCorrectWhileTyping(event), focus == nil {
                reset()
                return .passThrough
            }
            if let focus {
                if let bufferedFocus, bufferedFocus != focus.identity {
                    reset()
                }
                self.bufferedFocus = focus.identity
            } else if bufferedFocus == nil {
                reset()
                return .passThrough
            }
            return pipeline.handle(event, focusIsSafe: true)

        case let .boundary(delimiter), let .punctuation(delimiter, _, _):
            if bufferedFocus == nil,
               ([".", ","].contains(delimiter) || delimiter.first?.isLetter == true), let focus {
                bufferedFocus = focus.identity
                let outcome = pipeline.handle(event, focusIsSafe: true)
                recentWordFocus = pipeline.hasRecentWord ? focus.identity : nil
                if !pipeline.hasPendingText { bufferedFocus = nil }
                return outcome
            }
            guard let focus, focus.identity == bufferedFocus else {
                reset()
                return .passThrough
            }
            let outcome = pipeline.handle(event, focusIsSafe: true)
            recentWordFocus = pipeline.hasRecentWord ? focus.identity : nil
            if !pipeline.hasPendingText { bufferedFocus = nil }
            return outcome

        case .reset:
            reset()
            return .passThrough

        case .backspace, .synthetic:
            if event == .backspace { recentWordFocus = nil }
            return pipeline.handle(event, focusIsSafe: bufferedFocus != nil)
        }
    }

    public mutating func forceCorrection(focus: FocusSnapshot?) -> PipelineOutcome {
        let expectedFocus = pipeline.hasCurrentWord ? bufferedFocus : recentWordFocus
        guard let focus, let expectedFocus, focus.identity == expectedFocus else {
            reset()
            return .passThrough
        }
        let outcome = pipeline.forceCorrection(focusIsSafe: true)
        if case let .replace(plan) = outcome { remember(plan, focus: focus) }
        return outcome
    }

    private mutating func resetBufferFocus() {
        bufferedFocus = nil
        recentWordFocus = nil
    }

    public mutating func reset() {
        pipeline.reset()
        resetBufferFocus()
    }
}
