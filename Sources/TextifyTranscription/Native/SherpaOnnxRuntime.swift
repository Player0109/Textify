import Foundation
import TextifySherpaShim

public enum SherpaOnnxModelVariant: String, Equatable, Sendable {
    case reazonSpeechK2V2 = "reazonspeech-k2-v2"
    case qwen3ASR0_6B = "qwen3-asr-0.6b"
    case dolphinSmall = "dolphin-small-ctc-multi-lang-int8"
    case senseVoiceSmall = "sensevoice-small-int8-2024-07-17"
}

public enum SherpaOnnxComputeRoute: String, Equatable, Sendable {
    case cpu
    case coreML = "coreml"
}

public enum SherpaOnnxRuntimeFailure: String, Equatable, Codable, Sendable {
    case missingRuntimeDirectory
    case missingModelDirectory
    case loadFailed
    case warmupFailed
}

public enum SherpaOnnxRuntimeState: Equatable, Sendable {
    case noModel
    case loading(modelID: String)
    case preparing(modelID: String)
    case ready(modelID: String)
    case failed(modelID: String, reason: SherpaOnnxRuntimeFailure)
}

public enum SherpaOnnxRuntimeError: Error, Equatable, Sendable {
    case missingRuntimeDirectory(String)
    case missingModelDirectory(String)
    case missingModelFile(String)
    case unsupportedVariant(String)
    case loadFailed(String)
    case warmupFailed(String)
    case notLoaded
    case invalidAudioFormat(sampleRate: Int, channelCount: Int)
    case emptyAudio
    case audioTooLong(maximumSamples: Int, actualSamples: Int)
    case transcriptionFailed(String)
}

struct SherpaOnnxSessionResult: Equatable, Sendable {
    let text: String
    let averageLogProbability: Float
}

protocol SherpaOnnxRuntimeSession: Sendable {
    func transcribe(samples: [Float], sampleRate: Int) async throws -> SherpaOnnxSessionResult
    func unload() async
}

struct SherpaOnnxRuntimeBackend: Sendable {
    let load: @Sendable (
        _ runtimeDirectory: URL,
        _ modelDirectory: URL,
        _ variant: SherpaOnnxModelVariant,
        _ languageCode: String,
        _ computeRoute: SherpaOnnxComputeRoute,
        _ threadCount: Int
    ) async throws -> any SherpaOnnxRuntimeSession

    static let native = SherpaOnnxRuntimeBackend {
        runtimeDirectory,
        modelDirectory,
        variant,
        languageCode,
        computeRoute,
        threadCount in
        switch variant {
        case .reazonSpeechK2V2:
            guard computeRoute == .cpu else {
                throw SherpaOnnxRuntimeError.loadFailed(
                    "ReazonSpeech requires the sherpa-onnx CPU route."
                )
            }
            let filenames = TransducerFilenames.reazonSpeechK2V2
            let encoderURL = modelDirectory.appendingPathComponent(filenames.encoder)
            let decoderURL = modelDirectory.appendingPathComponent(filenames.decoder)
            let joinerURL = modelDirectory.appendingPathComponent(filenames.joiner)
            let tokensURL = modelDirectory.appendingPathComponent(filenames.tokens)
            try requireFiles([encoderURL, decoderURL, joinerURL, tokensURL])

            let context = try NativeSherpaOnnxSession.makeTransducerContext(
                runtimeDirectory: runtimeDirectory,
                encoderURL: encoderURL,
                decoderURL: decoderURL,
                joinerURL: joinerURL,
                tokensURL: tokensURL,
                threadCount: threadCount
            )
            return NativeSherpaOnnxSession(context: context)

        case .qwen3ASR0_6B:
            let filenames = Qwen3Filenames.int8_0_6B
            let convFrontendURL = modelDirectory.appendingPathComponent(filenames.convFrontend)
            let encoderURL = modelDirectory.appendingPathComponent(filenames.encoder)
            let decoderURL = modelDirectory.appendingPathComponent(filenames.decoder)
            let tokenizerURL = modelDirectory.appendingPathComponent(
                filenames.tokenizerDirectory,
                isDirectory: true
            )
            try requireFiles(
                [convFrontendURL, encoderURL, decoderURL]
                    + filenames.tokenizerFiles.map { tokenizerURL.appendingPathComponent($0) }
            )

            let context = try NativeSherpaOnnxSession.makeQwen3Context(
                runtimeDirectory: runtimeDirectory,
                convFrontendURL: convFrontendURL,
                encoderURL: encoderURL,
                decoderURL: decoderURL,
                tokenizerURL: tokenizerURL,
                computeRoute: computeRoute,
                threadCount: threadCount
            )
            return NativeSherpaOnnxSession(context: context)

        case .dolphinSmall:
            let modelURL = modelDirectory.appendingPathComponent("model.int8.onnx")
            let tokensURL = modelDirectory.appendingPathComponent("tokens.txt")
            try requireFiles([modelURL, tokensURL])
            let context = try NativeSherpaOnnxSession.makeDolphinContext(
                runtimeDirectory: runtimeDirectory,
                modelURL: modelURL,
                tokensURL: tokensURL,
                computeRoute: computeRoute,
                threadCount: threadCount
            )
            return NativeSherpaOnnxSession(context: context)

        case .senseVoiceSmall:
            let modelURL = modelDirectory.appendingPathComponent("model.int8.onnx")
            let tokensURL = modelDirectory.appendingPathComponent("tokens.txt")
            try requireFiles([modelURL, tokensURL])
            let context = try NativeSherpaOnnxSession.makeSenseVoiceContext(
                runtimeDirectory: runtimeDirectory,
                modelURL: modelURL,
                tokensURL: tokensURL,
                languageCode: languageCode,
                computeRoute: computeRoute,
                threadCount: threadCount
            )
            return NativeSherpaOnnxSession(context: context)
        }
    }

