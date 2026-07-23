import Foundation

@main
enum TextifyRealtimeBenchmarkCLI {
    static func main() async {
        do {
            let options = try BenchmarkOptions.parse(
                arguments: Array(CommandLine.arguments.dropFirst())
            )
            if options.batchJobsURL != nil {
                try await BatchBenchmark.run(options: options)
                return
            }
            guard let audioURL = options.audioURL else {
                throw BenchmarkCLIError.invalidArguments("--audio is required")
            }
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw BenchmarkCLIError.invalidAudio(
                    "Audio file does not exist: \(audioURL.path)"
                )
            }
            let audio = try CanonicalBenchmarkAudio.load(from: audioURL)
            guard !audio.samples.isEmpty else {
                throw BenchmarkCLIError.invalidAudio("Audio file contains no samples")
            }

            let result: BenchmarkResult
            switch options.engine {
            case .appleDictationAnalyzer:
                result = try await AppleDictationAnalyzerBenchmark.run(
                    audio: audio,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .appleSpeechAnalyzer:
                result = try await AppleSpeechAnalyzerBenchmark.run(
                    audio: audio,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .whisper:
                result = try await WhisperBenchmark.run(
                    audio: audio,
                    modelURL: options.whisperModelURL!,
                    languageCode: options.languageCode,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .parakeetEou160:
                result = try await ParakeetEouBenchmark.run(
                    audio: audio,
                    cacheURL: options.fluidCacheURL,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .parakeetUnified320:
                result = try await ParakeetBenchmark.run(
                    audio: audio,
                    cacheURL: options.fluidCacheURL,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .parakeetTdtV2, .parakeetTdtV3, .parakeetTdtCtc110M,
                 .parakeetTdtJapanese:
                result = try await ParakeetTdtBenchmark.run(
                    engine: options.engine,
                    audio: audio,
                    modelsRootURL: options.fluidCacheURL,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .paraformerLargeZhInt8:
                result = try await ParaformerBenchmark.run(
                    audio: audio,
                    modelsRootURL: options.fluidCacheURL,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .reazonSpeechK2V2, .qwen3ASR0_6B, .omnilingualASR300M,
                 .dolphinSmall, .senseVoiceSmall:
                result = try await SherpaOnnxBenchmark.run(
                    engine: options.engine,
                    audio: audio,
                    runtimeDirectoryURL: options.sherpaRuntimeURL!,
                    modelDirectoryURL: options.sherpaModelURL!,
                    provider: options.sherpaProvider,
                    threadCount: options.sherpaThreadCount,
                    languageCode: options.languageCode,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .mlxParakeetRNNT1_1B:
                result = try await MLXAudioBenchmark.run(
                    engine: options.engine,
                    variant: .parakeetRNNT1_1B,
                    modelID: "parakeet-rnnt-1.1b",
                    modelLicense: "CC-BY-4.0",
                    audio: audio,
                    modelDirectoryURL: options.mlxModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .mlxCohereTranscribe03_2026:
                result = try await MLXAudioBenchmark.run(
                    engine: options.engine,
                    variant: .cohereTranscribe03_2026,
                    modelID: "cohere-transcribe-03-2026-mlx-8bit",
                    modelLicense: "Apache-2.0",
                    audio: audio,
                    modelDirectoryURL: options.mlxModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .mlxWhisperLargeV3Turbo:
                result = try await MLXAudioBenchmark.run(
                    engine: options.engine,
                    variant: .whisperLargeV3Turbo,
                    modelID: "mlx-community/whisper-large-v3-turbo",
                    modelLicense: "MIT",
                    audio: audio,
                    modelDirectoryURL: options.mlxModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .mlxQwen3ASR0_6B8Bit:
                result = try await MLXAudioBenchmark.run(
                    engine: options.engine,
                    variant: .qwen3ASR0_6B8Bit,
                    modelID: "mlx-community/Qwen3-ASR-0.6B-8bit",
                    modelLicense: "Apache-2.0",
                    audio: audio,
                    modelDirectoryURL: options.mlxModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .mlxQwen3ASR1_7B8Bit:
                result = try await MLXAudioBenchmark.run(
                    engine: options.engine,
                    variant: .qwen3ASR1_7B8Bit,
                    modelID: "mlx-community/Qwen3-ASR-1.7B-8bit",
                    modelLicense: "Apache-2.0",
                    audio: audio,
                    modelDirectoryURL: options.mlxModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .mlxParakeetTDT0_6BV2:
                result = try await MLXAudioBenchmark.run(
                    engine: options.engine,
                    variant: .parakeetTDT0_6BV2,
                    modelID: "mlx-community/parakeet-tdt-0.6b-v2",
                    modelLicense: "CC-BY-4.0",
                    audio: audio,
                    modelDirectoryURL: options.mlxModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .mlxParakeetTDT0_6BV3:
                result = try await MLXAudioBenchmark.run(
                    engine: options.engine,
                    variant: .parakeetTDT0_6BV3,
                    modelID: "mlx-community/parakeet-tdt-0.6b-v3",
                    modelLicense: "CC-BY-4.0",
                    audio: audio,
                    modelDirectoryURL: options.mlxModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .mlxNemotron3_5ASRStreaming0_6B:
                result = try await MLXAudioBenchmark.run(
                    engine: options.engine,
                    variant: .nemotron3_5ASRStreaming0_6B,
                    modelID: "mlx-community/nemotron-3.5-asr-streaming-0.6b",
                    modelLicense: "NVIDIA Open Model License",
                    audio: audio,
                    modelDirectoryURL: options.mlxModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .canaryQwen2_5B:
                result = try await TranscribeCppBenchmark.runCanaryQwen(
                    audio: audio,
                    runtimeDirectoryURL: options.transcribeRuntimeURL!,
                    modelURL: options.transcribeModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .transcribeQwen3ASR0_6B:
                result = try await TranscribeCppBenchmark.runModel(
                    engine: options.engine,
                    variant: .qwen3ASR0_6B,
                    languageCode: "auto",
                    modelLicense: "Apache-2.0",
                    audio: audio,
                    runtimeDirectoryURL: options.transcribeRuntimeURL!,
                    modelURL: options.transcribeModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .transcribeQwen3ASR1_7B:
                result = try await TranscribeCppBenchmark.runModel(
                    engine: options.engine,
                    variant: .qwen3ASR1_7B,
                    languageCode: "auto",
                    modelLicense: "Apache-2.0",
                    audio: audio,
                    runtimeDirectoryURL: options.transcribeRuntimeURL!,
                    modelURL: options.transcribeModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .transcribeParakeetTDT0_6BV2:
                result = try await TranscribeCppBenchmark.runModel(
                    engine: options.engine,
                    variant: .parakeetTDT0_6BV2,
                    languageCode: "en",
                    modelLicense: "CC-BY-4.0",
                    audio: audio,
                    runtimeDirectoryURL: options.transcribeRuntimeURL!,
                    modelURL: options.transcribeModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .transcribeParakeetTDT0_6BV3:
                result = try await TranscribeCppBenchmark.runModel(
                    engine: options.engine,
                    variant: .parakeetTDT0_6BV3,
                    languageCode: "auto",
                    modelLicense: "CC-BY-4.0",
                    audio: audio,
                    runtimeDirectoryURL: options.transcribeRuntimeURL!,
                    modelURL: options.transcribeModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .transcribeNemotron3_5ASRStreaming0_6B:
                result = try await TranscribeCppBenchmark.runModel(
                    engine: options.engine,
                    variant: .nemotron3_5ASRStreaming0_6B,
                    languageCode: "auto",
                    modelLicense: "OpenMDW-1.1",
                    audio: audio,
                    runtimeDirectoryURL: options.transcribeRuntimeURL!,
                    modelURL: options.transcribeModelURL!,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            case .liteRTGemma4_12B:
                result = try await LiteRTLMBenchmark.runGemma4(
                    audio: audio,
                    modelURL: options.liteRTModelURL!,
                    cacheURL: options.liteRTCacheURL,
                    reference: options.reference,
                    feedMode: options.feedMode
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(result)
            if let outputURL = options.outputURL {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: outputURL, options: .atomic)
                print(outputURL.path)
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(2)
        }
    }
}
