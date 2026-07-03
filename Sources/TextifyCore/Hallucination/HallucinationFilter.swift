public struct HallucinationFilter {
    public init() {}

    public func shouldDiscard(
        text: String,
        noSpeechProbability: Double,
        averageLogProbability: Double,
        compressionRatio: Double
    ) -> Bool {
        if noSpeechProbability > 0.60 {
            return true
        }
        if averageLogProbability < -1.00 {
            return true
        }
        if compressionRatio > 2.40 {
            return true
        }
        return text.localizedCaseInsensitiveContains("thanks for watching")
    }
}
