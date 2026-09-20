import Foundation
import TextifyModels
import TextifyTranscription

public protocol RuntimeLivePreviewing: Sendable {
    var supportsLivePreview: Bool { get async }
    func preview(
        chunks: AsyncStream<TranscriptionAudioBuffer>,
        onText: @escaping @Sendable (String) async -> Void
    ) async throws
}

public actor ConfuciusRuntimeTranscribingAdapter: RuntimeEngineTranscribing, RuntimeLivePreviewing {
    private let runtime: ConfuciusRuntime
    private var preparedModel: RuntimeActiveModel?
    private var preparation: Task<Void, Error>?
    public private(set) var readiness: RuntimeModelReadiness = .noActiveModel

    public init(runtime: ConfuciusRuntime = ConfuciusRuntime()) {
        self.runtime = runtime
    }

    public var supportsLivePreview: Bool { preparedModel != nil }

    public func prepare(model: RuntimeActiveModel) async throws {
        if let preparation { try await preparation.value }
        guard model.engine == .audioCpp,
              model.accelerator == .metalGPU,
              model.artifactLayout == .singleFile,
              ["confucius4-r2t2-q8_0", "confucius4-r2t2-f16"].contains(model.variant),
              ["en", "zh", "auto"].contains(model.runtimeParameters.language) else {
            throw ConfuciusRuntimeError.unavailable
        }
        if preparedModel == model { return }
        // Language changes do not require reloading the weights.
        if preparedModel?.localModelPath == model.localModelPath {
            preparedModel = model
            readiness = .ready(modelID: model.id)
            return
        }
        preparedModel = nil
        readiness = .loading(modelID: model.id)
        let runtime = runtime
        let task = Task { try await runtime.load(modelPath: model.localModelPath) }
        preparation = task
        do {
            try await task.value
            preparation = nil
            preparedModel = model
            readiness = .ready(modelID: model.id)
        } catch {
            preparation = nil
            readiness = .failed(modelID: model.id, reason: .loadFailed)
            await runtime.unload()
            throw error
        }
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        guard let preparedModel else { throw ConfuciusRuntimeError.unavailable }
        return try await runtime.transcribe(audio, language: language(for: preparedModel))
    }

    public func preview(
        chunks: AsyncStream<TranscriptionAudioBuffer>,
        onText: @escaping @Sendable (String) async -> Void
    ) async throws {
        guard let preparedModel else { throw ConfuciusRuntimeError.unavailable }
        try await runtime.preview(chunks: chunks, language: language(for: preparedModel), onText: onText)
    }

    public func unload() async {
        if let preparation { _ = try? await preparation.value }
        preparedModel = nil
        readiness = .noActiveModel
        await runtime.unload()
    }

    private func language(for model: RuntimeActiveModel) -> String {
        switch model.runtimeParameters.language {
        case "en": "English"
        case "zh": "Chinese"
        default: ""
        }
    }
}
