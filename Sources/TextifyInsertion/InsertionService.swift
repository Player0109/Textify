public struct InsertionRequest: Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum InsertionOutcome: Equatable, Sendable {
    case pastePosted
    case fallbackTyped(chunks: Int)
    case notInserted(reason: String)
}

public protocol InsertionService: Sendable {
    func insert(_ request: InsertionRequest) async -> InsertionOutcome
}
