import TextifyAudio
import TextifySettings

public actor RuntimeAudioRecorderAdapter: RuntimeAudioRecording {
    private let recorder: LiveAudioRecorder

    public init(recorder: LiveAudioRecorder = LiveAudioRecorder()) {
        self.recorder = recorder
    }

    public func startRecording(
        microphone: MicrophoneSelection,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) async throws {
        guard microphone == .systemDefault else {
            throw LiveAudioRecorderError.unsupportedInput
        }

        try await recorder.startRecording(
            onSpeechDetected: onSpeechDetected,
            onMaximumDurationReached: {}
        )
    }

    public func finishRecording() async throws -> CanonicalAudioBuffer {
        try await recorder.finishRecording()
    }

    public func discardRecording() async {
        await recorder.discardRecording()
    }
}
