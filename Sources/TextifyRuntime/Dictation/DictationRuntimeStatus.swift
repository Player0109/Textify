public enum DictationRuntimeStatus: Equatable, Sendable {
    case idle
    case waitingForActivation
    case recording(speechDetected: Bool)
    case processing
    case inserting
    case completed(textLengthBucket: String)
    case cancelled(DictationCancellationReason)
    case blocked(ProductionDictationError)
    case failed(ProductionDictationError)
}

public enum DictationCancellationReason: Equatable, Sendable {
    case releasedBeforeActivation
    case shortcutUseBeforeSpeech
    case escapeKey
    case noSpeechDetected
}
