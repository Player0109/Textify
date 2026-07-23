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
        try await runSingleResidentBenchmark(
            session: TranscribeCppBenchmarkSession(
                engine: .canaryQwen2_5B,
                variant: .canaryQwen2_5B,
                languageCode: "en",
                modelLicense: "CC-BY-4.0 + Apache-2.0",
                runtimeDirectoryURL: runtimeDirectoryURL,
                modelURL: modelURL,
                feedMode: feedMode
            ),
            audio: audio,
            reference: reference
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
        try await runSingleResidentBenchmark(
            session: TranscribeCppBenchmarkSession(
                engine: engine,
                variant: variant,
                languageCode: languageCode,
                modelLicense: modelLicense,
                runtimeDirectoryURL: runtimeDirectoryURL,
                modelURL: modelURL,
                feedMode: feedMode
            ),
            audio: audio,
            reference: reference
        )
    }

    static func makeSession(
        engine: BenchmarkEngine,
        runtimeDirectoryURL: URL,
        modelURL: URL,
        feedMode: FeedMode
    ) throws -> any ResidentBenchmarkSession {
        let configuration: (TranscribeCppModelVariant, String, String)
        switch engine {
        case .canaryQwen2_5B:
            configuration = (.canaryQwen2_5B, "en", "CC-BY-4.0 + Apache-2.0")
        case .transcribeQwen3ASR0_6B:
            configuration = (.qwen3ASR0_6B, "auto", "Apache-2.0")
        case .transcribeQwen3ASR1_7B:
            configuration = (.qwen3ASR1_7B, "auto", "Apache-2.0")
        case .transcribeParakeetTDT0_6BV2:
            configuration = (.parakeetTDT0_6BV2, "en", "CC-BY-4.0")
        case .transcribeParakeetTDT0_6BV3:
            configuration = (.parakeetTDT0_6BV3, "auto", "CC-BY-4.0")
        case .transcribeNemotron3_5ASRStreaming0_6B:
            configuration = (.nemotron3_5ASRStreaming0_6B, "auto", "OpenMDW-1.1")
        default:
            throw BenchmarkCLIError.invalidArguments(
                "transcribe.cpp resident session received unsupported engine: \(engine.rawValue)"
            )
        }
        return TranscribeCppBenchmarkSession(
            engine: engine,
            variant: configuration.0,
            languageCode: configuration.1,
            modelLicense: configuration.2,
            runtimeDirectoryURL: runtimeDirectoryURL,
            modelURL: modelURL,
            feedMode: feedMode
        )
    }
}

private final class TranscribeCppBenchmarkSession: ResidentBenchmarkSession {
    let engine: BenchmarkEngine
    let modelName: String
    private(set) var modelLoadMs = 0
    private(set) var warmupMs = 0

    private let runtime: TranscribeCppRuntime
    private let variant: TranscribeCppModelVariant
    private let languageCode: String
    private let modelLicense: String
    private let modelURL: URL
    private let feedMode: FeedMode
    private var loaded = false

    init(
        engine: BenchmarkEngine,
        variant: TranscribeCppModelVariant,
        languageCode: String,
        modelLicense: String,
        runtimeDirectoryURL: URL,
        modelURL: URL,
        feedMode: FeedMode
    ) {
        self.engine = engine
        self.variant = variant
        self.languageCode = languageCode
        self.modelLicense = modelLicense
        self.runtime = TranscribeCppRuntime(runtimeDirectory: runtimeDirectoryURL.path)
        self.modelURL = modelURL
        self.modelName = modelURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        self.feedMode = feedMode
    }

    func load() async throws {
        guard !loaded else {
            throw BenchmarkCLIError.benchmarkFailed(
                "transcribe.cpp benchmark session is already loaded"
            )
        }
        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: modelName,
            modelPath: modelURL.path,
            variant: variant,
            languageCode: languageCode,
            threadCount: 4,
            warmup: false
        )
        modelLoadMs = elapsedMilliseconds(from: loadStart)

        let warmupStart = uptimeNanoseconds()
        _ = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.01, count: 6_400))
        )
        warmupMs = elapsedMilliseconds(from: warmupStart)
        loaded = true
    }

    func transcribe(
        audio: CanonicalBenchmarkAudio,
        reference: String?
    ) async throws -> BenchmarkResult {
        guard loaded else {
            throw BenchmarkCLIError.benchmarkFailed(
                "transcribe.cpp benchmark session is not loaded"
            )
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
            engineVersion: "transcribe.cpp 0.1.3 (5a5a496)",
            model: modelName,
            modelLicense: modelLicense,
            computeBackend: "transcribe.cpp Metal required and verified by Textify runtime",
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
