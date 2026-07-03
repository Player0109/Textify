public struct TranscriptionResult: Equatable, Codable, Sendable {
    public let text: String
    public let noSpeechProbability: Double
    public let averageLogProbability: Double
    public let compressionRatio: Double

    public init(
        text: String,
        noSpeechProbability: Double,
        averageLogProbability: Double,
        compressionRatio: Double
    ) {
        self.text = text
        self.noSpeechProbability = noSpeechProbability
        self.averageLogProbability = averageLogProbability
        self.compressionRatio = compressionRatio
    }
}
