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

public enum VoiceCleaningRuntimeStatus: Equatable, Sendable {
    case disabled
    case preparing(modelID: String)
    case ready(modelID: String)
    case warning(modelID: String, reason: VoiceCleaningWarningReason)
}

public enum VoiceCleaningWarningReason: String, Equatable, Sendable {
    case modelUnavailable
    case processingFailed
    case revoked
}

public enum DictationCancellationReason: Equatable, Sendable {
    case releasedBeforeActivation
    case shortcutUseBeforeSpeech
    case escapeKey
    case noSpeechDetected
}