    private static func requireFiles(_ fileURLs: [URL]) throws {
        for fileURL in fileURLs where !FileManager.default.fileExists(atPath: fileURL.path) {
            throw SherpaOnnxRuntimeError.missingModelFile(fileURL.path)
        }
    }
}

private struct TransducerFilenames: Sendable {
    let encoder: String
    let decoder: String
    let joiner: String
    let tokens: String

    static let reazonSpeechK2V2 = TransducerFilenames(
        encoder: "encoder-epoch-99-avg-1.int8.onnx",
        decoder: "decoder-epoch-99-avg-1.int8.onnx",
        joiner: "joiner-epoch-99-avg-1.int8.onnx",
        tokens: "tokens.txt"
    )
}

private struct Qwen3Filenames: Sendable {
    let convFrontend: String
    let encoder: String
    let decoder: String
    let tokenizerDirectory: String
    let tokenizerFiles: [String]

    static let int8_0_6B = Qwen3Filenames(
        convFrontend: "conv_frontend.onnx",
        encoder: "encoder.int8.onnx",
        decoder: "decoder.int8.onnx",
        tokenizerDirectory: "tokenizer",
        tokenizerFiles: ["merges.txt", "tokenizer_config.json", "vocab.json"]
    )
}

private actor NativeSherpaOnnxSession: SherpaOnnxRuntimeSession {
    private var context: OpaquePointer?

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        if let context {
            TextifySherpaDestroy(context)
        }
    }

    static func makeTransducerContext(
        runtimeDirectory: URL,
        encoderURL: URL,
        decoderURL: URL,
        joinerURL: URL,
        tokensURL: URL,
        threadCount: Int
    ) throws -> OpaquePointer {
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let context = runtimeDirectory.path.withCString { runtimePath in
            encoderURL.path.withCString { encoderPath in
                decoderURL.path.withCString { decoderPath in
                    joinerURL.path.withCString { joinerPath in
                        tokensURL.path.withCString { tokensPath in
                            TextifySherpaCreateTransducer(
                                runtimePath,
                                encoderPath,
                                decoderPath,
                                joinerPath,
                                tokensPath,
                                Int32(threadCount),
                                &errorBuffer,
                                Int32(errorBuffer.count)
                            )
                        }
                    }
                }
            }
        }
        guard let context else {
            throw SherpaOnnxRuntimeError.loadFailed(Self.errorMessage(from: errorBuffer))
        }
        return context
    }

    static func makeQwen3Context(
        runtimeDirectory: URL,
        convFrontendURL: URL,
        encoderURL: URL,
        decoderURL: URL,
        tokenizerURL: URL,
        computeRoute: SherpaOnnxComputeRoute,
        threadCount: Int
    ) throws -> OpaquePointer {
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let context = runtimeDirectory.path.withCString { runtimePath in
            convFrontendURL.path.withCString { convFrontendPath in
                encoderURL.path.withCString { encoderPath in
                    decoderURL.path.withCString { decoderPath in
                        tokenizerURL.path.withCString { tokenizerPath in
                            computeRoute.rawValue.withCString { provider in
                                TextifySherpaCreateQwen3ASR(
                                    runtimePath,
                                    convFrontendPath,
                                    encoderPath,
                                    decoderPath,
                                    tokenizerPath,
                                    provider,
                                    Int32(threadCount),
                                    &errorBuffer,
                                    Int32(errorBuffer.count)
                                )
                            }
                        }
                    }
                }
            }
        }
        guard let context else {
            throw SherpaOnnxRuntimeError.loadFailed(Self.errorMessage(from: errorBuffer))
        }
        return context
    }

    static func makeDolphinContext(
        runtimeDirectory: URL,
        modelURL: URL,
        tokensURL: URL,
        computeRoute: SherpaOnnxComputeRoute,
        threadCount: Int
    ) throws -> OpaquePointer {
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let context = runtimeDirectory.path.withCString { runtimePath in
            modelURL.path.withCString { modelPath in
                tokensURL.path.withCString { tokensPath in
                    computeRoute.rawValue.withCString { provider in
                        TextifySherpaCreateDolphin(
                            runtimePath,
                            modelPath,
                            tokensPath,
                            provider,
                            Int32(threadCount),
                            &errorBuffer,
                            Int32(errorBuffer.count)
                        )
                    }
                }
            }
        }
        guard let context else {
            throw SherpaOnnxRuntimeError.loadFailed(Self.errorMessage(from: errorBuffer))
        }
        return context
    }

    static func makeSenseVoiceContext(
        runtimeDirectory: URL,
        modelURL: URL,
        tokensURL: URL,
        languageCode: String,
        computeRoute: SherpaOnnxComputeRoute,
        threadCount: Int
    ) throws -> OpaquePointer {
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let context = runtimeDirectory.path.withCString { runtimePath in
            modelURL.path.withCString { modelPath in
                tokensURL.path.withCString { tokensPath in
                    languageCode.withCString { language in
                        computeRoute.rawValue.withCString { provider in
                            TextifySherpaCreateSenseVoice(
                                runtimePath,
                                modelPath,
                                tokensPath,
                                language,
                                provider,
                                Int32(threadCount),
                                &errorBuffer,
                                Int32(errorBuffer.count)
                            )
                        }
                    }
                }
            }
        }
        guard let context else {
            throw SherpaOnnxRuntimeError.loadFailed(Self.errorMessage(from: errorBuffer))
        }
        return context
    }

    func transcribe(samples: [Float], sampleRate: Int) throws -> SherpaOnnxSessionResult {
        guard let context else {
            throw SherpaOnnxRuntimeError.notLoaded
        }
        var textPointer: UnsafeMutablePointer<CChar>?
        var averageLogProbability: Float = -10
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let status = samples.withUnsafeBufferPointer { buffer in
            TextifySherpaTranscribe(
                context,
                buffer.baseAddress,
                Int32(buffer.count),
                Int32(sampleRate),
                &textPointer,
                &averageLogProbability,
                &errorBuffer,
                Int32(errorBuffer.count)
            )
        }
        guard status == TextifySherpaStatusOK, let textPointer else {
            if let textPointer {
                TextifySherpaFreeText(textPointer)
            }
            throw SherpaOnnxRuntimeError.transcriptionFailed(
                Self.errorMessage(from: errorBuffer)
            )
        }
        defer { TextifySherpaFreeText(textPointer) }
        return SherpaOnnxSessionResult(
            text: String(cString: textPointer),
            averageLogProbability: averageLogProbability
        )
    }

    func unload() {
        guard let context else {
            return
        }
        self.context = nil
        TextifySherpaDestroy(context)
    }

    private static func errorMessage(from buffer: [CChar]) -> String {
        buffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress, baseAddress.pointee != 0 else {
                return "Unknown sherpa-onnx runtime error."
            }
            return String(cString: baseAddress)
        }
    }
}

