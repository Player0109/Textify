import TextifyModels
import TextifyTranscription

public enum RuntimeVoiceCleaningAdapterError: Error, Equatable, Sendable {
    case wrongPurpose(ModelPurpose)
    case incompatibleRuntime
    case unsupportedVariant(String)
}

public actor MossFormer2RuntimeVoiceCleaner: RuntimeVoiceCleaning {
    private let runtime: MossFormer2VoiceCleaningRuntime

    public init(runtime: MossFormer2VoiceCleaningRuntime) {
        self.runtime = runtime
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        guard model.purpose == .voiceCleaning else {
            throw RuntimeVoiceCleaningAdapterError.wrongPurpose(model.purpose)
        }
        guard model.engine == .mlxAudio,
              model.accelerator == .metalGPU,
              model.artifactLayout == .modelDirectory else {
            throw RuntimeVoiceCleaningAdapterError.incompatibleRuntime
        }
        guard let variant = MossFormer2VoiceCleaningVariant(rawValue: model.variant) else {
            throw RuntimeVoiceCleaningAdapterError.unsupportedVariant(model.variant)
        }
        try await runtime.load(
            modelID: model.id,
            modelDirectory: model.localModelPath,
            variant: variant
        )
    }

    public func clean(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionAudioBuffer {
        try await runtime.clean(audio)
    }

    public func unload() async {
        await runtime.unload()
    }
}
