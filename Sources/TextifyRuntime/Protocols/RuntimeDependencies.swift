import TextifyAudio
import TextifyCore
import TextifyDiagnostics
import TextifyInsertion
import TextifyModels
import TextifySettings
import TextifyTranscription

public struct RuntimeActiveModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let tier: String
    public let localModelPath: String
    public let useGPU: Bool
    public let threadCount: Int?
    public let engine: TranscriptionEngine
    public let variant: String
    public let accelerator: ModelAccelerator
    public let artifactLayout: ModelArtifactLayout
    public let runtimeParameters: RuntimeParameters
    public let purpose: ModelPurpose

    public init(
        id: String,
        displayName: String,
        tier: String,
        localModelPath: String,
        useGPU: Bool,
        threadCount: Int?
    ) {
        self.init(
            id: id,
            displayName: displayName,
            tier: tier,
            localModelPath: localModelPath,
            useGPU: useGPU,
            threadCount: threadCount,
            engine: .whisperCpp,
            variant: ModelRuntimeDescriptor.legacyWhisper.variant,
            accelerator: .metalGPU,
            artifactLayout: .singleFile,
            runtimeParameters: .legacyEnglishWhisper,
            purpose: .transcription
        )
    }

    public init(
        id: String,
        displayName: String,
        tier: String,
        localModelPath: String,
        useGPU: Bool,
        threadCount: Int?,
        engine: TranscriptionEngine,
        variant: String,
        accelerator: ModelAccelerator,
        artifactLayout: ModelArtifactLayout,
        runtimeParameters: RuntimeParameters,
        purpose: ModelPurpose = .transcription
    ) {
        self.id = id
        self.displayName = displayName
        self.tier = tier
        self.localModelPath = localModelPath
        self.useGPU = useGPU
        self.threadCount = threadCount
        self.engine = engine
        self.variant = variant
        self.accelerator = accelerator
        self.artifactLayout = artifactLayout
        self.runtimeParameters = runtimeParameters
        self.purpose = purpose
    }
}

public struct RuntimeDependencies: Sendable {
    public let settings: any RuntimeSettingsProviding
    public let permissions: any RuntimePermissionChecking
    public let models: any RuntimeModelResolving
    public let audio: any RuntimeAudioRecording
    public let transcriber: any RuntimeTranscribing
    public let voiceCleaner: any RuntimeVoiceCleaning
    public let targetCapturer: any InsertionTargetCapturing
    public let inserter: any InsertionService
    public let diagnostics: any RuntimeDiagnosticsLogging
    public let postProcessor: any RuntimePostProcessing
    public let clock: any RuntimeClock

    public init(
        settings: any RuntimeSettingsProviding,
        permissions: any RuntimePermissionChecking,
        models: any RuntimeModelResolving,
        audio: any RuntimeAudioRecording,
        transcriber: any RuntimeTranscribing,
        voiceCleaner: any RuntimeVoiceCleaning = DisabledRuntimeVoiceCleaning(),
        targetCapturer: any InsertionTargetCapturing,
        inserter: any InsertionService,
        diagnostics: any RuntimeDiagnosticsLogging,
        postProcessor: any RuntimePostProcessing,
        clock: any RuntimeClock
    ) {
        self.settings = settings
        self.permissions = permissions
        self.models = models
        self.audio = audio
        self.transcriber = transcriber
        self.voiceCleaner = voiceCleaner
        self.targetCapturer = targetCapturer
        self.inserter = inserter
        self.diagnostics = diagnostics
        self.postProcessor = postProcessor
        self.clock = clock
    }
}

public protocol RuntimeSettingsProviding: Sendable {
    func loadPreferences() async -> AppPreferences
    func savePreferences(_ preferences: AppPreferences) async
}

public protocol RuntimePermissionChecking: Sendable {
    func permissionSnapshot() async -> RuntimePermissionSnapshot
}

public protocol RuntimeModelResolving: Sendable {
    func resolveActiveModel(preferences: AppPreferences) async -> RuntimeActiveModel?
    func resolveActiveVoiceCleaningModel(preferences: AppPreferences) async -> RuntimeActiveModel?
    func readiness(for model: RuntimeActiveModel?) async -> RuntimeModelReadiness
}

public extension RuntimeModelResolving {
    func resolveActiveVoiceCleaningModel(preferences: AppPreferences) async -> RuntimeActiveModel? {
        nil
    }
}

public protocol RuntimeAudioRecording: Sendable {
    func startRecording(
        microphone: MicrophoneSelection,
        maximumDurationSeconds: Double,
        onSpeechDetected: @escaping @Sendable () -> Void,
        onMaximumDurationReached: @escaping @Sendable () -> Void
    ) async throws
    func finishRecording() async throws -> CanonicalAudioBuffer
    func discardRecording() async
}

public protocol RuntimeTranscribing: Sendable {
    var readiness: RuntimeModelReadiness { get async }
    func prepare(model: RuntimeActiveModel) async throws
    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
}

public protocol RuntimeVoiceCleaning: Sendable {
    func prepare(model: RuntimeActiveModel) async throws
    func clean(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionAudioBuffer
    func unload() async
}

public struct DisabledRuntimeVoiceCleaning: RuntimeVoiceCleaning {
    public init() {}

    public func prepare(model: RuntimeActiveModel) async throws {}

    public func clean(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionAudioBuffer {
        audio
    }

    public func unload() async {}
}

public protocol RuntimeDiagnosticsLogging: Sendable {
    func log(_ event: DiagnosticEvent) async
}

public protocol RuntimePostProcessing: Sendable {
    func process(rawText: String, preferences: AppPreferences) async -> String
}

public protocol RuntimeClock: Sendable {
    func nowMilliseconds() -> Int
    func sleep(milliseconds: Int) async
}
