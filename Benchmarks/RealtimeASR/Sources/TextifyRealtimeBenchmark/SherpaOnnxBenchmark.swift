import Foundation
import TextifyTranscription

enum SherpaOnnxBenchmark {
    static func run(
        engine: BenchmarkEngine = .reazonSpeechK2V2,
        audio: CanonicalBenchmarkAudio,
        runtimeDirectoryURL: URL,
        modelDirectoryURL: URL,
        provider: String = "cpu",
        threadCount: Int = 4,
        languageCode: String = "auto",
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        try await runSingleResidentBenchmark(
            session: makeSession(
                engine: engine,
                runtimeDirectoryURL: runtimeDirectoryURL,
                modelDirectoryURL: modelDirectoryURL,
                provider: provider,
                threadCount: threadCount,
                languageCode: languageCode,
                feedMode: feedMode
            ),
            audio: audio,
            reference: reference
        )
    }

    static func makeSession(
        engine: BenchmarkEngine,
        runtimeDirectoryURL: URL,
        modelDirectoryURL: URL,
        provider: String,
        threadCount: Int,
        languageCode: String,
        feedMode: FeedMode
    ) throws -> any ResidentBenchmarkSession {
        guard let computeRoute = SherpaOnnxComputeRoute(rawValue: provider) else {
            throw BenchmarkCLIError.invalidArguments("Unknown sherpa-onnx provider: \(provider)")
        }
        return SherpaOnnxBenchmarkSession(
            engine: engine,
            configuration: try configuration(for: engine),
            runtimeDirectoryURL: runtimeDirectoryURL,
            modelDirectoryURL: modelDirectoryURL,
            computeRoute: computeRoute,
            provider: provider,
            threadCount: threadCount,
            languageCode: languageCode,
            feedMode: feedMode
        )
    }

    private static func configuration(for engine: BenchmarkEngine) throws -> Configuration {
        switch engine {
        case .reazonSpeechK2V2:
            return Configuration(
                variant: .reazonSpeechK2V2,
                modelID: "reazonspeech-k2-v2-int8",
                license: "Apache-2.0"
            )
        case .qwen3ASR0_6B:
            return Configuration(
                variant: .qwen3ASR0_6B,
                modelID: "qwen3-asr-0.6b-int8",
                license: "Apache-2.0"
            )
        case .dolphinSmall:
            return Configuration(
                variant: .dolphinSmall,
                modelID: "dolphin-small-ctc-multi-lang-int8",
                license: "Apache-2.0"
            )
        case .senseVoiceSmall:
            return Configuration(
                variant: .senseVoiceSmall,
                modelID: "sensevoice-small-int8-2024-07-17",
                license: "FunASR Model License 1.1"
            )
        default:
            throw BenchmarkCLIError.invalidArguments("Unsupported sherpa-onnx engine")
        }
    }

    fileprivate struct Configuration {
        let variant: SherpaOnnxModelVariant
        let modelID: String
        let license: String
    }
}

private final class SherpaOnnxBenchmarkSession: ResidentBenchmarkSession {
    let engine: BenchmarkEngine
    let modelName: String
    private(set) var modelLoadMs = 0
    private(set) var warmupMs = 0

    private let runtime: SherpaOnnxRuntime
    private let configuration: SherpaOnnxBenchmark.Configuration
    private let modelDirectoryURL: URL
    private let computeRoute: SherpaOnnxComputeRoute
    private let provider: String
    private let threadCount: Int
    private let languageCode: String
    private let feedMode: FeedMode
    private var loaded = false

    init(
        engine: BenchmarkEngine,
        configuration: SherpaOnnxBenchmark.Configuration,
        runtimeDirectoryURL: URL,
        modelDirectoryURL: URL,
        computeRoute: SherpaOnnxComputeRoute,
        provider: String,
        threadCount: Int,
        languageCode: String,
        feedMode: FeedMode
    ) {
        self.engine = engine
        self.configuration = configuration
        self.modelName = configuration.modelID
        self.runtime = SherpaOnnxRuntime(runtimeDirectory: runtimeDirectoryURL.path)
        self.modelDirectoryURL = modelDirectoryURL
        self.computeRoute = computeRoute
        self.provider = provider
        self.threadCount = threadCount
        self.languageCode = languageCode
        self.feedMode = feedMode
    }

    func load() async throws {
        guard !loaded else {
            throw BenchmarkCLIError.benchmarkFailed("sherpa-onnx benchmark session is already loaded")
        }
        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: modelName,
            modelDirectory: modelDirectoryURL.path,
            variant: configuration.variant,
            languageCode: languageCode,
            computeRoute: computeRoute,
            threadCount: threadCount,
            warmup: false
        )
        modelLoadMs = elapsedMilliseconds(from: loadStart)

        let warmupStart = uptimeNanoseconds()
        _ = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 6_400))
        )
        warmupMs = elapsedMilliseconds(from: warmupStart)
        loaded = true
    }

    func transcribe(
        audio: CanonicalBenchmarkAudio,
        reference: String?
    ) async throws -> BenchmarkResult {
        guard loaded else {
            throw BenchmarkCLIError.benchmarkFailed("sherpa-onnx benchmark session is not loaded")
        }
        let resourceStart = ResourceUsage.current()
        let inferenceStart = uptimeNanoseconds()
        let transcript = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: audio.samples)
        )
        let inferenceMs = elapsedMilliseconds(from: inferenceStart)
        let resources = ResourceUsage.current().delta(from: resourceStart)
        return makeResult(
            engine: engine,
            engineVersion: "sherpa-onnx 1.13.2 / ONNX Runtime 1.24.4",
            model: modelName,
            modelLicense: configuration.license,
            computeBackend: "ONNX Runtime \(provider) (\(threadCount) threads)",
            feedMode: feedMode,
            audio: audio,
            modelLoadMs: modelLoadMs,
            warmupMs: warmupMs,
            firstPartialMs: nil,
            partialIntervalsMs: [],
            releaseToFinalMs: inferenceMs,
            inferenceWorkMs: inferenceMs,
            maximumFeedLagMs: 0,
            transcript: transcript.text,
            reference: reference,
            resources: resources,
            productionMetadata: transcript
        )
    }

    func unload() async {
        guard loaded else { return }
        await runtime.unload()
        loaded = false
    }
}
