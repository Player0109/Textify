public enum ProductionDictationError: Error, Equatable, Sendable {
    case readinessBlocked(ReadinessBlocker)
    case concurrentDictation
    case audioStartFailed
    case audioFinishFailed
    case audioConversionFailed
    case microphoneChanged
    case transcriptionNotReady
    case transcriptionFailed
    case insertionFailed
}
