import LayoutSwitcherCore

public enum ReplacementExecutionResult: Equatable, Sendable {
    case completed
    case textReplacedLayoutUnavailable
    case failed
}

public final class ReplacementExecutor {
    private let eventPoster: EventPosting
    private let inputSources: InputSourceManaging
    public init(eventPoster: EventPosting, inputSources: InputSourceManaging) { self.eventPoster = eventPoster; self.inputSources = inputSources }

    public func execute(_ plan: ReplacementPlan) -> ReplacementExecutionResult {
        guard eventPoster.postBackspaces(count: plan.deleteKeyCount),
              eventPoster.postUnicode(plan.replacement),
              eventPoster.postUnicode(plan.delimiter) else { return .failed }
        return inputSources.select(plan.targetLayout) ? .completed : .textReplacedLayoutUnavailable
    }
}
