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
        guard let computeRoute = SherpaOnnxComputeRoute(rawValue: provider) else {
            throw BenchmarkCLIError.invalidArguments("Unknown sherpa-onnx provider: \(provider)")
        }
        let variant: SherpaOnnxModelVariant
        let modelID: String
        let modelName: String
        switch engine {
        case .reazonSpeechK2V2:
            variant = .reazonSpeechK2V2
            modelID = "reazonspeech-k2-v2-int8"
            modelName = "ReazonSpeech K2 V2 int8"
        case .qwen3ASR0_6B:
            variant = .qwen3ASR0_6B
            modelID = "qwen3-asr-0.6b-int8"
            modelName = "Qwen3-ASR 0.6B int8"
        case .omnilingualASR300M:
            variant = .omnilingualASR300M
            modelID = "omnilingual-asr-300m-ctc-int8"
            modelName = "Omnilingual ASR CTC 300M int8"
        case .dolphinSmall:
            variant = .dolphinSmall
            modelID = "dolphin-small-ctc-multi-lang-int8"
            modelName = "Dolphin Small CTC multilingual int8"
        case .senseVoiceSmall:
            variant = .senseVoiceSmall
            modelID = "sensevoice-small-int8-2024-07-17"
            modelName = "SenseVoiceSmall int8 2024-07-17"
        default:
            throw BenchmarkCLIError.invalidArguments("Unsupported sherpa-onnx engine")
        }
        let runtime = SherpaOnnxRuntime(runtimeDirectory: runtimeDirectoryURL.path)

        let loadStart = uptimeNanoseconds()
        try await runtime.load(
            modelID: modelID,
            modelDirectory: modelDirectoryURL.path,
            variant: variant,
            languageCode: languageCode,
            computeRoute: computeRoute,
            threadCount: threadCount,
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
        let transcript = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: audio.samples)
        )
        let finalTimestamp = uptimeNanoseconds()
        let resources = ResourceUsage.current().delta(from: resourceStart)
        await runtime.unload()
        let inferenceMs = elapsedMilliseconds(from: inferenceStart, to: finalTimestamp)

        return makeResult(
            engine: engine,
            engineVersion: "sherpa-onnx 1.13.2 / ONNX Runtime 1.24.4",
            model: modelName,
            modelLicense: engine == .senseVoiceSmall ? "FunASR Model License 1.1" : "Apache-2.0",
            computeBackend: "ONNX Runtime \(provider) (\(threadCount) threads)",
            feedMode: feedMode,
            audio: audio,
            modelLoadMs: loadMs,
            warmupMs: warmupMs,
            firstPartialMs: nil,
            partialIntervalsMs: [],
            releaseToFinalMs: inferenceMs,
            inferenceWorkMs: inferenceMs,
            maximumFeedLagMs: 0,
            transcript: transcript.text,
            reference: reference,
            resources: resources
        )
    }
}
