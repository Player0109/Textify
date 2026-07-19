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
}

enum FeedMode: String, Codable {
    case realtime
    case accelerated
}

struct BenchmarkOptions {
    let engine: BenchmarkEngine
    let audioURL: URL
    let reference: String?
    let whisperModelURL: URL?
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
                "--engine must be apple-dictation-analyzer, apple-speech-analyzer, whisper, parakeet-eou-160, parakeet-unified-320, parakeet-tdt-v2, parakeet-tdt-v3, parakeet-tdt-ctc-110m, parakeet-tdt-ja, paraformer-large-zh-int8, reazonspeech-k2-v2, qwen3-asr-0.6b, omnilingual-asr-300m-ctc-int8, dolphin-small-ctc-multi-lang-int8, or sensevoice-small-int8"
            )
        }
        guard let audioPath = values["--audio"] else {
            throw BenchmarkCLIError.invalidArguments("--audio is required")
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
        let sherpaRuntimeURL = values["--sherpa-runtime"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        let sherpaModelURL = values["--sherpa-model"].map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        if engine == .reazonSpeechK2V2 || engine == .qwen3ASR0_6B
            || engine == .omnilingualASR300M || engine == .dolphinSmall
            || engine == .senseVoiceSmall,
           sherpaRuntimeURL == nil || sherpaModelURL == nil {
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
        guard (1...16).contains(sherpaThreadCount) else {
            throw BenchmarkCLIError.invalidArguments(
                "--sherpa-threads must be between 1 and 16"
            )
        }

        return BenchmarkOptions(
            engine: engine,
            audioURL: URL(fileURLWithPath: audioPath).standardizedFileURL,
            reference: values["--reference"],
            whisperModelURL: whisperModelURL,
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
        case .invalidArguments(let message),
             .invalidAudio(let message),
             .benchmarkFailed(let message):
            return message
        }
    }
}
