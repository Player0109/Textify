public enum LiveAudioInput: Equatable, Sendable {
    case systemDefault
    case device(deviceUID: String)
}

public struct LiveAudioRecordingConfiguration: Equatable, Sendable {
    public let input: LiveAudioInput
    public let maximumDurationSeconds: Double
    public let postReleaseGraceMilliseconds: Int

    public init(
        input: LiveAudioInput = .systemDefault,
        maximumDurationSeconds: Double = 300,
        postReleaseGraceMilliseconds: Int = 250
    ) {
        self.input = input
        self.maximumDurationSeconds = maximumDurationSeconds
        self.postReleaseGraceMilliseconds = postReleaseGraceMilliseconds
    }

    public static let v1_1Default = LiveAudioRecordingConfiguration()
}
