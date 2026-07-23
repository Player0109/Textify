import Foundation
import TextifyTranscription

enum ParaformerBenchmark {
    static func run(
        audio: CanonicalBenchmarkAudio,
        modelsRootURL: URL,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        let modelDirectory = modelsRootURL
            .appendingPathComponent("paraformer-large-zh", isDirectory: true)
        let runtime = ParaformerRuntime()

        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: "paraformer-large-zh-int8",
            modelDirectory: modelDirectory.path,
            variant: .largeZhInt8,
            warmup: false
        )
        let loadMs = elapsedMilliseconds(from: loadStart)

        let warmupStart = uptimeNanoseconds()
        _ = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 6_400))
        )
        let warmupMs = elapsedMilliseconds(from: warmupStart)

        let resourceStart = ResourceUsage.current()
        let inferenceStart = uptimeNanoseconds()
        let result = try await runtime.transcribe(
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
            engine: .paraformerLargeZhInt8,
            engineVersion: "Textify ParaformerRuntime / FluidAudio 0.15.5",
            model: "paraformer-large-zh int8",
            modelLicense: "Apache-2.0 upstream model; conversion inherits upstream terms",
            computeBackend: "Core ML CPU preprocessor + CPU/Apple Neural Engine inference",
            feedMode: feedMode,
            audio: audio,
            modelLoadMs: loadMs,
            warmupMs: warmupMs,
            firstPartialMs: nil,
            partialIntervalsMs: [],
            releaseToFinalMs: inferenceMs,
            inferenceWorkMs: inferenceMs,
            maximumFeedLagMs: 0,
            transcript: result.text,
            reference: reference,
            resources: resources,
            productionMetadata: result
        )
    }
}
