import Foundation
import TextifyTranscribeCppShim

public enum TranscribeCppModelVariant: String, Equatable, Sendable {
    case funASRMLTNanoQ8 = "funasr-mlt-nano-2512-q8"
}

public enum TranscribeCppRuntimeFailure: String, Equatable, Codable, Sendable {
    case missingRuntimeDirectory
    case missingModelFile
    case loadFailed
    case warmupFailed
}

public enum TranscribeCppRuntimeState: Equatable, Sendable {
    case noModel
    case loading(modelID: String)
    case preparing(modelID: String)
    case ready(modelID: String)
    case failed(modelID: String, reason: TranscribeCppRuntimeFailure)
}

public enum TranscribeCppRuntimeError: Error, Equatable, Sendable {
    case missingRuntimeDirectory(String)
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
    case transcriptionFailed(String)
}

struct TranscribeCppSessionResult: Equatable, Sendable {
    let text: String
}

protocol TranscribeCppRuntimeSession: Sendable {
    var backendName: String { get async }
    func transcribe(
        samples: [Float],
        sampleRate: Int,
        languageCode: String
    ) async throws -> TranscribeCppSessionResult
    func unload() async
}

struct TranscribeCppRuntimeBackend: Sendable {
    let load: @Sendable (
        _ runtimeDirectory: URL,
        _ modelURL: URL,
        _ variant: TranscribeCppModelVariant,
        _ threadCount: Int
    ) async throws -> any TranscribeCppRuntimeSession

    static let native = TranscribeCppRuntimeBackend {
        runtimeDirectory,
        modelURL,
        variant,
        threadCount in
        guard variant == .funASRMLTNanoQ8 else {
            throw TranscribeCppRuntimeError.unsupportedVariant(variant.rawValue)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw TranscribeCppRuntimeError.missingModelFile(modelURL.path)
        }
        let context = try NativeTranscribeCppSession.makeContext(
            runtimeDirectory: runtimeDirectory,
            modelURL: modelURL,
            threadCount: threadCount
        )
        return NativeTranscribeCppSession(context: context)
    }
}

private actor NativeTranscribeCppSession: TranscribeCppRuntimeSession {
    private var context: OpaquePointer?

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        if let context {
            TextifyTranscribeCppDestroy(context)
        }
    }

    static func makeContext(
        runtimeDirectory: URL,
        modelURL: URL,
        threadCount: Int
    ) throws -> OpaquePointer {
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let context = runtimeDirectory.path.withCString { runtimePath in
            modelURL.path.withCString { modelPath in
                TextifyTranscribeCppCreate(
                    runtimePath,
                    modelPath,
                    Int32(threadCount),
                    &errorBuffer,
                    Int32(errorBuffer.count)
                )
            }
        }
        guard let context else {
            throw TranscribeCppRuntimeError.loadFailed(Self.errorMessage(from: errorBuffer))
        }
        return context
    }

    var backendName: String {
        guard let context else {
            return ""
        }
        var backendBuffer = [CChar](repeating: 0, count: 64)
        let status = TextifyTranscribeCppCopyBackend(
            context,
            &backendBuffer,
            Int32(backendBuffer.count)
        )
        guard status == TextifyTranscribeCppStatusOK else {
            return ""
        }
        return backendBuffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return ""
            }
            return String(cString: baseAddress)
        }
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        languageCode: String
    ) throws -> TranscribeCppSessionResult {
        guard let context else {
            throw TranscribeCppRuntimeError.notLoaded
        }
        var textPointer: UnsafeMutablePointer<CChar>?
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let status = languageCode.withCString { language in
            samples.withUnsafeBufferPointer { buffer in
                TextifyTranscribeCppTranscribe(
                    context,
                    buffer.baseAddress,
                    Int32(buffer.count),
                    Int32(sampleRate),
                    language,
                    &textPointer,
                    &errorBuffer,
                    Int32(errorBuffer.count)
                )
            }
        }
        guard status == TextifyTranscribeCppStatusOK, let textPointer else {
            if let textPointer {
                TextifyTranscribeCppFreeText(textPointer)
            }
            throw TranscribeCppRuntimeError.transcriptionFailed(
                Self.errorMessage(from: errorBuffer)
            )
        }
        defer { TextifyTranscribeCppFreeText(textPointer) }
        return TranscribeCppSessionResult(text: String(cString: textPointer))
    }

    func unload() {
        guard let context else {
            return
        }
        self.context = nil
        TextifyTranscribeCppDestroy(context)
    }

    private static func errorMessage(from buffer: [CChar]) -> String {
        buffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress, baseAddress.pointee != 0 else {
                return "Unknown transcribe.cpp runtime error."
            }
            return String(cString: baseAddress)
        }
    }
}