public actor SherpaOnnxRuntime: TranscriptionProvider {
    public static let maximumAudioSamples = 29 * 16_000

    private let runtimeDirectory: String
    private let backend: SherpaOnnxRuntimeBackend
    private var session: (any SherpaOnnxRuntimeSession)?
    private var loadedConfiguration: LoadedConfiguration?

    public private(set) var state: SherpaOnnxRuntimeState = .noModel

    public init(runtimeDirectory: String? = nil) {
        self.runtimeDirectory = runtimeDirectory
            ?? Bundle.main.privateFrameworksURL?.path
            ?? ""
        self.backend = .native
    }

    init(runtimeDirectory: String, backend: SherpaOnnxRuntimeBackend) {
        self.runtimeDirectory = runtimeDirectory
        self.backend = backend
    }

    public func load(
        modelID: String,
        modelDirectory: String,
        variant: SherpaOnnxModelVariant,
        languageCode: String = "auto",
        computeRoute: SherpaOnnxComputeRoute = .cpu,
        threadCount: Int = 4,
        warmup: Bool = true
    ) async throws {
        let requestedConfiguration = LoadedConfiguration(
            modelID: modelID,
            modelDirectory: modelDirectory,
            variant: variant,
            languageCode: languageCode,
            computeRoute: computeRoute,
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
            throw SherpaOnnxRuntimeError.missingRuntimeDirectory(runtimeDirectory)
        }

        let modelURL = URL(fileURLWithPath: modelDirectory, isDirectory: true)
        isDirectory = false
        guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            state = .failed(modelID: modelID, reason: .missingModelDirectory)
            throw SherpaOnnxRuntimeError.missingModelDirectory(modelDirectory)
        }
        guard threadCount > 0, threadCount <= Int(Int32.max) else {
            state = .failed(modelID: modelID, reason: .loadFailed)
            throw SherpaOnnxRuntimeError.loadFailed("Invalid sherpa-onnx thread count.")
        }

        await releaseSession()
        state = .loading(modelID: modelID)

        let loadedSession: any SherpaOnnxRuntimeSession
        do {
            loadedSession = try await backend.load(
                runtimeURL,
                modelURL,
                variant,
                languageCode,
                computeRoute,
                threadCount
            )
        } catch {
            state = .failed(modelID: modelID, reason: .loadFailed)
            if let error = error as? SherpaOnnxRuntimeError {
                throw error
            }
            throw SherpaOnnxRuntimeError.loadFailed(String(describing: error))
        }

        session = loadedSession
        loadedConfiguration = requestedConfiguration
        state = .preparing(modelID: modelID)
        if warmup {
            do {
                _ = try await loadedSession.transcribe(
                    samples: Array(repeating: 0, count: 6_400),
                    sampleRate: 16_000
                )
            } catch {
                await releaseSession()
                state = .failed(modelID: modelID, reason: .warmupFailed)
                throw SherpaOnnxRuntimeError.warmupFailed(String(describing: error))
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
            throw SherpaOnnxRuntimeError.invalidAudioFormat(
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount
            )
        }
        guard !audio.samples.isEmpty else {
            throw SherpaOnnxRuntimeError.emptyAudio
        }
        guard audio.samples.count <= Self.maximumAudioSamples else {
            throw SherpaOnnxRuntimeError.audioTooLong(
                maximumSamples: Self.maximumAudioSamples,
                actualSamples: audio.samples.count
            )
        }
        guard let session else {
            throw SherpaOnnxRuntimeError.notLoaded
        }

        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let result = try await session.transcribe(
                samples: audio.samples,
                sampleRate: audio.sampleRate
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
            // Accepted microphone recordings have already passed Textify's
            // speech detector and -45 dBFS edge trimmer. Keep this lower
            // backstop for direct runtime callers and models that emit a word
            // for digital or near-digital silence.
            let hasAudibleSignal = audio.samples.contains { abs($0) >= 0.001 }
            let isEmpty = !hasLinguisticContent || !hasAudibleSignal
            let averageLogProbability = Double(result.averageLogProbability)
            return TranscriptionResult(
                text: result.text,
                noSpeechProbability: isEmpty ? 1 : 0,
                averageLogProbability: averageLogProbability.isFinite
                    ? averageLogProbability
                    : (isEmpty ? -10 : 0),
                compressionRatio: 1,
                timing: TranscriptionTiming(
                    audioDurationMs: audioDurationMs,
                    inferenceDurationMs: inferenceDurationMs
                )
            )
        } catch let error as SherpaOnnxRuntimeError {
            throw error
        } catch {
            throw SherpaOnnxRuntimeError.transcriptionFailed(String(describing: error))
        }
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
        let modelDirectory: String
        let variant: SherpaOnnxModelVariant
        let languageCode: String
        let computeRoute: SherpaOnnxComputeRoute
        let threadCount: Int
    }
}
