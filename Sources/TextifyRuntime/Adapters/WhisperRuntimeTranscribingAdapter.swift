import Foundation
import TextifyTranscription

protocol WhisperRuntimeLoading: Sendable {
    var state: WhisperRuntimeState { get async }

    func load(
        modelID: String,
        modelPath: String,
        useGPU: Bool,
        threadCount: Int,
        warmup: Bool
    ) async throws

    func transcribe(
        _ audio: TranscriptionAudioBuffer,
        options: WhisperTranscriptionOptions
    ) async throws -> TranscriptionResult

    func unload() async
}

extension WhisperRuntime: WhisperRuntimeLoading {}

public actor WhisperRuntimeTranscribingAdapter: RuntimeTranscribing {
    private let runtime: any WhisperRuntimeLoading
    private var inFlightPreparations: [PreparationKey: InFlightPreparation] = [:]
    private var activeOptions = WhisperTranscriptionOptions.v1_1English

    public init(runtime: WhisperRuntime) {
        self.runtime = runtime
    }

    init(runtime: any WhisperRuntimeLoading) {
        self.runtime = runtime
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            await Self.map(state: runtime.state)
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        let threadCount = model.threadCount ?? ProcessInfo.processInfo.activeProcessorCount
        let key = PreparationKey(
            modelID: model.id,
            modelPath: model.localModelPath,
            useGPU: model.useGPU,
            threadCount: threadCount
        )
        let state = await runtime.state
        if case let .ready(modelID) = state, modelID == model.id {
            activeOptions = Self.options(for: model)
            return
        }
        if let inFlightPreparation = inFlightPreparations[key] {
            try await inFlightPreparation.task.value
            activeOptions = Self.options(for: model)
            return
        }

        let preparationID = UUID()
        let runtime = runtime
        let task = Task {
            try await runtime.load(
                modelID: model.id,
                modelPath: model.localModelPath,
                useGPU: model.useGPU,
                threadCount: threadCount,
                warmup: true
            )
        }
        inFlightPreparations[key] = InFlightPreparation(id: preparationID, task: task)

        do {
            try await task.value
            clearInFlightPreparation(key: key, id: preparationID)
            activeOptions = Self.options(for: model)
        } catch {
            clearInFlightPreparation(key: key, id: preparationID)
            throw error
        }
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        try await runtime.transcribe(audio, options: activeOptions)
    }

    public func unload() async {
        inFlightPreparations.removeAll()
        activeOptions = .v1_1English
        await runtime.unload()
    }

    private static func options(for model: RuntimeActiveModel) -> WhisperTranscriptionOptions {
        let parameters = model.runtimeParameters
        return WhisperTranscriptionOptions(
            language: parameters.detectLanguage ? "auto" : parameters.language,
            translate: parameters.translate,
            temperature: Float(parameters.temperature),
            temperatureFallback: parameters.temperatureFallback.map(Float.init),
            usePreviousContext: !parameters.noContext,
            initialPrompt: nil
        )
    }

    private static func map(state: WhisperRuntimeState) -> RuntimeModelReadiness {
        switch state {
        case .noModel:
            return .noActiveModel
        case let .loading(modelID):
            return .loading(modelID: modelID)
        case let .preparing(modelID):
            return .warming(modelID: modelID)
        case let .ready(modelID):
            return .ready(modelID: modelID)
        case let .unloadedToSaveMemory(modelID):
            return .loading(modelID: modelID)
        case let .failed(modelID, reason):
            return .failed(modelID: modelID, reason: mapFailure(reason))
        }
    }

    private static func mapFailure(_ failure: WhisperRuntimeFailure) -> RuntimeModelFailure {
        switch failure {
        case .missingModelFile:
            return .missingFile
        case .checksumFailure:
            return .checksumFailed
        case .loadFailed, .memoryFailure:
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
        let useGPU: Bool
        let threadCount: Int
    }

    private struct InFlightPreparation {
        let id: UUID
        let task: Task<Void, Error>
    }
}
