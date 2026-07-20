import Foundation
import TextifyModels
import TextifyTranscription

protocol MLXAudioRuntimeLoading: Sendable {
    var state: MLXAudioRuntimeState { get async }

    func load(
        modelID: String,
        modelDirectory: String,
        variant: MLXAudioModelVariant,
        languageCode: String,
        warmup: Bool
    ) async throws

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
    func unload() async
}

extension MLXAudioRuntime: MLXAudioRuntimeLoading {}

public actor MLXAudioRuntimeTranscribingAdapter: RuntimeEngineTranscribing {
    private let runtime: any MLXAudioRuntimeLoading
    private var inFlightPreparations: [PreparationKey: InFlightPreparation] = [:]
    private var preparedKey: PreparationKey?

    public init(runtime: MLXAudioRuntime) {
        self.runtime = runtime
    }

    init(runtime: any MLXAudioRuntimeLoading) {
        self.runtime = runtime
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            await Self.map(state: runtime.state)
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        guard model.engine == .mlxAudio else {
            throw RuntimeTranscriptionEngineError.engineMismatch(
                expected: .mlxAudio,
                actual: model.engine
            )
        }
        guard model.accelerator == .metalGPU else {
            throw RuntimeTranscriptionEngineError.incompatibleAccelerator(
                engine: model.engine,
                accelerator: model.accelerator
            )
        }
        guard model.artifactLayout == .modelDirectory else {
            throw RuntimeTranscriptionEngineError.incompatibleArtifactLayout(
                engine: model.engine,
                artifactLayout: model.artifactLayout
            )
        }
        guard let variant = MLXAudioModelVariant(rawValue: model.variant) else {
            throw MLXAudioRuntimeError.unsupportedVariant(model.variant)
        }
        if variant.supportsAutomaticLanguageDetection {
            guard model.runtimeParameters.detectLanguage else {
                throw MLXAudioRuntimeError.automaticLanguageDetectionRequired
            }
        } else if model.runtimeParameters.detectLanguage {
            throw MLXAudioRuntimeError.automaticLanguageDetectionUnsupported
        }
        let languageCode = try MLXAudioRuntime.requireSupportedLanguage(
            model.runtimeParameters.language,
            variant: variant
        )
        let key = PreparationKey(
            modelID: model.id,
            modelDirectory: model.localModelPath,
            variant: variant,
            languageCode: languageCode
        )
        let state = await runtime.state
        if case let .ready(modelID) = state,
           modelID == model.id,
           preparedKey == key {
            return
        }
        if let inFlightPreparation = inFlightPreparations[key] {
            try await inFlightPreparation.task.value
            return
        }

        let preparationID = UUID()
        let runtime = runtime
        let task = Task {
            try await runtime.load(
                modelID: model.id,
                modelDirectory: model.localModelPath,
                variant: variant,
                languageCode: languageCode,
                warmup: true
            )
        }
        inFlightPreparations[key] = InFlightPreparation(id: preparationID, task: task)

        do {
            try await task.value
            preparedKey = key
            clearInFlightPreparation(key: key, id: preparationID)
        } catch {
            clearInFlightPreparation(key: key, id: preparationID)
            throw error
        }
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        try await runtime.transcribe(audio)
    }

    public func unload() async {
        inFlightPreparations.removeAll()
        preparedKey = nil
        await runtime.unload()
    }

    private static func map(state: MLXAudioRuntimeState) -> RuntimeModelReadiness {
        switch state {
        case .noModel:
            return .noActiveModel
        case let .loading(modelID):
            return .loading(modelID: modelID)
        case let .preparing(modelID):
            return .warming(modelID: modelID)
        case let .ready(modelID):
            return .ready(modelID: modelID)
        case let .failed(modelID, reason):
            return .failed(modelID: modelID, reason: mapFailure(reason))
        }
    }

    private static func mapFailure(_ failure: MLXAudioRuntimeFailure) -> RuntimeModelFailure {
        switch failure {
        case .missingModelDirectory, .missingModelFile:
            return .missingFile
        case .loadFailed:
            return .loadFailed
        case .warmupFailed:
            return .warmupFailed
        }
    }

    private func clearInFlightPreparation(key: PreparationKey, id: UUID) {
        guard inFlightPreparations[key]?.id == id else {
            return
        }
        inFlightPreparations[key] = nil
    }

    private struct PreparationKey: Hashable, Sendable {
        let modelID: String
        let modelDirectory: String
        let variant: MLXAudioModelVariant
        let languageCode: String
    }

    private struct InFlightPreparation {
        let id: UUID
        let task: Task<Void, Error>
    }
}
