import Foundation

enum BenchmarkEngine: String, Codable {
    case appleDictationAnalyzer = "apple-dictation-analyzer"
    case appleSpeechAnalyzer = "apple-speech-analyzer"
    case whisper
    case parakeetEou160 = "parakeet-eou-160"
    case parakeetUnified320 = "parakeet-unified-320"
    case parakeetTdtV2 = "parakeet-tdt-v2"
    case parakeetTdtV3 = "parakeet-tdt-v3"
    case parakeetTdtCtc110M = "parakeet-tdt-ctc-110m"
    case parakeetTdtJapanese = "parakeet-tdt-ja"
    case paraformerLargeZhInt8 = "paraformer-large-zh-int8"
    case reazonSpeechK2V2 = "reazonspeech-k2-v2"
    case qwen3ASR0_6B = "qwen3-asr-0.6b"
    case omnilingualASR300M = "omnilingual-asr-300m-ctc-int8"
    case dolphinSmall = "dolphin-small-ctc-multi-lang-int8"
    case senseVoiceSmall = "sensevoice-small-int8"
    case mlxParakeetRNNT1_1B = "mlx-parakeet-rnnt-1.1b"
    case mlxCohereTranscribe03_2026 = "mlx-cohere-transcribe-03-2026"
    case mlxWhisperLargeV3Turbo = "mlx-whisper-large-v3-turbo"
    case mlxQwen3ASR0_6B8Bit = "mlx-qwen3-asr-0.6b-8bit"
    case mlxQwen3ASR1_7B8Bit = "mlx-qwen3-asr-1.7b-8bit"
    case mlxParakeetTDT0_6BV2 = "mlx-parakeet-tdt-0.6b-v2"
    case mlxParakeetTDT0_6BV3 = "mlx-parakeet-tdt-0.6b-v3"
    case mlxNemotron3_5ASRStreaming0_6B = "mlx-nemotron-3.5-asr-streaming-0.6b"
    case canaryQwen2_5B = "canary-qwen-2.5b"
    case transcribeQwen3ASR0_6B = "transcribe-qwen3-asr-0.6b"
    case transcribeQwen3ASR1_7B = "transcribe-qwen3-asr-1.7b"
    case transcribeParakeetTDT0_6BV2 = "transcribe-parakeet-tdt-0.6b-v2"
    case transcribeParakeetTDT0_6BV3 = "transcribe-parakeet-tdt-0.6b-v3"
    case transcribeNemotron3_5ASRStreaming0_6B = "transcribe-nemotron-3.5-asr-streaming-0.6b"
    case liteRTGemma4_12B = "litert-gemma-4-12b"
}

enum FeedMode: String, Codable {
    case realtime
    case accelerated
}

struct BenchmarkOptions {
    let engine: BenchmarkEngine
    let audioURL: URL?
    let batchJobsURL: URL?
    let batchOutputDirectoryURL: URL?
    let reference: String?
    let whisperModelURL: URL?
    let mlxModelURL: URL?
    let transcribeRuntimeURL: URL?
    let transcribeModelURL: URL?
    let liteRTModelURL: URL?
    let liteRTCacheURL: URL
    let languageCode: String
    let fluidCacheURL: URL
    let sherpaRuntimeURL: URL?
    let sherpaModelURL: URL?
    let sherpaProvider: String
    let sherpaThreadCount: Int
    let outputURL: URL?
    let feedMode: FeedMode

