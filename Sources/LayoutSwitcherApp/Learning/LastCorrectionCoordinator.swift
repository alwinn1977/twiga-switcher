import Foundation
import LayoutSwitcherCore

public struct LastCorrection: Equatable, Sendable {
    public let source: String
    public let candidate: String
    public let delimiter: String
    public let focus: FocusIdentity
    public let originalLayout: KeyboardLayout

    public init(
        source: String,
        candidate: String,
        delimiter: String,
        focus: FocusIdentity,
        originalLayout: KeyboardLayout
    ) {
        self.source = source
        self.candidate = candidate
        self.delimiter = delimiter
        self.focus = focus
        self.originalLayout = originalLayout
    }
}

public struct UndoLearningAction: Equatable, Sendable {
    public let source: String
    public let candidate: String
    public let reversalPlan: ReplacementPlan
}

public final class LastCorrectionCoordinator: @unchecked Sendable {
    public typealias Clock = @Sendable () -> TimeInterval

    private struct TimedCorrection {
        let value: LastCorrection
        let recordedAt: TimeInterval
    }

    private let ruleStore: UserRuleStore
    private let clock: Clock
    private let lifetime: TimeInterval
    private let lock = NSLock()
    private var current: TimedCorrection?

    public init(
        ruleStore: UserRuleStore,
        lifetime: TimeInterval = 10,
        clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.ruleStore = ruleStore
        self.lifetime = lifetime
        self.clock = clock
    }

    public func record(_ correction: LastCorrection) {
        lock.withLock { current = TimedCorrection(value: correction, recordedAt: clock()) }
    }

    public func invalidate() {
        lock.withLock { current = nil }
    }

    public func handleCommandZ(currentFocus: FocusIdentity) -> UndoLearningAction? {
        lock.withLock {
            guard let timed = current,
                  timed.value.focus == currentFocus,
                  clock() - timed.recordedAt <= lifetime else {
                current = nil
                return nil
            }
            current = nil
            let correction = timed.value
            return UndoLearningAction(
                source: correction.source,
                candidate: correction.candidate,
                reversalPlan: ReplacementPlan(
                    deleteKeyCount: correction.candidate.count + correction.delimiter.count,
                    replacement: correction.source,
                    delimiter: correction.delimiter,
                    targetLayout: correction.originalLayout
                )
            )
        }
    }

    public func complete(_ action: UndoLearningAction, result: ReplacementExecutionResult) throws {
        guard result == .completed else { return }
        try ruleStore.set(disposition: .never, source: action.source, candidate: action.candidate)
    }
}
