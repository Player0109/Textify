public struct InsertionRequest: Equatable, Sendable {
    public let text: String
    public let target: InsertionTargetIdentity?

    public init(text: String, target: InsertionTargetIdentity? = nil) {
        self.text = text
        self.target = target
    }
}

public enum InsertionOutcome: Equatable, Sendable {
    case pasted(PasteInsertionReport)
    case typed(TypingFallbackReport)
    case notInserted(InsertionFailureReason)
}

public struct TypingFallbackReport: Equatable, Sendable {
    public let cause: TypingFallbackCause
    public let chunkCount: Int

    public init(cause: TypingFallbackCause, chunkCount: Int) {
        self.cause = cause
        self.chunkCount = chunkCount
    }
}

public enum TypingFallbackCause: Equatable, Sendable {
    case pasteboardSnapshotUnavailable
    case pasteEventUnavailable
}

public struct PasteInsertionReport: Equatable, Sendable {
    public let pasteboardRestored: Bool
    public let pasteboardRestoreFailed: Bool

    public init(pasteboardRestored: Bool, pasteboardRestoreFailed: Bool) {
        self.pasteboardRestored = pasteboardRestored
        self.pasteboardRestoreFailed = pasteboardRestoreFailed
    }
}

public protocol InsertionService: Sendable {
    func insert(_ request: InsertionRequest) async -> InsertionOutcome
}
