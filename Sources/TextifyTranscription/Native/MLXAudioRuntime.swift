import Foundation
import Metal
import MLX
import MLXAudioSTT

public enum MLXAudioModelVariant: String, Equatable, Sendable {
    case parakeetRNNT1_1B = "parakeet-rnnt-1.1b"
    case parakeetTDT0_6BV2 = "parakeet-tdt-0.6b-v2"
    case parakeetTDT0_6BV3 = "parakeet-tdt-0.6b-v3"
    case nemotron3_5ASRStreaming0_6B = "nemotron-3.5-asr-streaming-0.6b"
    case cohereTranscribe03_2026 = "cohere-transcribe-03-2026"
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case qwen3ASR0_6B8Bit = "qwen3-asr-0.6b-8bit"
    case qwen3ASR1_7B8Bit = "qwen3-asr-1.7b-8bit"

    public var supportsAutomaticLanguageDetection: Bool {
        switch self {
        case .parakeetTDT0_6BV3, .nemotron3_5ASRStreaming0_6B,
             .qwen3ASR0_6B8Bit, .qwen3ASR1_7B8Bit:
            return true
        case .parakeetRNNT1_1B, .parakeetTDT0_6BV2,
             .cohereTranscribe03_2026, .whisperLargeV3Turbo:
            return false
        }
    }

    var maximumAudioSamples: Int {
        switch self {
        case .parakeetRNNT1_1B, .parakeetTDT0_6BV2, .parakeetTDT0_6BV3,
             .nemotron3_5ASRStreaming0_6B:
            return 60 * 16000
        case .cohereTranscribe03_2026:
            return 30 * 16000
        case .whisperLargeV3Turbo:
            return 60 * 16000
        case .qwen3ASR0_6B8Bit, .qwen3ASR1_7B8Bit:
            return 60 * 16000
        }
    }

    var requiredFilenames: [String] {
        switch self {
        case .parakeetRNNT1_1B:
            return ["config.json", "model.safetensors"]
        case .parakeetTDT0_6BV2, .parakeetTDT0_6BV3:
            return [
                "config.json",
                "model.safetensors",
                "tokenizer.model",
                "tokenizer.vocab",
                "vocab.txt",
            ]
        case .nemotron3_5ASRStreaming0_6B:
            return [
                "config.json",
                "model.safetensors",
                "tokenizer.model",
                "vocab.txt",
            ]
        case .cohereTranscribe03_2026:
            return [
                "config.json",
                "model.safetensors",
                "tokenizer.model",
                "tokenizer_config.json",
            ]
        case .whisperLargeV3Turbo:
            return [
                "config.json",
                "weights.safetensors",
                "tokenizer.json",
                "tokenizer_config.json",
                "special_tokens_map.json",
                "added_tokens.json",
                "vocab.json",
                "merges.txt",
                "normalizer.json",
                "generation_config.json",
            ]
        case .qwen3ASR0_6B8Bit, .qwen3ASR1_7B8Bit:
            return [
                "config.json",
                "model.safetensors",
                "chat_template.json",
                "generation_config.json",
                "model.safetensors.index.json",
                "preprocessor_config.json",
                "tokenizer_config.json",
                "vocab.json",
                "merges.txt",
            ]
        }
    }
}

public enum MLXAudioRuntimeFailure: String, Equatable, Codable, Sendable {
    case missingModelDirectory
    case missingModelFile
    case loadFailed
    case warmupFailed
}

public enum MLXAudioRuntimeState: Equatable, Sendable {
    case noModel
    case loading(modelID: String)
    case preparing(modelID: String)
    case ready(modelID: String)
    case failed(modelID: String, reason: MLXAudioRuntimeFailure)
}

public enum MLXAudioRuntimeError: Error, Equatable, Sendable {
    case missingModelDirectory(String)
    case missingModelFile(String)
    case unsupportedVariant(String)
    case unsupportedLanguage(String)
    case automaticLanguageDetectionUnsupported
    case automaticLanguageDetectionRequired
    case loadFailed(String)
    case warmupFailed(String)
    case notLoaded
    case invalidAudioFormat(sampleRate: Int, channelCount: Int)
    case emptyAudio
    case audioTooLong(maximumSamples: Int, actualSamples: Int)
    case transcriptionFailed(String)
}

