import Foundation
import TextifyModels
import TextifyTranscription

protocol TranscribeCppRuntimeLoading: Sendable {
    var state: TranscribeCppRuntimeState { get async }

    func load(
        modelID: String,
        modelPath: String,
        variant: TranscribeCppModelVariant,
        languageCode: String,
        threadCount: Int,
        warmup: Bool
    ) async throws

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
    func unload() async
}

extension TranscribeCppRuntime: TranscribeCppRuntimeLoading {}

public actor TranscribeCppRuntimeTranscribingAdapter: RuntimeEngineTranscribing {
    private let runtime: any TranscribeCppRuntimeLoading
    private var inFlightPreparations: [PreparationKey: InFlightPreparation] = [:]
    private var preparedKey: PreparationKey?

    public init(runtime: TranscribeCppRuntime) {
        self.runtime = runtime
    }

    init(runtime: any TranscribeCppRuntimeLoading) {
        self.runtime = runtime
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            await Self.map(state: runtime.state)
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        guard model.engine == .transcribeCpp else {
            throw RuntimeTranscriptionEngineError.engineMismatch(
                expected: .transcribeCpp,
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
        guard let variant = TranscribeCppModelVariant(rawValue: model.variant) else {
            throw TranscribeCppRuntimeError.unsupportedVariant(model.variant)
        }
        guard !model.runtimeParameters.detectLanguage else {
            throw TranscribeCppRuntimeError.automaticLanguageDetectionUnsupported
        }
        let languageCode = try TranscribeCppRuntime.requireSupportedLanguage(
            model.runtimeParameters.language
        )
        let threadCount = min(max(model.threadCount ?? 4, 1), 4)
        let key = PreparationKey(
            modelID: model.id,
            modelPath: model.localModelPath,
            variant: variant,
            languageCode: languageCode,
            threadCount: threadCount
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
                threadCount: threadCount,
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

    private static func map(state: TranscribeCppRuntimeState) -> RuntimeModelReadiness {
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

    private static func mapFailure(_ failure: TranscribeCppRuntimeFailure) -> RuntimeModelFailure {
        switch failure {
        case .missingRuntimeDirectory, .missingModelFile:
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
        let variant: TranscribeCppModelVariant
        let languageCode: String
        let threadCount: Int
    }

    private struct InFlightPreparation {
        let id: UUID
        let task: Task<Void, Error>
    }
}
