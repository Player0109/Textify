import Foundation
import TextifyTranscription

enum LiteRTLMBenchmark {
    static func runGemma4(
        audio: CanonicalBenchmarkAudio,
        modelURL: URL,
        cacheURL: URL,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        let runtime = LiteRTLMRuntime(cacheDirectory: cacheURL.path)

        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: "gemma-4-12b-litertlm",
            modelPath: modelURL.path,
            variant: .gemma4_12B,
            languageCode: "en",
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
            engine: .liteRTGemma4_12B,
            engineVersion: "LiteRT-LM 0.14.0 (f73637c)",
            model: "gemma-4-12b-litertlm",
            modelLicense: "Apache-2.0",
            computeBackend: "LiteRT-LM text and audio GPU backends on Metal",
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
