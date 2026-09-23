import LayoutSwitcherCore

public enum ReplacementExecutionResult: Equatable, Sendable {
    case completed
    case textReplacedLayoutUnavailable
    case failedBeforeMutation
    case partialFailure
}

public enum ReplacementEventDisposition: Equatable, Sendable {
    case passOriginal
    case suppressOriginal

    public static func resolve(_ result: ReplacementExecutionResult) -> Self {
        result == .failedBeforeMutation ? .passOriginal : .suppressOriginal
    }
}

public final class ReplacementExecutor {
    private let eventPoster: EventPosting
    private let inputSources: InputSourceManaging
    public init(eventPoster: EventPosting, inputSources: InputSourceManaging) { self.eventPoster = eventPoster; self.inputSources = inputSources }

    public func execute(_ plan: ReplacementPlan) -> ReplacementExecutionResult {
        guard eventPoster.isAvailable else { return .failedBeforeMutation }
        guard eventPoster.postBackspaces(count: plan.deleteKeyCount),
              eventPoster.postUnicode(plan.replacement),
              (plan.delimiter.isEmpty || eventPoster.postUnicode(plan.delimiter)) else { return .partialFailure }
        return inputSources.select(plan.targetLayout) ? .completed : .textReplacedLayoutUnavailable
    }

    public func reverse(_ plan: ReplacementPlan) -> ReplacementExecutionResult {
        execute(plan)
    }
}
