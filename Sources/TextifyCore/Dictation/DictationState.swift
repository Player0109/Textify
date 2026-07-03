public enum DictationState: Equatable, Sendable {
    case idle
    case armed
    case recording(speechDetected: Bool)
    case processing
    case inserting
    case error(DictationError)
}

public enum DictationError: Error, Equatable, Sendable {
    case audioStartFailed
    case audioFinishFailed
    case transcriptionFailed
    case insertionFailed
}
