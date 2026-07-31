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
        onMaximumDurationReached: @escaping @Sendable () -> Void,
        onRecordingError:
            @escaping @Sendable (LiveAudioRecorderError) -> Void
    ) async throws {
        let input: LiveAudioInput
        switch microphone {
        case .systemDefault:
            input = .systemDefault
        case .device(let deviceUID, _):
            input = .device(deviceUID: deviceUID)
        }

        try await recorder.startRecording(
            input: input,
            maximumDurationSeconds: maximumDurationSeconds,
            onSpeechDetected: onSpeechDetected,
            onMaximumDurationReached: onMaximumDurationReached,
            onRecordingError: onRecordingError
        )
    }

    public func finishRecording() async throws -> CanonicalAudioBuffer {
        try await recorder.finishRecording()
    }

    public func discardRecording() async {
        await recorder.discardRecording()
    }
}
