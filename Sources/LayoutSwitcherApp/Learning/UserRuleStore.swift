import Foundation
import LayoutSwitcherCore

public final class UserRuleStore: @unchecked Sendable, UserCorrectionRuleLookingUp {
    public static let sharedDefault: UserRuleStore = {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let url = applicationSupport
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("rules.json")
        if let store = try? UserRuleStore(fileURL: url) { return store }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutSwitcher-rules-\(UUID().uuidString).json")
        guard let store = try? UserRuleStore(fileURL: fallback) else {
            preconditionFailure("Unable to create user rule store")
        }
        return store
    }()
    private struct Document: Codable {
        let schemaVersion: Int
        let rules: [UserRule]
    }

    public typealias BeforeReplace = @Sendable (URL) throws -> Void

    private let fileURL: URL
    private let beforeReplace: BeforeReplace
    private let lock = NSLock()
    private var current: UserRuleSnapshot
    private var sessionRules = UserRuleSnapshot(rules: [])

    public init(
        fileURL: URL,
        beforeReplace: @escaping BeforeReplace = { _ in }
    ) throws {
        self.fileURL = fileURL
        self.beforeReplace = beforeReplace
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let document = try JSONDecoder().decode(
                    Document.self,
                    from: Data(contentsOf: fileURL)
                )
                guard document.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
                self.current = UserRuleSnapshot(rules: document.rules)
            } catch {
                let quarantine = fileURL.deletingLastPathComponent().appendingPathComponent(
                    "\(fileURL.lastPathComponent).corrupt-\(UUID().uuidString)"
                )
                try? FileManager.default.moveItem(at: fileURL, to: quarantine)
                self.current = UserRuleSnapshot(rules: [])
            }
        } else {
            self.current = UserRuleSnapshot(rules: [])
        }
    }

    public func loadSnapshot() -> UserRuleSnapshot {
        lock.withLock { current }
    }

    public func disposition(source: String, candidate: String) -> UserCorrectionDisposition? {
        lock.withLock {
            sessionRules.disposition(source: source, candidate: candidate)
                ?? current.disposition(source: source, candidate: candidate)
        }
    }

    public func preventsEarlyCorrection(source: String, candidate: String) -> Bool {
        lock.withLock {
            sessionRules.preventsEarlyCorrection(source: source, candidate: candidate)
                || current.preventsEarlyCorrection(source: source, candidate: candidate)
        }
    }

    // Undo is not consent to store typed words. Keep its suppression in memory,
    // separate from explicit rules so a later save cannot persist undo history.
    public func suppressForSession(source: String, candidate: String) {
        let rule = UserRule(source: source, candidate: candidate, disposition: .never)
        lock.withLock {
            sessionRules = UserRuleSnapshot(rules: sessionRules.rules.filter { $0.id != rule.id } + [rule])
        }
    }

    public func set(
        disposition: UserCorrectionDisposition,
        source: String,
        candidate: String
    ) throws {
        let newRule = UserRule(source: source, candidate: candidate, disposition: disposition)
        try mutate(removingSessionRuleID: newRule.id) { rules in
            rules.removeAll { $0.id == newRule.id }
            rules.append(newRule)
        }
    }

    public func remove(_ rule: UserRule) throws {
        try mutate(removingSessionRuleID: rule.id) { $0.removeAll { $0.id == rule.id } }
    }

    public func removeAll() throws {
        try mutate(clearSessionRules: true) { $0.removeAll() }
    }

    private func mutate(
        removingSessionRuleID: String? = nil,
        clearSessionRules: Bool = false,
        _ mutation: (inout [UserRule]) -> Void
    ) throws {
        try lock.withLock {
            var rules = current.rules
            mutation(&rules)
            let next = UserRuleSnapshot(rules: rules)
            try persist(next)
            current = next
            sessionRules = UserRuleSnapshot(rules: clearSessionRules ? [] : sessionRules.rules.filter {
                $0.id != removingSessionRuleID
            })
        }
    }

    private func persist(_ snapshot: UserRuleSnapshot) throws {
        let document = Document(schemaVersion: 1, rules: snapshot.rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document)
        data.append(0x0A)
        let temporary = fileURL.deletingLastPathComponent().appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
            try beforeReplace(temporary)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
