import TextifyAudio
import TextifySettings

public actor RuntimeAudioRecorderAdapter: RuntimeAudioRecording {
    private let recorder: LiveAudioRecorder

    public init(recorder: LiveAudioRecorder = LiveAudioRecorder()) {
        self.recorder = recorder
    }

    public func startRecording(
        microphone: MicrophoneSelection,
        maximumDurationSeconds: Double,
        onSpeechDetected: @escaping @Sendable () -> Void,
        onMaximumDurationReached: @escaping @Sendable () -> Void
    ) async throws {
        guard microphone == .systemDefault else {
            throw LiveAudioRecorderError.unsupportedInput
        }

        try await recorder.startRecording(
            maximumDurationSeconds: maximumDurationSeconds,
            onSpeechDetected: onSpeechDetected,
            onMaximumDurationReached: onMaximumDurationReached
        )
    }

    public func finishRecording() async throws -> CanonicalAudioBuffer {
        try await recorder.finishRecording()
    }

    public func discardRecording() async {
        await recorder.discardRecording()
    }
}