struct MLXAudioSessionResult: Equatable {
    let text: String
}

protocol MLXAudioRuntimeSession: Sendable {
    var backendName: String { get async }
    func transcribe(samples: [Float]) async throws -> MLXAudioSessionResult
    func unload() async
}

struct MLXAudioRuntimeBackend {
    let load: @Sendable (
        _ modelDirectory: URL,
        _ variant: MLXAudioModelVariant
    ) async throws -> any MLXAudioRuntimeSession

    static let native = MLXAudioRuntimeBackend { modelDirectory, variant in
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw MLXAudioRuntimeError.loadFailed("The required MLX Metal GPU is unavailable.")
        }
        switch variant {
        case .parakeetRNNT1_1B, .parakeetTDT0_6BV2, .parakeetTDT0_6BV3:
            return try Device.withDefaultDevice(.gpu) {
                try NativeParakeetRNNTSession(
                    model: ParakeetModel.fromDirectory(modelDirectory)
                )
            }
        case .nemotron3_5ASRStreaming0_6B:
            return try Device.withDefaultDevice(.gpu) {
                try NativeNemotronASRSession(
                    model: NemotronASRModel.fromDirectory(modelDirectory)
                )
            }
        case .cohereTranscribe03_2026:
            return try Device.withDefaultDevice(.gpu) {
                try NativeCohereTranscribeSession(
                    model: CohereTranscribeModel.fromDirectory(modelDirectory)
                )
            }
        case .whisperLargeV3Turbo:
            return try await Device.withDefaultDevice(.gpu) {
                try NativeWhisperSession(
                    model: await WhisperModel.fromDirectory(modelDirectory)
                )
            }
        case .qwen3ASR0_6B8Bit, .qwen3ASR1_7B8Bit:
            return try await Device.withDefaultDevice(.gpu) {
                try NativeQwen3ASRSession(
                    model: await Qwen3ASRModel.fromModelDirectory(modelDirectory)
                )
            }
        }
    }
}

private actor NativeNemotronASRSession: MLXAudioRuntimeSession {
    private var model: NemotronASRModel?

    init(model: NemotronASRModel) {
        self.model = model
    }

    var backendName: String {
        Device.defaultDevice().deviceType == .gpu ? "mlx-metal" : ""
    }

    func transcribe(samples: [Float]) throws -> MLXAudioSessionResult {
        guard let model else {
            throw MLXAudioRuntimeError.notLoaded
        }
        let output = Device.withDefaultDevice(.gpu) {
            model.generate(
                audio: MLXArray(samples),
                generationParameters: STTGenerateParameters(
                    maxTokens: model.defaultGenerationParameters.maxTokens,
                    temperature: 0,
                    topP: 1,
                    language: "auto",
                    chunkDuration: 60,
                    minChunkDuration: 0.1
                )
            )
        }
        return MLXAudioSessionResult(text: output.text)
    }

    func unload() {
        model = nil
        Memory.clearCache()
    }
}

private actor NativeParakeetRNNTSession: MLXAudioRuntimeSession {
    private var model: ParakeetModel?

    init(model: ParakeetModel) {
        self.model = model
    }

    var backendName: String {
        Device.defaultDevice().deviceType == .gpu ? "mlx-metal" : ""
    }

    func transcribe(samples: [Float]) throws -> MLXAudioSessionResult {
        guard let model else {
            throw MLXAudioRuntimeError.notLoaded
        }
        let output = Device.withDefaultDevice(.gpu) {
            model.generate(audio: MLXArray(samples))
        }
        return MLXAudioSessionResult(text: output.text)
    }

    func unload() {
        model = nil
        Memory.clearCache()
    }
}

