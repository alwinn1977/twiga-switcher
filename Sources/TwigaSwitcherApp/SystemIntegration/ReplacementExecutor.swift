import TwigaSwitcherCore

public enum ReplacementExecutionResult: Equatable, Sendable {
    case completed
    case textReplacedLayoutUnavailable
    case failedBeforeMutation
    case partialFailure
}

public final class ReplacementExecutor {
    private let eventPoster: EventPosting
    private let inputSources: InputSourceManaging
    private let spotlightTextReplacer: SpotlightTextReplacer

    public convenience init(eventPoster: EventPosting, inputSources: InputSourceManaging) {
        self.init(eventPoster: eventPoster, inputSources: inputSources, spotlightTextReplacer: .init())
    }

    init(eventPoster: EventPosting, inputSources: InputSourceManaging, spotlightTextReplacer: SpotlightTextReplacer) {
        self.eventPoster = eventPoster
        self.inputSources = inputSources
        self.spotlightTextReplacer = spotlightTextReplacer
    }

    public func execute(_ plan: ReplacementPlan, focus: FocusSnapshot? = nil, sourceText: String? = nil) -> ReplacementExecutionResult {
        if let result = spotlightTextReplacer.replace(plan, focus: focus, sourceText: sourceText) {
            switch result {
            case .replaced:
                return inputSources.select(plan.targetLayout) ? .completed : .textReplacedLayoutUnavailable
            case .failedBeforeMutation: return .failedBeforeMutation
            case .partialFailure: return .partialFailure
            }
        }
        guard eventPoster.isAvailable else { return .failedBeforeMutation }
        guard eventPoster.postBackspaces(count: plan.deleteKeyCount),
              eventPoster.postUnicode(plan.replacement),
              (plan.delimiter.isEmpty || eventPoster.postUnicode(plan.delimiter)) else { return .partialFailure }
        return inputSources.select(plan.targetLayout) ? .completed : .textReplacedLayoutUnavailable
    }

    public func reverse(_ plan: ReplacementPlan, focus: FocusSnapshot? = nil, sourceText: String? = nil) -> ReplacementExecutionResult {
        execute(plan, focus: focus, sourceText: sourceText)
    }
}
