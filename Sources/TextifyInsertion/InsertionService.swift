public struct InsertionRequest: Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum InsertionOutcome: Equatable, Sendable {
    case pasted(PasteInsertionReport)
    case notInserted(InsertionFailureReason)
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