private actor NativeCohereTranscribeSession: MLXAudioRuntimeSession {
    private var model: CohereTranscribeModel?

    init(model: CohereTranscribeModel) {
        self.model = model
    }

    var backendName: String {
        Device.defaultDevice().deviceType == .gpu ? "mlx-metal" : ""
    }

    func transcribe(samples: [Float]) throws -> MLXAudioSessionResult {
        guard let model else {
            throw MLXAudioRuntimeError.notLoaded
        }
        let output = Device.withDefaultDevice(.gpu) {
            model.generate(
                audio: MLXArray(samples),
                generationParameters: STTGenerateParameters(
                    maxTokens: model.defaultGenerationParameters.maxTokens,
                    temperature: 0,
                    topP: 1,
                    language: "en",
                    chunkDuration: 30
                )
            )
        }
        return MLXAudioSessionResult(text: output.text)
    }

    func unload() {
        model = nil
        Memory.clearCache()
    }
}

private actor NativeWhisperSession: MLXAudioRuntimeSession {
    private var model: WhisperModel?

    init(model: WhisperModel) {
        self.model = model
    }

    var backendName: String {
        Device.defaultDevice().deviceType == .gpu ? "mlx-metal" : ""
    }

    func transcribe(samples: [Float]) throws -> MLXAudioSessionResult {
        guard let model else {
            throw MLXAudioRuntimeError.notLoaded
        }
        let output = Device.withDefaultDevice(.gpu) {
            model.generate(
                audio: MLXArray(samples),
                generationParameters: STTGenerateParameters(
                    maxTokens: model.defaultGenerationParameters.maxTokens,
                    temperature: 0,
                    topP: 1,
                    language: "en",
                    chunkDuration: 30,
                    minChunkDuration: 0.1
                )
            )
        }
        return MLXAudioSessionResult(text: output.text)
    }

    func unload() {
        model = nil
        Memory.clearCache()
    }
}

private actor NativeQwen3ASRSession: MLXAudioRuntimeSession {
    private var model: Qwen3ASRModel?

    init(model: Qwen3ASRModel) {
        self.model = model
    }

    var backendName: String {
        Device.defaultDevice().deviceType == .gpu ? "mlx-metal" : ""
    }

    func transcribe(samples: [Float]) throws -> MLXAudioSessionResult {
        guard let model else {
            throw MLXAudioRuntimeError.notLoaded
        }
        let output = Device.withDefaultDevice(.gpu) {
            model.generate(
                audio: MLXArray(samples),
                maxTokens: 8192,
                temperature: 0,
                language: nil,
                chunkDuration: 60,
                minChunkDuration: 0.1
            )
        }
        return MLXAudioSessionResult(text: output.text)
    }

    func unload() {
        model = nil
        Memory.clearCache()
    }
}

