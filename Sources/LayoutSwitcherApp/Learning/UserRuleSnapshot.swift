import Foundation
import LayoutSwitcherCore

public struct UserRule: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let source: String
    public let candidate: String
    public let disposition: UserCorrectionDisposition

    public var id: String { source + "\u{0}" + candidate }

    public init(source: String, candidate: String, disposition: UserCorrectionDisposition) {
        self.source = TermNormalizer.normalize(source)
        self.candidate = TermNormalizer.normalize(candidate)
        self.disposition = disposition
    }
}

public final class UserRuleSnapshot: @unchecked Sendable, UserCorrectionRuleLookingUp {
    public let rules: [UserRule]
    private let byID: [String: UserCorrectionDisposition]

    public init(rules: [UserRule]) {
        self.rules = rules.sorted {
            ($0.source, $0.candidate, $0.disposition.rawValue)
                < ($1.source, $1.candidate, $1.disposition.rawValue)
        }
        self.byID = Dictionary(uniqueKeysWithValues: self.rules.map { ($0.id, $0.disposition) })
    }

    public func disposition(source: String, candidate: String) -> UserCorrectionDisposition? {
        let id = TermNormalizer.normalize(source) + "\u{0}" + TermNormalizer.normalize(candidate)
        return byID[id]
    }
}
