public enum WhisperRuntimeFailure: String, Equatable, Codable, Sendable {
    case missingModelFile
    case checksumFailure
    case loadFailed
    case memoryFailure
    case warmupFailed
}

public enum WhisperRuntimeState: Equatable, Sendable {
    case noModel
    case loading(modelID: String)
    case preparing(modelID: String)
    case ready(modelID: String)
    case unloadedToSaveMemory(modelID: String)
    case failed(modelID: String, reason: WhisperRuntimeFailure)
}
