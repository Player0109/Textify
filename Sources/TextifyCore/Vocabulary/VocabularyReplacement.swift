public struct VocabularyReplacement: Equatable, Codable, Sendable {
    public let trigger: String
    public let replacement: String

    public init(trigger: String, replacement: String) {
        self.trigger = trigger
        self.replacement = replacement
    }
}
