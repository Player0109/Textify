import Foundation
import TextifyModels
import TextifyTranscription

protocol ParakeetRuntimeLoading: Sendable {
    var state: ParakeetRuntimeState { get async }

    func load(
        modelID: String,
        modelDirectory: String,
        variant: ParakeetModelVariant,
        computeRoute: ParakeetComputeRoute,
        languageCode: String?,
        warmup: Bool
    ) async throws

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
    func unload() async
}

extension ParakeetRuntime: ParakeetRuntimeLoading {}

public actor ParakeetRuntimeTranscribingAdapter: RuntimeEngineTranscribing {
    private let runtime: any ParakeetRuntimeLoading
    private var inFlightPreparations: [PreparationKey: InFlightPreparation] = [:]

    public init(runtime: ParakeetRuntime) {
        self.runtime = runtime
    }

    init(runtime: any ParakeetRuntimeLoading) {
        self.runtime = runtime
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            await Self.map(state: runtime.state)
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        guard model.engine == .fluidAudioParakeet else {
            throw RuntimeTranscriptionEngineError.engineMismatch(
                expected: .fluidAudioParakeet,
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
        guard let variant = ParakeetModelVariant(rawValue: model.variant) else {
            throw ParakeetRuntimeError.unsupportedVariant(model.variant)
        }

        let languageCode = model.runtimeParameters.detectLanguage
            ? nil
            : model.runtimeParameters.language
        let key = PreparationKey(
            modelID: model.id,
            modelDirectory: model.localModelPath,
            variant: variant,
            languageCode: languageCode
        )
        let state = await runtime.state
        if case let .ready(modelID) = state, modelID == model.id {
            try await runtime.load(
                modelID: model.id,
                modelDirectory: model.localModelPath,
                variant: variant,
                computeRoute: .neuralEngine,
                languageCode: languageCode,
                warmup: false
            )
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
                computeRoute: .neuralEngine,
                languageCode: languageCode,
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

    private static func map(state: ParakeetRuntimeState) -> RuntimeModelReadiness {
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

    private static func mapFailure(_ failure: ParakeetRuntimeFailure) -> RuntimeModelFailure {
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
        let variant: ParakeetModelVariant
        let languageCode: String?
    }

    private struct InFlightPreparation {
        let id: UUID
        let task: Task<Void, Error>
    }
}
