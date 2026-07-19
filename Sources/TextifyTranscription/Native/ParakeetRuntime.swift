import CoreML
import FluidAudio
import Foundation

public enum ParakeetModelVariant: String, Equatable, Sendable {
    case tdtV2 = "parakeet-tdt-0.6b-v2"
    case tdtV3 = "parakeet-tdt-0.6b-v3"
    case tdtCtc110M = "parakeet-tdt-ctc-110m"
    case tdtJapanese = "parakeet-tdt-0.6b-ja"

    fileprivate var fluidAudioVersion: AsrModelVersion {
        switch self {
        case .tdtV2:
            return .v2
        case .tdtV3:
            return .v3
        case .tdtCtc110M:
            return .tdtCtc110m
        case .tdtJapanese:
            return .tdtJa
        }
    }

    fileprivate var decoderLayerCount: Int {
        switch self {
        case .tdtCtc110M:
            return 1
        case .tdtV2, .tdtV3, .tdtJapanese:
            return 2
        }
    }

    var neuralEngineVerificationModelNameFragments: [String] {
        switch self {
        case .tdtCtc110M:
            return ["preprocessor"]
        case .tdtV2, .tdtV3, .tdtJapanese:
            return ["encoder"]
        }
    }
}

public enum ParakeetComputeRoute: String, Equatable, Sendable {
    case neuralEngine = "coreml_cpu_and_neural_engine"
}

public enum ParakeetRuntimeFailure: String, Equatable, Codable, Sendable {
    case missingModelDirectory
    case loadFailed
    case warmupFailed
}

public enum ParakeetRuntimeState: Equatable, Sendable {
    case noModel
    case loading(modelID: String)
    case preparing(modelID: String)
    case ready(modelID: String)
    case failed(modelID: String, reason: ParakeetRuntimeFailure)
}

public enum ParakeetRuntimeError: Error, Equatable, Sendable {
    case missingModelDirectory(String)
    case unsupportedVariant(String)
    case loadFailed(String)
    case warmupFailed(String)
    case notLoaded
    case invalidAudioFormat(sampleRate: Int, channelCount: Int)
    case transcriptionFailed(String)
}

struct ParakeetSessionResult: Equatable, Sendable {
    let text: String
    let confidence: Float
    let processingTimeSeconds: TimeInterval
}

protocol ParakeetRuntimeSession: Sendable {
    func transcribe(samples: [Float], languageCode: String?) async throws -> ParakeetSessionResult
    func unload() async
}

struct ParakeetRuntimeBackend: Sendable {
    let load: @Sendable (
        _ modelDirectory: URL,
        _ variant: ParakeetModelVariant,
        _ computeRoute: ParakeetComputeRoute
    ) async throws -> any ParakeetRuntimeSession

    static let native = ParakeetRuntimeBackend { modelDirectory, variant, computeRoute in
        ModelHub.offlineMode = true

        let configuration = MLModelConfiguration()
        switch computeRoute {
        case .neuralEngine:
            configuration.computeUnits = .cpuAndNeuralEngine
        }

        try await CoreMLNeuralEngineVerifier.verifyNeuralEnginePlans(
            modelDirectory: modelDirectory,
            configuration: configuration,
            requiredModelNameFragments: variant.neuralEngineVerificationModelNameFragments
        )

        let models = try await AsrModels.load(
            from: modelDirectory,
            configuration: configuration,
            version: variant.fluidAudioVersion,
            encoderPrecision: .int8
        )
        return NativeParakeetSession(
            manager: AsrManager(models: models),
            decoderLayerCount: variant.decoderLayerCount
        )
    }
}

enum CoreMLNeuralEngineVerificationError: Error, Equatable, Sendable {
    case failed(String)
}

enum CoreMLNeuralEngineVerifier {
    static func verifyNeuralEnginePlans(
        modelDirectory: URL,
        configuration: MLModelConfiguration,
        requiredModelNameFragments: [String]
    ) async throws {
        guard #available(macOS 14.4, *) else {
            throw CoreMLNeuralEngineVerificationError.failed(
                "Neural Engine verification requires macOS 14.4 or newer."
            )
        }
        guard MLComputeDevice.allComputeDevices.contains(where: { device in
            if case .neuralEngine = device {
                return true
            }
            return false
        }) else {
            throw CoreMLNeuralEngineVerificationError.failed(
                "Apple Neural Engine is unavailable."
            )
        }

