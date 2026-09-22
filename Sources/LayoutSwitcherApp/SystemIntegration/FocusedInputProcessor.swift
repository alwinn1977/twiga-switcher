import LayoutSwitcherCore

public struct FocusedInputProcessor<Lexicon: FrequencyLexicon, Rules: UserCorrectionRuleLookingUp> {
    private var pipeline: InputPipeline<Lexicon, Rules>
    private var bufferedFocus: FocusIdentity?

    public init(pipeline: InputPipeline<Lexicon, Rules>) {
        self.pipeline = pipeline
    }

    public var latestDecisionPair: CorrectionPair? { pipeline.latestDecisionPair }

    public func needsFocusSnapshot(for event: InputEvent) -> Bool {
        switch event {
        case .character:
            return bufferedFocus == nil
        case .boundary:
            return true
        case .backspace, .reset, .synthetic:
            return false
        case .commandZ:
            return true
        }
    }

    public mutating func handle(_ event: InputEvent, focus: FocusSnapshot?) -> PipelineOutcome {
        switch event {
        case .character:
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

        case let .boundary(delimiter):
            if bufferedFocus == nil, delimiter == ".", let focus {
                bufferedFocus = focus.identity
                let outcome = pipeline.handle(event, focusIsSafe: true)
                if !pipeline.hasPendingText { bufferedFocus = nil }
                return outcome
            }
            guard let focus, focus.identity == bufferedFocus else {
                reset()
                return .passThrough
            }
            let outcome = pipeline.handle(event, focusIsSafe: true)
            if !pipeline.hasPendingText { bufferedFocus = nil }
            return outcome

        case .reset:
            reset()
            return .passThrough

        case .commandZ:
            return .passThrough

        case .backspace, .synthetic:
            return pipeline.handle(event, focusIsSafe: bufferedFocus != nil)
        }
    }

    public mutating func reset() {
        pipeline.reset()
        bufferedFocus = nil
    }
}
