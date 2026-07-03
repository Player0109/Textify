public enum InsertionTargetStatus: Equatable, Sendable {
    case allowed
    case blocked(InsertionTargetBlock)
}

public enum InsertionTargetBlock: Equatable, Sendable {
    case secureInputEnabled
    case secureFieldFocused
    case systemOwnedContext
    case noFocusedElement
    case unsupportedFocusedElement
}

public protocol InsertionTargetChecking: Sendable {
    func currentTargetStatus() async -> InsertionTargetStatus
}
