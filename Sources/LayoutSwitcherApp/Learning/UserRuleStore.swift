import Foundation
import LayoutSwitcherCore

public final class UserRuleStore: @unchecked Sendable, UserCorrectionRuleLookingUp {
    private struct Document: Codable {
        let schemaVersion: Int
        let rules: [UserRule]
    }

    public typealias BeforeReplace = @Sendable (URL) throws -> Void

    private let fileURL: URL
    private let beforeReplace: BeforeReplace
    private let lock = NSLock()
    private var current: UserRuleSnapshot

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
        loadSnapshot().disposition(source: source, candidate: candidate)
    }

    public func set(
        disposition: UserCorrectionDisposition,
        source: String,
        candidate: String
    ) throws {
        let newRule = UserRule(source: source, candidate: candidate, disposition: disposition)
        try mutate { rules in
            rules.removeAll { $0.id == newRule.id }
            rules.append(newRule)
        }
    }

    public func remove(_ rule: UserRule) throws {
        try mutate { $0.removeAll { $0.id == rule.id } }
    }

    public func removeAll() throws {
        try mutate { $0.removeAll() }
    }

    private func mutate(_ mutation: (inout [UserRule]) -> Void) throws {
        try lock.withLock {
            var rules = current.rules
            mutation(&rules)
            let next = UserRuleSnapshot(rules: rules)
            try persist(next)
            current = next
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
