public enum UserCorrectionDisposition: String, Codable, Equatable, Sendable {
    case always
    case never
}

public protocol UserCorrectionRuleLookingUp: Sendable {
    func disposition(source: String, candidate: String) -> UserCorrectionDisposition?
    func preventsEarlyCorrection(source: String, candidate: String) -> Bool
}

public extension UserCorrectionRuleLookingUp {
    func preventsEarlyCorrection(source: String, candidate: String) -> Bool {
        disposition(source: source, candidate: candidate) == .never
    }
}

public struct NoUserCorrectionRules: UserCorrectionRuleLookingUp {
    public init() {}

    public func disposition(source: String, candidate: String) -> UserCorrectionDisposition? {
        nil
    }
}