        let modelURLs = try FileManager.default.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for nameFragment in requiredModelNameFragments {
            let matchingURLs = modelURLs.filter {
                $0.pathExtension == "mlmodelc"
                    && $0.deletingPathExtension().lastPathComponent
                        .localizedCaseInsensitiveContains(nameFragment)
            }
            guard !matchingURLs.isEmpty else {
                throw CoreMLNeuralEngineVerificationError.failed(
                    "The model directory has no compiled \(nameFragment) for accelerator verification."
                )
            }

            var verified = false
            for modelURL in matchingURLs {
                let plan = try await MLComputePlan.load(
                    contentsOf: modelURL,
                    configuration: configuration
                )
                if prefersNeuralEngine(plan: plan, structure: plan.modelStructure) {
                    verified = true
                    break
                }
            }
            guard verified else {
                throw CoreMLNeuralEngineVerificationError.failed(
                    "Core ML did not plan the \(nameFragment) model for Apple Neural Engine execution."
                )
            }
        }
    }

    @available(macOS 14.4, *)
    private static func prefersNeuralEngine(
        plan: MLComputePlan,
        structure: MLModelStructure
    ) -> Bool {
        switch structure {
        case let .program(program):
            return program.functions.values.contains { function in
                blockPrefersNeuralEngine(function.block, plan: plan)
            }
        case let .neuralNetwork(network):
            return network.layers.contains { layer in
                guard let usage = plan.deviceUsage(for: layer) else {
                    return false
                }
                if case .neuralEngine = usage.preferred {
                    return true
                }
                return false
            }
        case let .pipeline(pipeline):
            return pipeline.subModels.contains {
                prefersNeuralEngine(plan: plan, structure: $0)
            }
        case .unsupported:
            return false
        @unknown default:
            return false
        }
    }

    @available(macOS 14.4, *)
    private static func blockPrefersNeuralEngine(
        _ block: MLModelStructure.Program.Block,
        plan: MLComputePlan
    ) -> Bool {
        block.operations.contains { operation in
            if let usage = plan.deviceUsage(for: operation),
               case .neuralEngine = usage.preferred {
                return true
            }
            return operation.blocks.contains {
                blockPrefersNeuralEngine($0, plan: plan)
            }
        }
    }
}

private actor NativeParakeetSession: ParakeetRuntimeSession {
    private let manager: AsrManager
    private let decoderLayerCount: Int

    init(manager: AsrManager, decoderLayerCount: Int) {
        self.manager = manager
        self.decoderLayerCount = decoderLayerCount
    }

    func transcribe(samples: [Float], languageCode: String?) async throws -> ParakeetSessionResult {
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayerCount)
        let language = languageCode.flatMap(Language.init(rawValue:))
        let result = try await manager.transcribe(
            samples,
            decoderState: &decoderState,
            language: language
        )
        return ParakeetSessionResult(
            text: result.text,
            confidence: result.confidence,
            processingTimeSeconds: result.processingTime
        )
    }

    func unload() async {
        await manager.cleanup()
    }
}

public actor ParakeetRuntime: TranscriptionProvider {
    private let backend: ParakeetRuntimeBackend
    private var session: (any ParakeetRuntimeSession)?
    private var activeLanguageCode: String?

    public private(set) var state: ParakeetRuntimeState = .noModel

    public init() {
        self.backend = .native
    }

    init(backend: ParakeetRuntimeBackend) {
        self.backend = backend
    }

    public func load(
        modelID: String,
        modelDirectory: String,
        variant: ParakeetModelVariant,
        computeRoute: ParakeetComputeRoute = .neuralEngine,
        languageCode: String? = nil,
        warmup: Bool = true
    ) async throws {
        if case let .ready(loadedModelID) = state,
           loadedModelID == modelID,
           session != nil {
            activeLanguageCode = languageCode
            return
        }

        let modelURL = URL(fileURLWithPath: modelDirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            state = .failed(modelID: modelID, reason: .missingModelDirectory)
            throw ParakeetRuntimeError.missingModelDirectory(modelDirectory)
        }

        await releaseSession()
        state = .loading(modelID: modelID)

        let loadedSession: any ParakeetRuntimeSession
        do {
            loadedSession = try await backend.load(modelURL, variant, computeRoute)
        } catch {
            state = .failed(modelID: modelID, reason: .loadFailed)
            throw ParakeetRuntimeError.loadFailed(String(describing: error))
        }

        session = loadedSession
        activeLanguageCode = languageCode
        state = .preparing(modelID: modelID)

        if warmup {
            do {
                _ = try await loadedSession.transcribe(
                    samples: Array(repeating: 0, count: 6_400),
                    languageCode: languageCode
                )
            } catch {
                await releaseSession()
                state = .failed(modelID: modelID, reason: .warmupFailed)
                throw ParakeetRuntimeError.warmupFailed(String(describing: error))
            }
        }

        state = .ready(modelID: modelID)
    }

    public func unload() async {
        await releaseSession()
        activeLanguageCode = nil
        state = .noModel
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        guard audio.sampleRate == 16_000, audio.channelCount == 1 else {
            throw ParakeetRuntimeError.invalidAudioFormat(
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount
            )
        }
        guard let session else {
            throw ParakeetRuntimeError.notLoaded
        }

        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let result = try await session.transcribe(
                samples: audio.samples,
                languageCode: activeLanguageCode
            )
            let inferenceDurationMs = Int(
                (DispatchTime.now().uptimeNanoseconds - start + 999_999) / 1_000_000
            )
            let audioDurationMs = Int(
                (Double(audio.samples.count) / Double(audio.sampleRate) * 1_000).rounded()
            )
            let confidence = Double(result.confidence)
            let normalizedConfidence = confidence.isFinite
                ? min(max(confidence, 0), 1)
                : 0
            return TranscriptionResult(
                text: result.text,
                noSpeechProbability: 1 - normalizedConfidence,
                averageLogProbability: log(max(normalizedConfidence, 0.000_001)),
                compressionRatio: 1,
                timing: TranscriptionTiming(
                    audioDurationMs: audioDurationMs,
                    inferenceDurationMs: inferenceDurationMs
                )
            )
        } catch let error as ParakeetRuntimeError {
            throw error
        } catch {
            throw ParakeetRuntimeError.transcriptionFailed(String(describing: error))
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
