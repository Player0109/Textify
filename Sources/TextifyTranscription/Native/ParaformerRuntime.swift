import CoreML
import FluidAudio
import Foundation

public enum ParaformerModelVariant: String, Equatable, Sendable {
    case largeZhInt8 = "paraformer-large-zh-int8"
}

public enum ParaformerRuntimeFailure: String, Equatable, Codable, Sendable {
    case missingModelDirectory
    case loadFailed
    case warmupFailed
}

public enum ParaformerRuntimeState: Equatable, Sendable {
    case noModel
    case loading(modelID: String)
    case preparing(modelID: String)
    case ready(modelID: String)
    case failed(modelID: String, reason: ParaformerRuntimeFailure)
}

public enum ParaformerRuntimeError: Error, Equatable, Sendable {
    case missingModelDirectory(String)
    case unsupportedVariant(String)
    case unsupportedLanguage(String)
    case loadFailed(String)
    case warmupFailed(String)
    case notLoaded
    case invalidAudioFormat(sampleRate: Int, channelCount: Int)
    case audioTooLong(maximumSamples: Int, actualSamples: Int)
    case transcriptionFailed(String)
}

protocol ParaformerRuntimeSession: Sendable {
    func transcribe(samples: [Float]) async throws -> String
    func unload() async
}

struct ParaformerRuntimeBackend: Sendable {
    let load: @Sendable (
        _ modelDirectory: URL,
        _ variant: ParaformerModelVariant
    ) async throws -> any ParaformerRuntimeSession

    static let native = ParaformerRuntimeBackend { modelDirectory, variant in
        ModelHub.offlineMode = true

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        switch variant {
        case .largeZhInt8:
            try await CoreMLNeuralEngineVerifier.verifyNeuralEnginePlans(
                modelDirectory: modelDirectory,
                configuration: configuration,
                requiredModelNameFragments: ["encoder_int8", "decoder_int8"]
            )
            let models = try ParaformerModels.load(from: modelDirectory, precision: .int8)
            return NativeParaformerSession(manager: ParaformerManager(models: models))
        }
    }
}

private actor NativeParaformerSession: ParaformerRuntimeSession {
    private let manager: ParaformerManager

    init(manager: ParaformerManager) {
        self.manager = manager
    }

    func transcribe(samples: [Float]) async throws -> String {
        try await manager.transcribe(audio: samples)
    }

    func unload() {}
}

public actor ParaformerRuntime: TranscriptionProvider {
    static let maximumAudioSamples = 30 * 16_000

    private let backend: ParaformerRuntimeBackend
    private var session: (any ParaformerRuntimeSession)?

    public private(set) var state: ParaformerRuntimeState = .noModel

    public init() {
        self.backend = .native
    }

    init(backend: ParaformerRuntimeBackend) {
        self.backend = backend
    }

    public func load(
        modelID: String,
        modelDirectory: String,
        variant: ParaformerModelVariant,
        warmup: Bool = true
    ) async throws {
        if case let .ready(loadedModelID) = state,
           loadedModelID == modelID,
           session != nil {
            return
        }

        let modelURL = URL(fileURLWithPath: modelDirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            state = .failed(modelID: modelID, reason: .missingModelDirectory)
            throw ParaformerRuntimeError.missingModelDirectory(modelDirectory)
        }

        await releaseSession()
        state = .loading(modelID: modelID)

        let loadedSession: any ParaformerRuntimeSession
        do {
            loadedSession = try await backend.load(modelURL, variant)
        } catch {
            state = .failed(modelID: modelID, reason: .loadFailed)
            throw ParaformerRuntimeError.loadFailed(String(describing: error))
        }

        session = loadedSession
        state = .preparing(modelID: modelID)
        if warmup {
            do {
                _ = try await loadedSession.transcribe(samples: Array(repeating: 0, count: 6_400))
            } catch {
                await releaseSession()
                state = .failed(modelID: modelID, reason: .warmupFailed)
                throw ParaformerRuntimeError.warmupFailed(String(describing: error))
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
            throw ParaformerRuntimeError.invalidAudioFormat(
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount
            )
        }
        guard audio.samples.count <= Self.maximumAudioSamples else {
            throw ParaformerRuntimeError.audioTooLong(
                maximumSamples: Self.maximumAudioSamples,
                actualSamples: audio.samples.count
            )
        }
        guard let session else {
            throw ParaformerRuntimeError.notLoaded
        }

        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let text = try await session.transcribe(samples: audio.samples)
            let inferenceDurationMs = Int(
                (DispatchTime.now().uptimeNanoseconds - start + 999_999) / 1_000_000
            )
            let audioDurationMs = Int(
                (Double(audio.samples.count) / Double(audio.sampleRate) * 1_000).rounded()
            )
            let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return TranscriptionResult(
                text: text,
                noSpeechProbability: isEmpty ? 1 : 0,
                averageLogProbability: isEmpty ? -10 : 0,
                compressionRatio: 1,
                timing: TranscriptionTiming(
                    audioDurationMs: audioDurationMs,
                    inferenceDurationMs: inferenceDurationMs
                )
            )
        } catch let error as ParaformerRuntimeError {
            throw error
        } catch {
            throw ParaformerRuntimeError.transcriptionFailed(String(describing: error))
        }
    }

    private func releaseSession() async {
        guard let session else {
            return
        }
        self.session = nil
        await session.unload()
    }
}
