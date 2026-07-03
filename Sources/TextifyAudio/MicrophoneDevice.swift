public struct MicrophoneDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let isAvailable: Bool

    public init(id: String, displayName: String, isAvailable: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.isAvailable = isAvailable
    }
}