public actor MLXAudioRuntime: TranscriptionProvider {
    public static let maximumAudioSamples = 60 * 16000

    private let backend: MLXAudioRuntimeBackend
    private var session: (any MLXAudioRuntimeSession)?
    private var loadedConfiguration: LoadedConfiguration?

    public private(set) var state: MLXAudioRuntimeState = .noModel

    public init() {
        backend = .native
    }

    init(backend: MLXAudioRuntimeBackend) {
        self.backend = backend
    }

    public func load(
        modelID: String,
        modelDirectory: String,
        variant: MLXAudioModelVariant,
        languageCode: String,
        warmup: Bool = true
    ) async throws {
        let languageCode = try Self.requireSupportedLanguage(
            languageCode,
            variant: variant
        )
        let requestedConfiguration = LoadedConfiguration(
            modelID: modelID,
            modelDirectory: modelDirectory,
            variant: variant,
            languageCode: languageCode
        )
        if case let .ready(loadedModelID) = state,
           loadedModelID == modelID,
           loadedConfiguration == requestedConfiguration,
           session != nil
        {
            return
        }

        let modelDirectoryURL = URL(fileURLWithPath: modelDirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: modelDirectoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            state = .failed(modelID: modelID, reason: .missingModelDirectory)
            throw MLXAudioRuntimeError.missingModelDirectory(modelDirectory)
        }
        for requiredFilename in variant.requiredFilenames {
            let fileURL = modelDirectoryURL.appendingPathComponent(requiredFilename)
            isDirectory = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                state = .failed(modelID: modelID, reason: .missingModelFile)
                throw MLXAudioRuntimeError.missingModelFile(fileURL.path)
            }
        }

        await releaseSession()
        state = .loading(modelID: modelID)

        let loadedSession: any MLXAudioRuntimeSession
        do {
            loadedSession = try await backend.load(modelDirectoryURL, variant)
            guard await loadedSession.backendName == "mlx-metal" else {
                await loadedSession.unload()
                throw MLXAudioRuntimeError.loadFailed(
                    "The speech model did not load on the required MLX Metal backend."
                )
            }
        } catch {
            state = .failed(modelID: modelID, reason: .loadFailed)
            if let error = error as? MLXAudioRuntimeError {
                throw error
            }
            throw MLXAudioRuntimeError.loadFailed(String(describing: error))
        }

        session = loadedSession
        loadedConfiguration = requestedConfiguration
        state = .preparing(modelID: modelID)
        if warmup {
            do {
                _ = try await loadedSession.transcribe(
                    samples: Array(repeating: 0.01, count: 16000)
                )
            } catch {
                await releaseSession()
                state = .failed(modelID: modelID, reason: .warmupFailed)
                throw MLXAudioRuntimeError.warmupFailed(String(describing: error))
            }
        }
        state = .ready(modelID: modelID)
    }

    public func unload() async {
        await releaseSession()
        state = .noModel
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        guard audio.sampleRate == 16000, audio.channelCount == 1 else {
            throw MLXAudioRuntimeError.invalidAudioFormat(
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount
            )
        }
        guard !audio.samples.isEmpty else {
            throw MLXAudioRuntimeError.emptyAudio
        }
        let maximumAudioSamples = loadedConfiguration?.variant.maximumAudioSamples
            ?? Self.maximumAudioSamples
        guard audio.samples.count <= maximumAudioSamples else {
            throw MLXAudioRuntimeError.audioTooLong(
                maximumSamples: maximumAudioSamples,
                actualSamples: audio.samples.count
            )
        }
        guard let session else {
            throw MLXAudioRuntimeError.notLoaded
        }

        let audioDurationMs = Int(
            (Double(audio.samples.count) / Double(audio.sampleRate) * 1000).rounded()
        )
        guard audio.samples.contains(where: { abs($0) >= 0.001 }) else {
            return TranscriptionResult(
                text: "",
                noSpeechProbability: 1,
                averageLogProbability: -10,
                compressionRatio: 1,
                timing: TranscriptionTiming(
                    audioDurationMs: audioDurationMs,
                    inferenceDurationMs: 0
                )
            )
        }

        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let result = try await session.transcribe(samples: audio.samples)
            let inferenceDurationMs = Int(
                (DispatchTime.now().uptimeNanoseconds - start + 999_999) / 1_000_000
            )
            let hasLinguisticContent = result.text.unicodeScalars.contains {
                CharacterSet.alphanumerics.contains($0)
            }
            return TranscriptionResult(
                text: result.text,
                noSpeechProbability: hasLinguisticContent ? 0 : 1,
                averageLogProbability: hasLinguisticContent ? 0 : -10,
                compressionRatio: 1,
                timing: TranscriptionTiming(
                    audioDurationMs: audioDurationMs,
                    inferenceDurationMs: inferenceDurationMs
                )
            )
        } catch let error as MLXAudioRuntimeError {
            throw error
        } catch {
            throw MLXAudioRuntimeError.transcriptionFailed(String(describing: error))
        }
    }

    public static func requireSupportedLanguage(
        _ languageCode: String,
        variant: MLXAudioModelVariant = .parakeetRNNT1_1B
    ) throws -> String {
        let normalized = languageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)
            ?? ""
        if variant.supportsAutomaticLanguageDetection {
            guard normalized == "auto" else {
                throw MLXAudioRuntimeError.automaticLanguageDetectionRequired
            }
            return normalized
        }
        guard normalized != "auto" else {
            throw MLXAudioRuntimeError.automaticLanguageDetectionUnsupported
        }
        guard normalized == "en" else {
            throw MLXAudioRuntimeError.unsupportedLanguage(languageCode)
        }
        return normalized
    }

    private func releaseSession() async {
        guard let session else {
            loadedConfiguration = nil
            return
        }
        self.session = nil
        loadedConfiguration = nil
        await session.unload()
    }

    private struct LoadedConfiguration: Equatable {
        let modelID: String
        let modelDirectory: String
        let variant: MLXAudioModelVariant
        let languageCode: String
    }
}
