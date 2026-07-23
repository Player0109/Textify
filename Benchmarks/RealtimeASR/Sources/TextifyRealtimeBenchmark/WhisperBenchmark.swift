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
        let session = WhisperBenchmarkSession(
            modelURL: modelURL,
            languageCode: languageCode,
            feedMode: feedMode
        )
        try await session.load()
        return try await session.transcribe(audio: audio, reference: reference)
    }
}

final class WhisperBenchmarkSession: ResidentBenchmarkSession {
    let engine = BenchmarkEngine.whisper
    let modelName: String
    private(set) var modelLoadMs = 0
    private(set) var warmupMs = 0

    private let runtime: WhisperRuntime
    private let modelURL: URL
    private let languageCode: String
    private let feedMode: FeedMode
    private var loaded = false

    init(
        modelURL: URL,
        modelID: String? = nil,
        languageCode: String,
        feedMode: FeedMode
    ) {
        let runtime = WhisperRuntime(queueLabel: "io.github.Player0109.Textify.realtime-benchmark")
        self.runtime = runtime
        self.modelURL = modelURL
        self.modelName = modelID
            ?? ProcessInfo.processInfo.environment["TEXTIFY_BENCHMARK_MODEL_ID"]
            ?? modelURL.deletingPathExtension().lastPathComponent
        self.languageCode = languageCode
        self.feedMode = feedMode
    }

    func load() async throws {
        guard !loaded else {
            throw BenchmarkCLIError.benchmarkFailed("Whisper benchmark session is already loaded")
        }

        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: modelName,
            modelPath: modelURL.path,
            useGPU: true,
            threadCount: ProcessInfo.processInfo.activeProcessorCount,
            warmup: false
        )
        let loadWallMs = elapsedMilliseconds(from: loadStart)
        let runtimeSnapshot = await runtime.snapshot()
        modelLoadMs = runtimeSnapshot.metrics.lastLoadDurationMs ?? loadWallMs

        let warmupStart = uptimeNanoseconds()
        _ = try await runtime.transcribe(
            TranscriptionAudioBuffer(
                sampleRate: CanonicalBenchmarkAudio.sampleRate,
                channelCount: 1,
                samples: Array(repeating: 0, count: CanonicalBenchmarkAudio.sampleRate)
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
        warmupMs = elapsedMilliseconds(from: warmupStart)
        loaded = true
    }

    func transcribe(
        audio: CanonicalBenchmarkAudio,
        reference: String?
    ) async throws -> BenchmarkResult {
        guard loaded else {
            throw BenchmarkCLIError.benchmarkFailed("Whisper benchmark session is not loaded")
        }

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
            modelLoadMs: modelLoadMs,
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

    func unload() async {
        guard loaded else { return }
        await runtime.unload()
        loaded = false
    }
}
