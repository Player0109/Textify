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

public struct InsertionTargetIdentity: Equatable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?

    public init(processIdentifier: Int32, bundleIdentifier: String?) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
    }
}

public protocol InsertionTargetCapturing: Sendable {
    func currentTargetIdentity() async -> InsertionTargetIdentity?
}

public protocol InsertionTargetChecking: InsertionTargetCapturing {
    func currentTargetStatus() async -> InsertionTargetStatus
}
