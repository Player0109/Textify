public enum LiveAudioRecorderError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case unsupportedInput
    case alreadyRecording
    case notRecording
    case inputNodeUnavailable
    case unsupportedInputFormat
    case engineStartFailed
    case conversionFailed
    case emptyRecording
    case deviceChangedDuringRecording
}
