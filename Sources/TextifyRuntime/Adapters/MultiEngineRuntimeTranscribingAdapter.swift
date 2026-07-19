import TextifyModels
import TextifyTranscription

protocol RuntimeEngineTranscribing: RuntimeTranscribing {
    func unload() async
}

extension WhisperRuntimeTranscribingAdapter: RuntimeEngineTranscribing {}

public enum RuntimeTranscriptionEngineError: Error, Equatable, Sendable {
    case engineMismatch(expected: TranscriptionEngine, actual: TranscriptionEngine)
    case incompatibleAccelerator(engine: TranscriptionEngine, accelerator: ModelAccelerator)
    case incompatibleArtifactLayout(
        engine: TranscriptionEngine,
        artifactLayout: ModelArtifactLayout
    )
    case noPreparedEngine
}

public actor MultiEngineRuntimeTranscribingAdapter: RuntimeTranscribing {
    private let whisper: any RuntimeEngineTranscribing
    private let parakeet: any RuntimeEngineTranscribing
    private let paraformer: any RuntimeEngineTranscribing
    private let sherpaOnnx: any RuntimeEngineTranscribing
    private let transcribeCpp: any RuntimeEngineTranscribing
    private var activeEngine: TranscriptionEngine?

    public init(
        whisper: WhisperRuntimeTranscribingAdapter,
        parakeet: ParakeetRuntimeTranscribingAdapter,
        paraformer: ParaformerRuntimeTranscribingAdapter,
        sherpaOnnx: SherpaOnnxRuntimeTranscribingAdapter,
        transcribeCpp: TranscribeCppRuntimeTranscribingAdapter
    ) {
        self.whisper = whisper
        self.parakeet = parakeet
        self.paraformer = paraformer
        self.sherpaOnnx = sherpaOnnx
        self.transcribeCpp = transcribeCpp
    }

    init(
        whisper: any RuntimeEngineTranscribing,
        parakeet: any RuntimeEngineTranscribing,
        paraformer: any RuntimeEngineTranscribing,
        sherpaOnnx: any RuntimeEngineTranscribing,
        transcribeCpp: any RuntimeEngineTranscribing
    ) {
        self.whisper = whisper
        self.parakeet = parakeet
        self.paraformer = paraformer
        self.sherpaOnnx = sherpaOnnx
        self.transcribeCpp = transcribeCpp
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            guard let activeEngine else {
                return .noActiveModel
            }
            return await backend(for: activeEngine).readiness
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        let target = backend(for: model.engine)
        if let activeEngine, activeEngine != model.engine {
            await backend(for: activeEngine).unload()
            self.activeEngine = nil
        }

        do {
            try await target.prepare(model: model)
            activeEngine = model.engine
        } catch {
            if activeEngine == nil || activeEngine != model.engine {
                activeEngine = nil
            }
            throw error
        }
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        guard let activeEngine else {
            throw RuntimeTranscriptionEngineError.noPreparedEngine
        }
        return try await backend(for: activeEngine).transcribe(audio)
    }

    public func unload() async {
        await whisper.unload()
        await parakeet.unload()
        await paraformer.unload()
        await sherpaOnnx.unload()
        await transcribeCpp.unload()
        activeEngine = nil
    }

    private func backend(for engine: TranscriptionEngine) -> any RuntimeEngineTranscribing {
        switch engine {
        case .whisperCpp:
            return whisper
        case .fluidAudioParakeet:
            return parakeet
        case .fluidAudioParaformer:
            return paraformer
        case .sherpaOnnx:
            return sherpaOnnx
        case .transcribeCpp:
            return transcribeCpp
        }
    }
}
