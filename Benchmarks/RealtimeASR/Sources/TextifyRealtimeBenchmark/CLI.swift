import Foundation

@main
enum TextifyRealtimeBenchmarkCLI {
    static func main() async {
        do {
            let options = try BenchmarkOptions.parse(
                arguments: Array(CommandLine.arguments.dropFirst())
            )
            guard FileManager.default.fileExists(atPath: options.audioURL.path) else {
                throw BenchmarkCLIError.invalidAudio(
                    "Audio file does not exist: \(options.audioURL.path)"
                )
            }
            let audio = try CanonicalBenchmarkAudio.load(from: options.audioURL)
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
