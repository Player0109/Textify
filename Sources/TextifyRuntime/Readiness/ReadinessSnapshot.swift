public struct ReadinessSnapshot: Equatable, Sendable {
    public let permissions: RuntimePermissionSnapshot
    public let model: RuntimeModelReadiness
    public let blockers: [ReadinessBlocker]

    public var canDictate: Bool {
        blockers.isEmpty
    }

    public init(
        permissions: RuntimePermissionSnapshot,
        model: RuntimeModelReadiness,
        blockers: [ReadinessBlocker]
    ) {
        self.permissions = permissions
        self.model = model
        self.blockers = blockers
    }
}

public struct RuntimePermissionSnapshot: Equatable, Sendable {
    public let microphone: RuntimePermissionState
    public let accessibility: RuntimePermissionState
    public let inputMonitoring: RuntimePermissionState

    public init(
        microphone: RuntimePermissionState,
        accessibility: RuntimePermissionState,
        inputMonitoring: RuntimePermissionState
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }
}

public enum RuntimePermissionState: Equatable, Sendable {
    case unknown
    case granted
    case denied
}

public enum RuntimeModelReadiness: Equatable, Sendable {
    case noActiveModel
    case missing(modelID: String)
    case loading(modelID: String)
    case warming(modelID: String)
    case ready(modelID: String)
    case failed(modelID: String, reason: RuntimeModelFailure)
}

public enum RuntimeModelFailure: Equatable, Sendable {
    case missingFile
    case checksumFailed
    case loadFailed
    case warmupFailed
}

public enum ReadinessBlocker: Equatable, Sendable {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case inputMonitoringPermissionDenied
    case noActiveModel
    case activeModelMissing(modelID: String)
    case activeModelNotReady(modelID: String)
    case transcriptionRuntimeFailed(modelID: String)
}
