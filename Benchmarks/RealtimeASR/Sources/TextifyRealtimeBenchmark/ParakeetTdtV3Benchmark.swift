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
        let configuration = try configuration(for: engine)
        let modelDirectory = modelsRootURL
            .appendingPathComponent(configuration.modelID, isDirectory: true)
        let runtime = ParakeetRuntime()

        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: configuration.modelID,
            modelDirectory: modelDirectory.path,
            variant: configuration.variant,
            computeRoute: .neuralEngine,
            languageCode: "en",
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
            engine: engine,
            engineVersion: "Textify ParakeetRuntime / FluidAudio 0.15.5",
            model: configuration.modelLabel,
            modelLicense: "CC-BY-4.0",
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
            resources: resources
        )
    }

    private static func configuration(for engine: BenchmarkEngine) throws -> Configuration {
        switch engine {
        case .parakeetTdtV2:
            return Configuration(
                modelID: "parakeet-tdt-0.6b-v2",
                modelLabel: "parakeet-tdt-0.6b-v2 int8",
                variant: .tdtV2
            )
        case .parakeetTdtV3:
            return Configuration(
                modelID: "parakeet-tdt-0.6b-v3",
                modelLabel: "parakeet-tdt-0.6b-v3 int8",
                variant: .tdtV3
            )
        case .parakeetTdtCtc110M:
            return Configuration(
                modelID: "parakeet-tdt-ctc-110m",
                modelLabel: "parakeet-tdt-ctc-110m Core ML",
                variant: .tdtCtc110M
            )
        case .parakeetTdtJapanese:
            return Configuration(
                modelID: "parakeet-ja",
                modelLabel: "parakeet-tdt-0.6b Japanese int8",
                variant: .tdtJapanese
            )
        default:
            throw BenchmarkCLIError.invalidArguments(
                "Parakeet TDT benchmark received unsupported engine: \(engine.rawValue)"
            )
        }
    }

    private struct Configuration {
        let modelID: String
        let modelLabel: String
        let variant: ParakeetModelVariant
    }
}
