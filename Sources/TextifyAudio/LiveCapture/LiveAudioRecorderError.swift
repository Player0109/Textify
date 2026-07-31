public enum LiveAudioRecorderError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case selectedInputUnavailable
    case alreadyRecording
    case notRecording
    case inputNodeUnavailable
    case unsupportedInputFormat
    case engineStartFailed
    case conversionFailed
    case emptyRecording
    case deviceChangedDuringRecording
}
