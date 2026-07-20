import Foundation
import CLiteRTLM
import Metal

public enum LiteRTLMModelVariant: String, Equatable, Sendable {
    case gemma4_12B = "gemma-4-12b"

    var maximumAudioSamples: Int {
        30 * 16_000
    }
}

public enum LiteRTLMRuntimeFailure: String, Equatable, Codable, Sendable {
    case missingModelFile
    case loadFailed
    case warmupFailed
}

public enum LiteRTLMRuntimeState: Equatable, Sendable {
    case noModel
    case loading(modelID: String)
    case preparing(modelID: String)
    case ready(modelID: String)
    case failed(modelID: String, reason: LiteRTLMRuntimeFailure)
}

public enum LiteRTLMRuntimeError: Error, Equatable, Sendable {
    case missingModelFile(String)
    case unsupportedVariant(String)
    case unsupportedLanguage(String)
    case automaticLanguageDetectionUnsupported
    case loadFailed(String)
    case warmupFailed(String)
    case notLoaded
    case invalidAudioFormat(sampleRate: Int, channelCount: Int)
    case emptyAudio
    case audioTooLong(maximumSamples: Int, actualSamples: Int)
    case temporaryAudioFailed(String)
    case transcriptionFailed(String)
}

struct LiteRTLMSessionResult: Equatable, Sendable {
    let text: String
}

protocol LiteRTLMRuntimeSession: Sendable {
    var backendName: String { get async }
    func transcribe(audioFileURL: URL) async throws -> LiteRTLMSessionResult
    func unload() async
}

struct LiteRTLMRuntimeBackend: Sendable {
    let load: @Sendable (
        _ modelURL: URL,
        _ cacheDirectory: URL,
        _ variant: LiteRTLMModelVariant
    ) async throws -> any LiteRTLMRuntimeSession

    static let native = LiteRTLMRuntimeBackend { modelURL, cacheDirectory, _ in
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw LiteRTLMRuntimeError.loadFailed(
                "The required LiteRT-LM Metal GPU is unavailable."
            )
        }
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        guard let settings = litert_lm_engine_settings_create(
            modelURL.path,
            "gpu",
            nil,
            "gpu"
        ) else {
            throw LiteRTLMRuntimeError.loadFailed(
                "LiteRT-LM could not create GPU engine settings."
            )
        }
        defer { litert_lm_engine_settings_delete(settings) }
        litert_lm_engine_settings_set_max_num_tokens(settings, 2_048)
        litert_lm_engine_settings_set_cache_dir(settings, cacheDirectory.path)
        guard let engine = litert_lm_engine_create(settings) else {
            throw LiteRTLMRuntimeError.loadFailed(
                "LiteRT-LM could not initialize the Gemma 4 GPU engine."
            )
        }
        return NativeLiteRTLMSession(engine: engine)
    }
}

