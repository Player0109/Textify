import Foundation
import TextifyTranscription

public actor WhisperRuntimeTranscribingAdapter: RuntimeTranscribing {
    private let runtime: WhisperRuntime

    public init(runtime: WhisperRuntime) {
        self.runtime = runtime
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            await Self.map(state: runtime.state)
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        let state = await runtime.state
        if case let .ready(modelID) = state, modelID == model.id {
            return
        }

        try await runtime.load(
            modelID: model.id,
            modelPath: model.localModelPath,
            useGPU: model.useGPU,
            threadCount: model.threadCount ?? ProcessInfo.processInfo.activeProcessorCount,
            warmup: true
        )
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        try await runtime.transcribe(audio, options: .v1_1English)
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
}
