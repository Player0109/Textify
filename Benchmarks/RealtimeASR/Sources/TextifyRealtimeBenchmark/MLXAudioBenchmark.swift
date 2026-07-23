import Foundation
import TextifyTranscription

enum MLXAudioBenchmark {
    static func run(
        engine: BenchmarkEngine,
        variant: MLXAudioModelVariant,
        modelID: String,
        modelLicense: String,
        audio: CanonicalBenchmarkAudio,
        modelDirectoryURL: URL,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        try await runSingleResidentBenchmark(
            session: MLXAudioBenchmarkSession(
                engine: engine,
                variant: variant,
                modelID: modelID,
                modelLicense: modelLicense,
                modelDirectoryURL: modelDirectoryURL,
                feedMode: feedMode
            ),
            audio: audio,
            reference: reference
        )
    }

    static func makeSession(
        engine: BenchmarkEngine,
        modelDirectoryURL: URL,
        feedMode: FeedMode
    ) throws -> any ResidentBenchmarkSession {
        let configuration: (MLXAudioModelVariant, String, String)
        switch engine {
        case .mlxParakeetRNNT1_1B:
            configuration = (.parakeetRNNT1_1B, "parakeet-rnnt-1.1b", "CC-BY-4.0")
        case .mlxCohereTranscribe03_2026:
            configuration = (
                .cohereTranscribe03_2026,
                "cohere-transcribe-03-2026-mlx-8bit",
                "Apache-2.0"
            )
        case .mlxWhisperLargeV3Turbo:
            configuration = (.whisperLargeV3Turbo, "whisper-large-v3-turbo-mlx", "MIT")
        case .mlxQwen3ASR0_6B8Bit:
            configuration = (.qwen3ASR0_6B8Bit, "qwen3-asr-0.6b-mlx-8bit", "Apache-2.0")
        case .mlxQwen3ASR1_7B8Bit:
            configuration = (.qwen3ASR1_7B8Bit, "qwen3-asr-1.7b-mlx-8bit", "Apache-2.0")
        case .mlxParakeetTDT0_6BV2:
            configuration = (.parakeetTDT0_6BV2, "parakeet-tdt-0.6b-v2-mlx", "CC-BY-4.0")
        case .mlxParakeetTDT0_6BV3:
            configuration = (.parakeetTDT0_6BV3, "parakeet-tdt-0.6b-v3-mlx", "CC-BY-4.0")
        case .mlxNemotron3_5ASRStreaming0_6B:
            configuration = (
                .nemotron3_5ASRStreaming0_6B,
                "nemotron-3.5-asr-streaming-0.6b-mlx",
                "NVIDIA Open Model License"
            )
        default:
            throw BenchmarkCLIError.invalidArguments(
                "MLX Audio resident session received unsupported engine: \(engine.rawValue)"
            )
        }
        return MLXAudioBenchmarkSession(
            engine: engine,
            variant: configuration.0,
            modelID: configuration.1,
            modelLicense: configuration.2,
            modelDirectoryURL: modelDirectoryURL,
            feedMode: feedMode
        )
    }
}

private final class MLXAudioBenchmarkSession: ResidentBenchmarkSession {
    let engine: BenchmarkEngine
    let modelName: String
    private(set) var modelLoadMs = 0
    private(set) var warmupMs = 0

    private let runtime = MLXAudioRuntime()
    private let variant: MLXAudioModelVariant
    private let modelLicense: String
    private let modelDirectoryURL: URL
    private let feedMode: FeedMode
    private var loaded = false

    init(
        engine: BenchmarkEngine,
        variant: MLXAudioModelVariant,
        modelID: String,
        modelLicense: String,
        modelDirectoryURL: URL,
        feedMode: FeedMode
    ) {
        self.engine = engine
        self.variant = variant
        self.modelName = modelID
        self.modelLicense = modelLicense
        self.modelDirectoryURL = modelDirectoryURL
        self.feedMode = feedMode
    }

    func load() async throws {
        guard !loaded else {
            throw BenchmarkCLIError.benchmarkFailed("MLX Audio benchmark session is already loaded")
        }
        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: modelName,
            modelDirectory: modelDirectoryURL.path,
            variant: variant,
            languageCode: variant.supportsAutomaticLanguageDetection ? "auto" : "en",
            warmup: false
        )
        modelLoadMs = elapsedMilliseconds(from: loadStart)

        let warmupStart = uptimeNanoseconds()
        _ = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.01, count: 16_000))
        )
        warmupMs = elapsedMilliseconds(from: warmupStart)
        loaded = true
    }

    func transcribe(
        audio: CanonicalBenchmarkAudio,
        reference: String?
    ) async throws -> BenchmarkResult {
        guard loaded else {
            throw BenchmarkCLIError.benchmarkFailed("MLX Audio benchmark session is not loaded")
        }
        let resourceStart = ResourceUsage.current()
        let inferenceStart = uptimeNanoseconds()
        let transcription = try await runtime.transcribe(
            TranscriptionAudioBuffer(
                sampleRate: CanonicalBenchmarkAudio.sampleRate,
                channelCount: 1,
                samples: audio.samples
            )
        )
        let inferenceMs = elapsedMilliseconds(from: inferenceStart)
        let resources = ResourceUsage.current().delta(from: resourceStart)
        return makeResult(
            engine: engine,
            engineVersion: "mlx-audio-swift d302a5c; MLX 0.31.3",
            model: modelName,
            modelLicense: modelLicense,
            computeBackend: "MLX Metal required and verified by Textify runtime",
            feedMode: feedMode,
            audio: audio,
            modelLoadMs: modelLoadMs,
            warmupMs: warmupMs,
            firstPartialMs: nil,
            partialIntervalsMs: [],
            releaseToFinalMs: inferenceMs,
            inferenceWorkMs: inferenceMs,
            maximumFeedLagMs: 0,
            transcript: transcription.text,
            reference: reference,
            resources: resources,
            productionMetadata: transcription
        )
    }

    func unload() async {
        guard loaded else { return }
        await runtime.unload()
        loaded = false
    }
}
