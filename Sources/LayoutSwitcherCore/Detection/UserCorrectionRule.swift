public enum UserCorrectionDisposition: String, Codable, Equatable, Sendable {
    case always
    case never
}

public protocol UserCorrectionRuleLookingUp: Sendable {
    func disposition(source: String, candidate: String) -> UserCorrectionDisposition?
}

public struct NoUserCorrectionRules: UserCorrectionRuleLookingUp {
    public init() {}

    public func disposition(source: String, candidate: String) -> UserCorrectionDisposition? {
        nil
    }
}
