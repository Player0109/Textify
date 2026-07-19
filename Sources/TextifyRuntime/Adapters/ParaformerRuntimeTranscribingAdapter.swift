import Foundation
import TextifyModels
import TextifyTranscription

protocol ParaformerRuntimeLoading: Sendable {
    var state: ParaformerRuntimeState { get async }

    func load(
        modelID: String,
        modelDirectory: String,
        variant: ParaformerModelVariant,
        warmup: Bool
    ) async throws

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
    func unload() async
}

extension ParaformerRuntime: ParaformerRuntimeLoading {}

public actor ParaformerRuntimeTranscribingAdapter: RuntimeEngineTranscribing {
    private let runtime: any ParaformerRuntimeLoading
    private var inFlightPreparations: [PreparationKey: InFlightPreparation] = [:]

    public init(runtime: ParaformerRuntime) {
        self.runtime = runtime
    }

    init(runtime: any ParaformerRuntimeLoading) {
        self.runtime = runtime
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            await Self.map(state: runtime.state)
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        guard model.engine == .fluidAudioParaformer else {
            throw RuntimeTranscriptionEngineError.engineMismatch(
                expected: .fluidAudioParaformer,
                actual: model.engine
            )
        }
        guard model.accelerator == .coreMLNeuralEngine else {
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
        guard !model.runtimeParameters.detectLanguage,
              model.runtimeParameters.language.lowercased().hasPrefix("zh")
        else {
            throw ParaformerRuntimeError.unsupportedLanguage(model.runtimeParameters.language)
        }
        guard let variant = ParaformerModelVariant(rawValue: model.variant) else {
            throw ParaformerRuntimeError.unsupportedVariant(model.variant)
        }

        let key = PreparationKey(
            modelID: model.id,
            modelDirectory: model.localModelPath,
            variant: variant
        )
        let state = await runtime.state
        if case let .ready(modelID) = state, modelID == model.id {
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
                warmup: true
            )
        }
        inFlightPreparations[key] = InFlightPreparation(id: preparationID, task: task)

        do {
            try await task.value
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
        await runtime.unload()
    }

    private static func map(state: ParaformerRuntimeState) -> RuntimeModelReadiness {
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

    private static func mapFailure(_ failure: ParaformerRuntimeFailure) -> RuntimeModelFailure {
        switch failure {
        case .missingModelDirectory:
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
        let variant: ParaformerModelVariant
    }

    private struct InFlightPreparation {
        let id: UUID
        let task: Task<Void, Error>
    }
}
