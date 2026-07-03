public protocol TranscriptionProvider: Sendable {
    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
}

public struct TranscriptionAudioBuffer: Equatable, Sendable {
    public let sampleRate: Int
    public let channelCount: Int
    public let samples: [Float]

    public init(sampleRate: Int = 16_000, channelCount: Int = 1, samples: [Float]) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.samples = samples
    }

    public static let emptyForTests = TranscriptionAudioBuffer(samples: [])
}
