public struct WhisperRuntimeMetrics: Equatable, Sendable {
    public let lastLoadDurationMs: Int?
    public let lastWarmupDurationMs: Int?
    public let lastInferenceDurationMs: Int?

    public init(
        lastLoadDurationMs: Int? = nil,
        lastWarmupDurationMs: Int? = nil,
        lastInferenceDurationMs: Int? = nil
    ) {
        self.lastLoadDurationMs = lastLoadDurationMs
        self.lastWarmupDurationMs = lastWarmupDurationMs
        self.lastInferenceDurationMs = lastInferenceDurationMs
    }
}

public struct WhisperRuntimeSnapshot: Equatable, Sendable {
    public let state: WhisperRuntimeState
    public let metrics: WhisperRuntimeMetrics

    public init(state: WhisperRuntimeState, metrics: WhisperRuntimeMetrics) {
        self.state = state
        self.metrics = metrics
    }
}