private actor NativeLiteRTLMSession: LiteRTLMRuntimeSession {
    private var engine: OpaquePointer?

    init(engine: OpaquePointer) {
        self.engine = engine
    }

    deinit {
        if let engine {
            litert_lm_engine_delete(engine)
        }
    }

    var backendName: String {
        "litert-metal-gpu"
    }

    func transcribe(audioFileURL: URL) throws -> LiteRTLMSessionResult {
        guard let engine else {
            throw LiteRTLMRuntimeError.notLoaded
        }

        guard let sampler = litert_lm_sampler_params_create(kLiteRtLmSamplerTypeGreedy) else {
            throw LiteRTLMRuntimeError.transcriptionFailed(
                "LiteRT-LM could not create a greedy sampler."
            )
        }
        defer { litert_lm_sampler_params_delete(sampler) }
        litert_lm_sampler_params_set_seed(sampler, 0)

        guard let sessionConfig = litert_lm_session_config_create() else {
            throw LiteRTLMRuntimeError.transcriptionFailed(
                "LiteRT-LM could not create a session configuration."
            )
        }
        defer { litert_lm_session_config_delete(sessionConfig) }
        litert_lm_session_config_set_sampler_params(sessionConfig, sampler)
        litert_lm_session_config_set_max_output_tokens(sessionConfig, 256)

        guard let conversationConfig = litert_lm_conversation_config_create() else {
            throw LiteRTLMRuntimeError.transcriptionFailed(
                "LiteRT-LM could not create a conversation configuration."
            )
        }
        defer { litert_lm_conversation_config_delete(conversationConfig) }
        litert_lm_conversation_config_set_session_config(conversationConfig, sessionConfig)

        guard let conversation = litert_lm_conversation_create(engine, conversationConfig) else {
            throw LiteRTLMRuntimeError.transcriptionFailed(
                "LiteRT-LM could not create a transcript-only conversation."
            )
        }
        defer { litert_lm_conversation_delete(conversation) }

        let message: [String: Any] = [
            "role": "user",
            "content": [
                [
                    "type": "text",
                    "text": "Transcribe this audio exactly. Return only the transcript, "
                        + "with no explanation, labels, or quotation marks.",
                ],
                ["type": "audio", "path": audioFileURL.path],
            ],
        ]
        let messageData = try JSONSerialization.data(withJSONObject: message)
        guard let messageJSON = String(data: messageData, encoding: .utf8) else {
            throw LiteRTLMRuntimeError.transcriptionFailed(
                "LiteRT-LM could not serialize the audio prompt."
            )
        }
        guard let optionalArgs = litert_lm_conversation_optional_args_create() else {
            throw LiteRTLMRuntimeError.transcriptionFailed(
                "LiteRT-LM could not create conversation arguments."
            )
        }
        defer { litert_lm_conversation_optional_args_delete(optionalArgs) }
        litert_lm_conversation_optional_args_set_max_output_tokens(optionalArgs, 256)

        guard let response = litert_lm_conversation_send_message(
            conversation,
            messageJSON,
            nil,
            optionalArgs
        ) else {
            throw LiteRTLMRuntimeError.transcriptionFailed(
                "LiteRT-LM returned no transcription response."
            )
        }
        defer { litert_lm_json_response_delete(response) }
        guard let responseCharacters = litert_lm_json_response_get_string(response) else {
            throw LiteRTLMRuntimeError.transcriptionFailed(
                "LiteRT-LM returned an unreadable transcription response."
            )
        }

        let responseJSON = String(cString: responseCharacters)
        guard let responseData = responseJSON.data(using: .utf8),
              let responseObject = try JSONSerialization.jsonObject(with: responseData)
                as? [String: Any],
              let content = responseObject["content"] as? [[String: Any]]
        else {
            throw LiteRTLMRuntimeError.transcriptionFailed(
                "LiteRT-LM returned invalid response JSON."
            )
        }
        let transcript = content.compactMap { item -> String? in
            guard item["type"] as? String == "text" else {
                return nil
            }
            return item["text"] as? String
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return LiteRTLMSessionResult(text: transcript)
    }

    func unload() {
        if let engine {
            litert_lm_engine_delete(engine)
        }
        engine = nil
    }
}

public actor LiteRTLMRuntime: TranscriptionProvider {
    public static let maximumAudioSamples = 30 * 16_000

    private let backend: LiteRTLMRuntimeBackend
    private let cacheDirectory: URL
    private let temporaryAudioDirectory: URL
    private var session: (any LiteRTLMRuntimeSession)?
    private var loadedConfiguration: LoadedConfiguration?

    public private(set) var state: LiteRTLMRuntimeState = .noModel

    public init(cacheDirectory: String? = nil) {
        let resolvedCacheDirectory = cacheDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? Self.defaultCacheDirectory()
        backend = .native
        self.cacheDirectory = resolvedCacheDirectory
        temporaryAudioDirectory = resolvedCacheDirectory
            .appendingPathComponent("TemporaryAudio", isDirectory: true)
    }

    init(cacheDirectory: URL, backend: LiteRTLMRuntimeBackend) {
        self.backend = backend
        self.cacheDirectory = cacheDirectory
        temporaryAudioDirectory = cacheDirectory
            .appendingPathComponent("TemporaryAudio", isDirectory: true)
    }

    public func load(
        modelID: String,
        modelPath: String,
        variant: LiteRTLMModelVariant,
        languageCode: String,
        warmup: Bool = true
    ) async throws {
        let languageCode = try Self.requireSupportedLanguage(languageCode)
        let requestedConfiguration = LoadedConfiguration(
            modelID: modelID,
            modelPath: modelPath,
            variant: variant,
            languageCode: languageCode
        )
        if case let .ready(loadedModelID) = state,
           loadedModelID == modelID,
           loadedConfiguration == requestedConfiguration,
           session != nil {
            return
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              modelURL.pathExtension.lowercased() == "litertlm"
        else {
            state = .failed(modelID: modelID, reason: .missingModelFile)
            throw LiteRTLMRuntimeError.missingModelFile(modelPath)
        }

        await releaseSession()
        state = .loading(modelID: modelID)

        let loadedSession: any LiteRTLMRuntimeSession
        do {
            loadedSession = try await backend.load(modelURL, cacheDirectory, variant)
            guard await loadedSession.backendName == "litert-metal-gpu" else {
                await loadedSession.unload()
                throw LiteRTLMRuntimeError.loadFailed(
                    "Gemma 4 did not load on the required LiteRT-LM Metal GPU backend."
                )
            }
        } catch {
            state = .failed(modelID: modelID, reason: .loadFailed)
            if let error = error as? LiteRTLMRuntimeError {
                throw error
            }
            throw LiteRTLMRuntimeError.loadFailed(String(describing: error))
        }

        session = loadedSession
        loadedConfiguration = requestedConfiguration
        state = .preparing(modelID: modelID)
        if warmup {
            do {
                _ = try await transcribeWithSession(
                    loadedSession,
                    samples: Array(repeating: 0.01, count: 16_000)
                )
            } catch {
                await releaseSession()
                state = .failed(modelID: modelID, reason: .warmupFailed)
                throw LiteRTLMRuntimeError.warmupFailed(String(describing: error))
            }
        }
        state = .ready(modelID: modelID)
    }

    public func unload() async {
        await releaseSession()
        state = .noModel
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        guard audio.sampleRate == 16_000, audio.channelCount == 1 else {
            throw LiteRTLMRuntimeError.invalidAudioFormat(
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount
            )
        }
        guard !audio.samples.isEmpty else {
            throw LiteRTLMRuntimeError.emptyAudio
        }
        let maximumAudioSamples = loadedConfiguration?.variant.maximumAudioSamples
            ?? Self.maximumAudioSamples
        guard audio.samples.count <= maximumAudioSamples else {
            throw LiteRTLMRuntimeError.audioTooLong(
                maximumSamples: maximumAudioSamples,
                actualSamples: audio.samples.count
            )
        }
        guard let session else {
            throw LiteRTLMRuntimeError.notLoaded
        }

        let audioDurationMs = Int(
            (Double(audio.samples.count) / Double(audio.sampleRate) * 1_000).rounded()
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
            let result = try await transcribeWithSession(session, samples: audio.samples)
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
        } catch let error as LiteRTLMRuntimeError {
            throw error
        } catch {
            throw LiteRTLMRuntimeError.transcriptionFailed(String(describing: error))
        }
    }

    public static func requireSupportedLanguage(_ languageCode: String) throws -> String {
        let normalized = languageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)
            ?? ""
        guard normalized != "auto" else {
            throw LiteRTLMRuntimeError.automaticLanguageDetectionUnsupported
        }
        guard normalized == "en" else {
            throw LiteRTLMRuntimeError.unsupportedLanguage(languageCode)
        }
        return normalized
    }

    private func transcribeWithSession(
        _ session: any LiteRTLMRuntimeSession,
        samples: [Float]
    ) async throws -> LiteRTLMSessionResult {
        let audioURL: URL
        do {
            try FileManager.default.createDirectory(
                at: temporaryAudioDirectory,
                withIntermediateDirectories: true
            )
            audioURL = temporaryAudioDirectory
                .appendingPathComponent("Textify-LiteRTLM-\(UUID().uuidString).wav")
            try LiteRTLMPCM16WAV.data(samples: samples).write(to: audioURL, options: .atomic)
        } catch {
            throw LiteRTLMRuntimeError.temporaryAudioFailed(String(describing: error))
        }
        defer { try? FileManager.default.removeItem(at: audioURL) }
        return try await session.transcribe(audioFileURL: audioURL)
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

    private static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("io.github.Player0109.Textify", isDirectory: true)
            .appendingPathComponent("LiteRTLM", isDirectory: true)
    }

    private struct LoadedConfiguration: Equatable, Sendable {
        let modelID: String
        let modelPath: String
        let variant: LiteRTLMModelVariant
        let languageCode: String
    }
}

enum LiteRTLMPCM16WAV {
    static func data(samples: [Float]) -> Data {
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data()
        data.reserveCapacity(44 + Int(byteCount))
        data.append(contentsOf: Data("RIFF".utf8))
        append(UInt32(36) + byteCount, to: &data)
        data.append(contentsOf: Data("WAVE".utf8))
        data.append(contentsOf: Data("fmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(16_000), to: &data)
        append(UInt32(32_000), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: Data("data".utf8))
        append(byteCount, to: &data)
        for sample in samples {
            let finiteSample = sample.isFinite ? sample : 0
            let clamped = min(1, max(-1, finiteSample))
            append(Int16((clamped * 32_767).rounded()), to: &data)
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