public actor TranscribeCppRuntime: TranscriptionProvider {
    public static let maximumAudioSamples = 60 * 16_000
    public static let supportedLanguageCodes: Set<String> = [
        "ar", "en", "id", "ja", "ko", "ms", "th", "tl", "vi", "yue", "zh",
    ]

    private let runtimeDirectory: String
    private let backend: TranscribeCppRuntimeBackend
    private var session: (any TranscribeCppRuntimeSession)?
    private var loadedConfiguration: LoadedConfiguration?

    public private(set) var state: TranscribeCppRuntimeState = .noModel

    public init(runtimeDirectory: String? = nil) {
        self.runtimeDirectory = runtimeDirectory
            ?? Bundle.main.privateFrameworksURL?.path
            ?? ""
        self.backend = .native
    }

    init(runtimeDirectory: String, backend: TranscribeCppRuntimeBackend) {
        self.runtimeDirectory = runtimeDirectory
        self.backend = backend
    }

    public func load(
        modelID: String,
        modelPath: String,
        variant: TranscribeCppModelVariant,
        languageCode: String,
        threadCount: Int = 4,
        warmup: Bool = true
    ) async throws {
        let languageCode = try Self.requireSupportedLanguage(languageCode)
        let requestedConfiguration = LoadedConfiguration(
            modelID: modelID,
            modelPath: modelPath,
            variant: variant,
            languageCode: languageCode,
            threadCount: threadCount
        )
        if case let .ready(loadedModelID) = state,
           loadedModelID == modelID,
           loadedConfiguration == requestedConfiguration,
           session != nil {
            return
        }

        let runtimeURL = URL(fileURLWithPath: runtimeDirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard !runtimeDirectory.isEmpty,
              FileManager.default.fileExists(atPath: runtimeURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            state = .failed(modelID: modelID, reason: .missingRuntimeDirectory)
            throw TranscribeCppRuntimeError.missingRuntimeDirectory(runtimeDirectory)
        }

        let modelURL = URL(fileURLWithPath: modelPath, isDirectory: false)
        isDirectory = false
        guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            state = .failed(modelID: modelID, reason: .missingModelFile)
            throw TranscribeCppRuntimeError.missingModelFile(modelPath)
        }
        guard (1...4).contains(threadCount) else {
            state = .failed(modelID: modelID, reason: .loadFailed)
            throw TranscribeCppRuntimeError.loadFailed(
                "The transcribe.cpp thread count must be between 1 and 4."
            )
        }

        await releaseSession()
        state = .loading(modelID: modelID)

        let loadedSession: any TranscribeCppRuntimeSession
        do {
            loadedSession = try await backend.load(
                runtimeURL,
                modelURL,
                variant,
                threadCount
            )
            guard await loadedSession.backendName == "metal" else {
                await loadedSession.unload()
                throw TranscribeCppRuntimeError.loadFailed(
                    "Fun-ASR did not load on the required Metal backend."
                )
            }
        } catch {
            state = .failed(modelID: modelID, reason: .loadFailed)
            if let error = error as? TranscribeCppRuntimeError {
                throw error
            }
            throw TranscribeCppRuntimeError.loadFailed(String(describing: error))
        }

        session = loadedSession
        loadedConfiguration = requestedConfiguration
        state = .preparing(modelID: modelID)
        if warmup {
            do {
                _ = try await loadedSession.transcribe(
                    samples: Array(repeating: 0, count: 6_400),
                    sampleRate: 16_000,
                    languageCode: languageCode
                )
            } catch {
                await releaseSession()
                state = .failed(modelID: modelID, reason: .warmupFailed)
                throw TranscribeCppRuntimeError.warmupFailed(String(describing: error))
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
            throw TranscribeCppRuntimeError.invalidAudioFormat(
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount
            )
        }
        guard !audio.samples.isEmpty else {
            throw TranscribeCppRuntimeError.emptyAudio
        }
        guard audio.samples.count <= Self.maximumAudioSamples else {
            throw TranscribeCppRuntimeError.audioTooLong(
                maximumSamples: Self.maximumAudioSamples,
                actualSamples: audio.samples.count
            )
        }
        guard let session, let loadedConfiguration else {
            throw TranscribeCppRuntimeError.notLoaded
        }

        // Avoid both unnecessary GPU work and known autoregressive
        // hallucinations for digital or near-digital silence. Normal captured
        // speech has already passed Textify's detector and edge trimmer; this
        // remains a defensive boundary for direct runtime callers.
        let hasAudibleSignal = audio.samples.contains { abs($0) >= 0.001 }
        if !hasAudibleSignal {
            let audioDurationMs = Int(
                (Double(audio.samples.count) / Double(audio.sampleRate) * 1_000).rounded()
            )
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
            let result = try await session.transcribe(
                samples: audio.samples,
                sampleRate: audio.sampleRate,
                languageCode: loadedConfiguration.languageCode
            )
            let inferenceDurationMs = Int(
                (DispatchTime.now().uptimeNanoseconds - start + 999_999) / 1_000_000
            )
            let audioDurationMs = Int(
                (Double(audio.samples.count) / Double(audio.sampleRate) * 1_000).rounded()
            )
            let hasLinguisticContent = result.text.unicodeScalars.contains {
                CharacterSet.alphanumerics.contains($0)
            }
            let isEmpty = !hasLinguisticContent
            return TranscriptionResult(
                text: result.text,
                noSpeechProbability: isEmpty ? 1 : 0,
                averageLogProbability: isEmpty ? -10 : 0,
                compressionRatio: 1,
                timing: TranscriptionTiming(
                    audioDurationMs: audioDurationMs,
                    inferenceDurationMs: inferenceDurationMs
                )
            )
        } catch let error as TranscribeCppRuntimeError {
            throw error
        } catch {
            throw TranscribeCppRuntimeError.transcriptionFailed(String(describing: error))
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
            throw TranscribeCppRuntimeError.automaticLanguageDetectionUnsupported
        }
        guard supportedLanguageCodes.contains(normalized) else {
            throw TranscribeCppRuntimeError.unsupportedLanguage(languageCode)
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

    private struct LoadedConfiguration: Equatable, Sendable {
        let modelID: String
        let modelPath: String
        let variant: TranscribeCppModelVariant
        let languageCode: String
        let threadCount: Int
    }
}
