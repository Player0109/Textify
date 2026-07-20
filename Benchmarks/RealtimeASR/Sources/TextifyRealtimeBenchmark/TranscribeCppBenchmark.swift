import Foundation
import TextifyTranscription

enum TranscribeCppBenchmark {
    static func runCanaryQwen(
        audio: CanonicalBenchmarkAudio,
        runtimeDirectoryURL: URL,
        modelURL: URL,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        let runtime = TranscribeCppRuntime(runtimeDirectory: runtimeDirectoryURL.path)

        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: "canary-qwen-2.5b-q4-k-m",
            modelPath: modelURL.path,
            variant: .canaryQwen2_5B,
            languageCode: "en",
            threadCount: 4,
            warmup: false
        )
        let loadMs = elapsedMilliseconds(from: loadStart)

        let warmupStart = uptimeNanoseconds()
        _ = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.01, count: 6400))
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
            engine: .canaryQwen2_5B,
            engineVersion: "transcribe.cpp 0.1.3 (5a5a496)",
            model: "canary-qwen-2.5b-q4-k-m",
            modelLicense: "CC-BY-4.0 + Apache-2.0",
            computeBackend: "transcribe.cpp Metal required and verified by Textify runtime",
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

    static func runModel(
        engine: BenchmarkEngine,
        variant: TranscribeCppModelVariant,
        languageCode: String,
        modelLicense: String,
        audio: CanonicalBenchmarkAudio,
        runtimeDirectoryURL: URL,
        modelURL: URL,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        let runtime = TranscribeCppRuntime(runtimeDirectory: runtimeDirectoryURL.path)
        let modelID = modelURL.deletingPathExtension().lastPathComponent

        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: modelID,
            modelPath: modelURL.path,
            variant: variant,
            languageCode: languageCode,
            threadCount: 4,
            warmup: false
        )
        let loadMs = elapsedMilliseconds(from: loadStart)

        let warmupStart = uptimeNanoseconds()
        _ = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.01, count: 6400))
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
            engineVersion: "transcribe.cpp 0.1.3 (5a5a496)",
            model: modelID,
            modelLicense: modelLicense,
            computeBackend: "transcribe.cpp Metal required and verified by Textify runtime",
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
