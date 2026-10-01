public struct ReplacementPlan: Equatable, Sendable {
    public let deleteKeyCount: Int
    public let replacement: String
    public let delimiter: String
    public let targetLayout: KeyboardLayout
    public init(deleteKeyCount: Int, replacement: String, delimiter: String, targetLayout: KeyboardLayout) {
        self.deleteKeyCount = deleteKeyCount; self.replacement = replacement
        self.delimiter = delimiter; self.targetLayout = targetLayout
    }
}

public enum PipelineOutcome: Equatable, Sendable {
    case passThrough
    case replace(ReplacementPlan)
}