    static func parse(arguments: [String]) throws -> BenchmarkOptions {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw BenchmarkCLIError.invalidArguments("Expected --key value, received: \(key)")
            }
            values[key] = arguments[index + 1]
            index += 2
        }

        guard let engineValue = values["--engine"],
              let engine = BenchmarkEngine(rawValue: engineValue)
        else {
            throw BenchmarkCLIError.invalidArguments(
                "--engine must name a supported benchmark engine, including whisper or mlx-parakeet-rnnt-1.1b"
            )
        }
        let audioURL = values["--audio"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        let batchJobsURL = values["--batch-jobs"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        let batchOutputDirectoryURL = values["--batch-output-dir"].map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
        guard (audioURL == nil) != (batchJobsURL == nil) else {
            throw BenchmarkCLIError.invalidArguments(
                "Provide exactly one of --audio or --batch-jobs"
            )
        }
        if batchJobsURL != nil, batchOutputDirectoryURL == nil {
            throw BenchmarkCLIError.invalidArguments(
                "--batch-output-dir is required with --batch-jobs"
            )
        }
        if audioURL != nil, batchOutputDirectoryURL != nil {
            throw BenchmarkCLIError.invalidArguments(
                "--batch-output-dir may only be used with --batch-jobs"
            )
        }

        let feedModeValue = values["--feed-mode"] ?? FeedMode.realtime.rawValue
        guard let feedMode = FeedMode(rawValue: feedModeValue) else {
            throw BenchmarkCLIError.invalidArguments(
                "--feed-mode must be realtime or accelerated"
            )
        }

        let defaultCache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/io.github.Player0109.Textify", isDirectory: true)
            .appendingPathComponent("RealtimeBenchmark/Models", isDirectory: true)

        let whisperModelURL = values["--whisper-model"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        if engine == .whisper, whisperModelURL == nil {
            throw BenchmarkCLIError.invalidArguments(
                "--whisper-model is required for the whisper engine"
            )
        }
        let mlxModelURL = values["--mlx-model"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        if engine == .mlxParakeetRNNT1_1B
            || engine == .mlxCohereTranscribe03_2026
            || engine == .mlxWhisperLargeV3Turbo
            || engine == .mlxQwen3ASR0_6B8Bit
            || engine == .mlxQwen3ASR1_7B8Bit
            || engine == .mlxParakeetTDT0_6BV2
            || engine == .mlxParakeetTDT0_6BV3
            || engine == .mlxNemotron3_5ASRStreaming0_6B,
            mlxModelURL == nil
        {
            throw BenchmarkCLIError.invalidArguments(
                "--mlx-model is required for MLX Audio engines"
            )
        }
        let transcribeRuntimeURL = values["--transcribe-runtime"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        let transcribeModelURL = values["--transcribe-model"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        if engine == .canaryQwen2_5B
            || engine == .transcribeQwen3ASR0_6B
            || engine == .transcribeQwen3ASR1_7B
            || engine == .transcribeParakeetTDT0_6BV2
            || engine == .transcribeParakeetTDT0_6BV3
            || engine == .transcribeNemotron3_5ASRStreaming0_6B,
            transcribeRuntimeURL == nil || transcribeModelURL == nil
        {
            throw BenchmarkCLIError.invalidArguments(
                "--transcribe-runtime and --transcribe-model are required for transcribe.cpp engines"
            )
        }
        let liteRTModelURL = values["--litert-model"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        if engine == .liteRTGemma4_12B, liteRTModelURL == nil {
            throw BenchmarkCLIError.invalidArguments(
                "--litert-model is required for the Gemma 4 LiteRT-LM engine"
            )
        }
        let sherpaRuntimeURL = values["--sherpa-runtime"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        let sherpaModelURL = values["--sherpa-model"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        if engine == .reazonSpeechK2V2 || engine == .qwen3ASR0_6B
            || engine == .omnilingualASR300M || engine == .dolphinSmall
            || engine == .senseVoiceSmall,
            sherpaRuntimeURL == nil || sherpaModelURL == nil
        {
            throw BenchmarkCLIError.invalidArguments(
                "--sherpa-runtime and --sherpa-model are required for sherpa-onnx engines"
            )
        }
        let sherpaProvider = values["--sherpa-provider"] ?? "cpu"
        guard sherpaProvider == "cpu" || sherpaProvider == "coreml" else {
            throw BenchmarkCLIError.invalidArguments(
                "--sherpa-provider must be cpu or coreml"
            )
        }
        let sherpaThreadCount = values["--sherpa-threads"].flatMap(Int.init) ?? 4
        guard (1 ... 16).contains(sherpaThreadCount) else {
            throw BenchmarkCLIError.invalidArguments(
                "--sherpa-threads must be between 1 and 16"
            )
        }

        return BenchmarkOptions(
            engine: engine,
            audioURL: audioURL,
            batchJobsURL: batchJobsURL,
            batchOutputDirectoryURL: batchOutputDirectoryURL,
            reference: values["--reference"],
            whisperModelURL: whisperModelURL,
            mlxModelURL: mlxModelURL,
            transcribeRuntimeURL: transcribeRuntimeURL,
            transcribeModelURL: transcribeModelURL,
            liteRTModelURL: liteRTModelURL,
            liteRTCacheURL: values["--litert-cache"].map {
                URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
            } ?? defaultCache.appendingPathComponent("LiteRTLM", isDirectory: true),
            languageCode: values["--language"] ?? "en",
            fluidCacheURL: values["--fluid-cache"].map {
                URL(fileURLWithPath: $0).standardizedFileURL
            } ?? defaultCache,
            sherpaRuntimeURL: sherpaRuntimeURL,
            sherpaModelURL: sherpaModelURL,
            sherpaProvider: sherpaProvider,
            sherpaThreadCount: sherpaThreadCount,
            outputURL: values["--output"].map {
                URL(fileURLWithPath: $0).standardizedFileURL
            },
            feedMode: feedMode
        )
    }
}

enum BenchmarkCLIError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case invalidAudio(String)
    case benchmarkFailed(String)

    var description: String {
        switch self {
        case let .invalidArguments(message),
             let .invalidAudio(message),
             let .benchmarkFailed(message):
            return message
        }
    }
}
