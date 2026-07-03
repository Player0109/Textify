public enum MockTranscriptionProviderError: Error, Equatable, Sendable {
    case noQueuedResult
}

public actor MockTranscriptionProvider: TranscriptionProvider {
    private var queuedResults: [TranscriptionResult]

    public init(results: [TranscriptionResult]) {
        self.queuedResults = results
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        guard !queuedResults.isEmpty else {
            throw MockTranscriptionProviderError.noQueuedResult
        }

        return queuedResults.removeFirst()
    }
}
