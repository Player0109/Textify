public struct CanonicalAudioBuffer: Equatable, Sendable {
    public let sampleRate: Int
    public let channelCount: Int
    public let samples: [Float]

    public init(sampleRate: Int = 16_000, channelCount: Int = 1, samples: [Float]) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.samples = samples
    }

    public var durationSeconds: Double {
        guard sampleRate > 0 else {
            return 0
        }

        return Double(samples.count) / Double(sampleRate)
    }

    public var isEmpty: Bool {
        samples.isEmpty
    }
}
