import Foundation

public struct PasteboardItemSnapshot: Equatable, Sendable {
    public let representationsByType: [String: Data]

    public init(representationsByType: [String: Data]) {
        self.representationsByType = representationsByType
    }
}

public struct PasteboardSnapshot: Equatable, Sendable {
    public let items: [PasteboardItemSnapshot]
    public let changeCount: Int

    public init(items: [PasteboardItemSnapshot], changeCount: Int) {
        self.items = items
        self.changeCount = changeCount
    }
}

public struct PasteboardWriteResult: Equatable, Sendable {
    public let changeCount: Int

    public init(changeCount: Int) {
        self.changeCount = changeCount
    }
}

public protocol PasteboardClient: Sendable {
    func snapshot() async throws -> PasteboardSnapshot
    func clearAndWritePlainText(_ text: String, marker: PasteboardMarker) async throws -> PasteboardWriteResult
    func containsMarker(_ marker: PasteboardMarker) async throws -> Bool
    func currentChangeCount() async -> Int
    func restore(_ snapshot: PasteboardSnapshot, ifCurrentChangeCountMatches expectedChangeCount: Int) async throws -> Bool
}
