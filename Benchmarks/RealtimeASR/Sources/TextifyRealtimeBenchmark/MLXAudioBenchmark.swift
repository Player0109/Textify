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
        let runtime = MLXAudioRuntime()

        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: modelID,
            modelDirectory: modelDirectoryURL.path,
            variant: variant,
            languageCode: variant.supportsAutomaticLanguageDetection ? "auto" : "en",
            warmup: false
        )
        let loadMs = elapsedMilliseconds(from: loadStart)

        let warmupStart = uptimeNanoseconds()
        _ = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.01, count: 16_000))
        )
        let warmupMs = elapsedMilliseconds(from: warmupStart)

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
        await runtime.unload()

        return makeResult(
            engine: engine,
            engineVersion: "mlx-audio-swift d302a5c; MLX 0.31.3",
            model: modelID,
            modelLicense: modelLicense,
            computeBackend: "MLX Metal required and verified by Textify runtime",
            feedMode: feedMode,
            audio: audio,
            modelLoadMs: loadMs,
            warmupMs: warmupMs,
            firstPartialMs: nil,
            partialIntervalsMs: [],
            releaseToFinalMs: inferenceMs,
            inferenceWorkMs: inferenceMs,
            maximumFeedLagMs: 0,
            transcript: transcription.text,
            reference: reference,
            resources: resources
        )
    }
}
