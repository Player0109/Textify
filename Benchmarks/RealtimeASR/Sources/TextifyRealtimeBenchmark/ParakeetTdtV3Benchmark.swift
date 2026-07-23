import Foundation
import TextifyTranscription

enum ParakeetTdtBenchmark {
    static func run(
        engine: BenchmarkEngine,
        audio: CanonicalBenchmarkAudio,
        modelsRootURL: URL,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        try await runSingleResidentBenchmark(
            session: makeSession(
                engine: engine,
                modelsRootURL: modelsRootURL,
                feedMode: feedMode
            ),
            audio: audio,
            reference: reference
        )
    }

    static func makeSession(
        engine: BenchmarkEngine,
        modelsRootURL: URL,
        feedMode: FeedMode
    ) throws -> any ResidentBenchmarkSession {
        ParakeetTdtBenchmarkSession(
            engine: engine,
            configuration: try configuration(for: engine),
            modelsRootURL: modelsRootURL,
            feedMode: feedMode
        )
    }

    private static func configuration(for engine: BenchmarkEngine) throws -> Configuration {
        switch engine {
        case .parakeetTdtV2:
            return Configuration(modelID: "parakeet-tdt-0.6b-v2", variant: .tdtV2)
        case .parakeetTdtV3:
            return Configuration(modelID: "parakeet-tdt-0.6b-v3", variant: .tdtV3)
        case .parakeetTdtCtc110M:
            return Configuration(modelID: "parakeet-tdt-ctc-110m", variant: .tdtCtc110M)
        case .parakeetTdtJapanese:
            return Configuration(modelID: "parakeet-ja", variant: .tdtJapanese)
        default:
            throw BenchmarkCLIError.invalidArguments(
                "Parakeet TDT benchmark received unsupported engine: \(engine.rawValue)"
            )
        }
    }

    fileprivate struct Configuration {
        let modelID: String
        let variant: ParakeetModelVariant
    }
}

private final class ParakeetTdtBenchmarkSession: ResidentBenchmarkSession {
    let engine: BenchmarkEngine
    let modelName: String
    private(set) var modelLoadMs = 0
    private(set) var warmupMs = 0

    private let runtime = ParakeetRuntime()
    private let configuration: ParakeetTdtBenchmark.Configuration
    private let modelDirectory: URL
    private let feedMode: FeedMode
    private var loaded = false

    init(
        engine: BenchmarkEngine,
        configuration: ParakeetTdtBenchmark.Configuration,
        modelsRootURL: URL,
        feedMode: FeedMode
    ) {
        self.engine = engine
        self.configuration = configuration
        self.modelName = configuration.modelID
        self.modelDirectory = modelsRootURL
            .appendingPathComponent(configuration.modelID, isDirectory: true)
        self.feedMode = feedMode
    }

    func load() async throws {
        guard !loaded else {
            throw BenchmarkCLIError.benchmarkFailed("Parakeet benchmark session is already loaded")
        }
        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: modelName,
            modelDirectory: modelDirectory.path,
            variant: configuration.variant,
            computeRoute: .neuralEngine,
            languageCode: "en",
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
            throw BenchmarkCLIError.benchmarkFailed("Parakeet benchmark session is not loaded")
        }
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
        return makeResult(
            engine: engine,
            engineVersion: "Textify ParakeetRuntime / FluidAudio 0.15.5",
            model: modelName,
            modelLicense: "CC-BY-4.0",
            computeBackend: "Core ML CPU preprocessor + CPU/Apple Neural Engine inference",
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
