import Foundation
import TextifyModels
import TextifyTranscription

protocol SherpaOnnxRuntimeLoading: Sendable {
    var state: SherpaOnnxRuntimeState { get async }

    func load(
        modelID: String,
        modelDirectory: String,
        variant: SherpaOnnxModelVariant,
        languageCode: String,
        computeRoute: SherpaOnnxComputeRoute,
        threadCount: Int,
        warmup: Bool
    ) async throws

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
    func unload() async
}

extension SherpaOnnxRuntime: SherpaOnnxRuntimeLoading {}

public actor SherpaOnnxRuntimeTranscribingAdapter: RuntimeEngineTranscribing {
    private let runtime: any SherpaOnnxRuntimeLoading
    private var inFlightPreparations: [PreparationKey: InFlightPreparation] = [:]
    private var preparedKey: PreparationKey?

    public init(runtime: SherpaOnnxRuntime) {
        self.runtime = runtime
    }

    init(runtime: any SherpaOnnxRuntimeLoading) {
        self.runtime = runtime
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            await Self.map(state: runtime.state)
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        guard model.engine == .sherpaOnnx else {
            throw RuntimeTranscriptionEngineError.engineMismatch(
                expected: .sherpaOnnx,
                actual: model.engine
            )
        }
        guard model.accelerator == .cpu else {
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
        guard let variant = SherpaOnnxModelVariant(rawValue: model.variant) else {
            throw SherpaOnnxRuntimeError.unsupportedVariant(model.variant)
        }
        let languageCode: String
        switch variant {
        case .reazonSpeechK2V2:
            guard !model.runtimeParameters.detectLanguage,
                  model.runtimeParameters.language.lowercased().hasPrefix("ja")
            else {
                throw SherpaOnnxRuntimeError.unsupportedVariant(
                    "ReazonSpeech K2 V2 requires Japanese."
                )
            }
            languageCode = "ja"
        case .senseVoiceSmall:
            let requestedLanguage = model.runtimeParameters.detectLanguage
                ? "auto"
                : model.runtimeParameters.language.lowercased()
            guard ["auto", "zh", "en", "yue", "ja", "ko"].contains(requestedLanguage) else {
                throw SherpaOnnxRuntimeError.unsupportedVariant(
                    "SenseVoiceSmall supports automatic, Chinese, English, Cantonese, Japanese, or Korean recognition."
                )
            }
            languageCode = requestedLanguage
        case .omnilingualASR300M:
            guard model.runtimeParameters.detectLanguage,
                  model.runtimeParameters.language == "auto"
            else {
                throw SherpaOnnxRuntimeError.unsupportedVariant(
                    "Omnilingual ASR requires automatic language mode."
                )
            }
            languageCode = "auto"
        case .qwen3ASR0_6B, .dolphinSmall:
            throw SherpaOnnxRuntimeError.unsupportedVariant(
                "This sherpa-onnx candidate has not been promoted for production use."
            )
        }

        let threadCount = min(max(model.threadCount ?? 4, 1), 4)
        let key = PreparationKey(
            modelID: model.id,
            modelDirectory: model.localModelPath,
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
                modelDirectory: model.localModelPath,
                variant: variant,
                languageCode: languageCode,
                computeRoute: .cpu,
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

    private static func map(state: SherpaOnnxRuntimeState) -> RuntimeModelReadiness {
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

    private static func mapFailure(_ failure: SherpaOnnxRuntimeFailure) -> RuntimeModelFailure {
        switch failure {
        case .missingRuntimeDirectory, .missingModelDirectory:
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
        let variant: SherpaOnnxModelVariant
        let languageCode: String
        let threadCount: Int
    }

    private struct InFlightPreparation {
        let id: UUID
        let task: Task<Void, Error>
    }
}
