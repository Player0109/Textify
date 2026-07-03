public struct TranscriptionTiming: Equatable, Codable, Sendable {
    public let audioDurationMs: Int
    public let inferenceDurationMs: Int

    public init(audioDurationMs: Int, inferenceDurationMs: Int) {
        self.audioDurationMs = audioDurationMs
        self.inferenceDurationMs = inferenceDurationMs
    }
}

public struct TranscriptionResult: Equatable, Codable, Sendable {
    public let text: String
    public let noSpeechProbability: Double
    public let averageLogProbability: Double
    public let compressionRatio: Double
    public let timing: TranscriptionTiming?

    public init(
        text: String,
        noSpeechProbability: Double,
        averageLogProbability: Double,
        compressionRatio: Double,
        timing: TranscriptionTiming? = nil
    ) {
        self.text = text
        self.noSpeechProbability = noSpeechProbability
        self.averageLogProbability = averageLogProbability
        self.compressionRatio = compressionRatio
        self.timing = timing
    }
}
