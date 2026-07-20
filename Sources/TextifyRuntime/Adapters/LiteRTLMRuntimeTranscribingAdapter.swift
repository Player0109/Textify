import Foundation
import TextifyModels
import TextifyTranscription

protocol LiteRTLMRuntimeLoading: Sendable {
    var state: LiteRTLMRuntimeState { get async }

    func load(
        modelID: String,
        modelPath: String,
        variant: LiteRTLMModelVariant,
        languageCode: String,
        warmup: Bool
    ) async throws

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
    func unload() async
}

extension LiteRTLMRuntime: LiteRTLMRuntimeLoading {}

public actor LiteRTLMRuntimeTranscribingAdapter: RuntimeEngineTranscribing {
    private let runtime: any LiteRTLMRuntimeLoading
    private var inFlightPreparations: [PreparationKey: InFlightPreparation] = [:]
    private var preparedKey: PreparationKey?

    public init(runtime: LiteRTLMRuntime) {
        self.runtime = runtime
    }

    init(runtime: any LiteRTLMRuntimeLoading) {
        self.runtime = runtime
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            await Self.map(state: runtime.state)
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        guard model.engine == .liteRTLM else {
            throw RuntimeTranscriptionEngineError.engineMismatch(
                expected: .liteRTLM,
                actual: model.engine
            )
        }
        guard model.accelerator == .metalGPU else {
            throw RuntimeTranscriptionEngineError.incompatibleAccelerator(
                engine: model.engine,
                accelerator: model.accelerator
            )
        }
        guard model.artifactLayout == .singleFile else {
            throw RuntimeTranscriptionEngineError.incompatibleArtifactLayout(
                engine: model.engine,
                artifactLayout: model.artifactLayout
            )
        }
        guard let variant = LiteRTLMModelVariant(rawValue: model.variant) else {
            throw LiteRTLMRuntimeError.unsupportedVariant(model.variant)
        }
        guard !model.runtimeParameters.detectLanguage else {
            throw LiteRTLMRuntimeError.automaticLanguageDetectionUnsupported
        }
        let languageCode = try LiteRTLMRuntime.requireSupportedLanguage(
            model.runtimeParameters.language
        )
        let key = PreparationKey(
            modelID: model.id,
            modelPath: model.localModelPath,
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
                modelPath: model.localModelPath,
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

    private static func map(state: LiteRTLMRuntimeState) -> RuntimeModelReadiness {
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

    private static func mapFailure(_ failure: LiteRTLMRuntimeFailure) -> RuntimeModelFailure {
        switch failure {
        case .missingModelFile:
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
        let modelPath: String
        let variant: LiteRTLMModelVariant
        let languageCode: String
    }

    private struct InFlightPreparation {
        let id: UUID
        let task: Task<Void, Error>
    }
}
