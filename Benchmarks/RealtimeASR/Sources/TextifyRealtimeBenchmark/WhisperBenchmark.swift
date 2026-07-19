import Foundation
import TextifyTranscription

enum WhisperBenchmark {
    static func run(
        audio: CanonicalBenchmarkAudio,
        modelURL: URL,
        languageCode: String,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        let runtime = WhisperRuntime(queueLabel: "io.github.Player0109.Textify.realtime-benchmark")
        let modelName = modelURL.deletingPathExtension().lastPathComponent

        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: modelName,
            modelPath: modelURL.path,
            useGPU: true,
            threadCount: ProcessInfo.processInfo.activeProcessorCount,
            warmup: true
        )
        let loadMs = elapsedMilliseconds(from: loadStart)
        let runtimeSnapshot = await runtime.snapshot()
        let warmupMs = runtimeSnapshot.metrics.lastWarmupDurationMs ?? 0

        let resourceStart = ResourceUsage.current()
        let inferenceStart = uptimeNanoseconds()
        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(
                sampleRate: CanonicalBenchmarkAudio.sampleRate,
                channelCount: 1,
                samples: audio.samples
            ),
            options: WhisperTranscriptionOptions(
                language: languageCode,
                translate: false,
                temperature: 0,
                temperatureFallback: [],
                usePreviousContext: false,
                initialPrompt: nil
            )
        )
        let inferenceMs = elapsedMilliseconds(from: inferenceStart)
        let resources = ResourceUsage.current().delta(from: resourceStart)

        return makeResult(
            engine: .whisper,
            engineVersion: "Textify vendored whisper.cpp",
            model: modelName,
            modelLicense: "MIT",
            computeBackend: "whisper.cpp Metal requested; CPU operations remain possible",
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
            resources: resources
        )
    }
}
