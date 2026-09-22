import Combine
import Foundation

@MainActor
public final class RulesManagerModel: ObservableObject {
    @Published public private(set) var rules: [UserRule] = []
    @Published public private(set) var statusMessage: String?

    private let store: UserRuleStore
    private let confirmDeleteAll: @MainActor () -> Bool

    public init(
        store: UserRuleStore = .sharedDefault,
        confirmDeleteAll: @escaping @MainActor () -> Bool = { true }
    ) {
        self.store = store
        self.confirmDeleteAll = confirmDeleteAll
        refresh()
    }

    public func refresh() {
        rules = store.loadSnapshot().rules
    }

    public func remove(_ rule: UserRule) {
        do {
            try store.remove(rule)
            refresh()
        } catch {
            statusMessage = "Unable to remove rule: \(error)"
        }
    }

    public func removeAll() {
        guard confirmDeleteAll() else { return }
        do {
            try store.removeAll()
            refresh()
        } catch {
            statusMessage = "Unable to remove rules: \(error)"
        }
    }
}
