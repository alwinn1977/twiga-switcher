import Combine
import Foundation

@MainActor
public final class RulesManagerModel: ObservableObject {
    @Published public private(set) var rules: [UserRule] = []
    @Published private(set) var status: InterfaceStatus?
    public var statusMessage: String? { status?.localized(.english) }
    public func statusMessage(in language: DisplayLanguage) -> String? { status?.localized(language) }

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
            status = .removeRuleFailed(String(describing: error))
        }
    }

    public func removeAll() {
        guard confirmDeleteAll() else { return }
        do {
            try store.removeAll()
            refresh()
        } catch {
            status = .removeRulesFailed(String(describing: error))
        }
    }
}
