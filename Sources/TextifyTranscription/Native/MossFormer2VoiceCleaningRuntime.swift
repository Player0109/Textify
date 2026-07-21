import AVFoundation
import Foundation
import Metal
import MLX
import MLXAudioSTS

public enum MossFormer2VoiceCleaningVariant: String, Equatable, Sendable {
    case fp32 = "mossformer2-se-fp32"
    case fp16 = "mossformer2-se-fp16"
    case int8 = "mossformer2-se-int8"

    var requiredFilenames: [String] {
        ["config.json", "model.safetensors"]
    }
}

public enum MossFormer2VoiceCleaningFailure: String, Equatable, Codable, Sendable {
    case missingModelDirectory
    case missingModelFile
    case loadFailed
    case warmupFailed
}

public enum MossFormer2VoiceCleaningState: Equatable, Sendable {
    case noModel
    case loading(modelID: String)
    case preparing(modelID: String)
    case ready(modelID: String)
    case failed(modelID: String, reason: MossFormer2VoiceCleaningFailure)
}

public enum MossFormer2VoiceCleaningError: Error, Equatable, Sendable {
    case missingModelDirectory(String)
    case missingModelFile(String)
    case unsupportedVariant(String)
    case loadFailed(String)
    case warmupFailed(String)
    case notLoaded
    case invalidAudioFormat(sampleRate: Int, channelCount: Int)
    case emptyAudio
    case audioTooLong(maximumSamples: Int, actualSamples: Int)
    case resamplingFailed
    case enhancementFailed(String)
}

protocol MossFormer2VoiceCleaningSession: Sendable {
    var backendName: String { get async }
    var sampleRate: Int { get async }
    func enhance(samples: [Float]) async throws -> [Float]
    func unload() async
}

struct MossFormer2VoiceCleaningBackend {
    let load: @Sendable (URL) async throws -> any MossFormer2VoiceCleaningSession

    static let native = MossFormer2VoiceCleaningBackend { modelDirectory in
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw MossFormer2VoiceCleaningError.loadFailed(
                "The required MLX Metal GPU is unavailable."
            )
        }
        return try Device.withDefaultDevice(.gpu) {
            try NativeMossFormer2VoiceCleaningSession(
                model: MossFormer2SEModel.fromLocal(modelDirectory)
            )
        }
    }
}

private actor NativeMossFormer2VoiceCleaningSession: MossFormer2VoiceCleaningSession {
    private var model: MossFormer2SEModel?

    init(model: MossFormer2SEModel) {
        self.model = model
    }

    var backendName: String {
        Device.defaultDevice().deviceType == .gpu ? "mlx-metal" : ""
    }

    var sampleRate: Int {
        model?.sampleRate ?? 0
    }

    func enhance(samples: [Float]) throws -> [Float] {
        guard let model else {
            throw MossFormer2VoiceCleaningError.notLoaded
        }
        return try Device.withDefaultDevice(.gpu) {
            let output = try model.enhance(MLXArray(samples))
            eval(output)
            return output.asArray(Float.self)
        }
    }

    func unload() {
        model = nil
        Memory.clearCache()
    }
}

public actor MossFormer2VoiceCleaningRuntime {
    public static let inputSampleRate = 16_000
    public static let modelSampleRate = 48_000
    public static let maximumAudioSamples = 60 * inputSampleRate

    private let backend: MossFormer2VoiceCleaningBackend
    private var session: (any MossFormer2VoiceCleaningSession)?
    private var loadedConfiguration: LoadedConfiguration?

    public private(set) var state: MossFormer2VoiceCleaningState = .noModel

    public init() {
        backend = .native
    }

    init(backend: MossFormer2VoiceCleaningBackend) {
        self.backend = backend
    }

    public func load(
        modelID: String,
        modelDirectory: String,
        variant: MossFormer2VoiceCleaningVariant,
        warmup: Bool = true
    ) async throws {
        let requestedConfiguration = LoadedConfiguration(
            modelID: modelID,
            modelDirectory: modelDirectory,
            variant: variant
        )
        if case let .ready(loadedModelID) = state,
           loadedModelID == modelID,
           loadedConfiguration == requestedConfiguration,
           session != nil {
            return
        }

        let modelDirectoryURL = URL(fileURLWithPath: modelDirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: modelDirectoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            state = .failed(modelID: modelID, reason: .missingModelDirectory)
            throw MossFormer2VoiceCleaningError.missingModelDirectory(modelDirectory)
        }
        for filename in variant.requiredFilenames {
            let fileURL = modelDirectoryURL.appendingPathComponent(filename)
            isDirectory = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                state = .failed(modelID: modelID, reason: .missingModelFile)
                throw MossFormer2VoiceCleaningError.missingModelFile(fileURL.path)
            }
        }

        await releaseSession()
        state = .loading(modelID: modelID)

        let loadedSession: any MossFormer2VoiceCleaningSession
        do {
            loadedSession = try await backend.load(modelDirectoryURL)
            guard await loadedSession.backendName == "mlx-metal" else {
                await loadedSession.unload()
                throw MossFormer2VoiceCleaningError.loadFailed(
                    "The voice-cleaning model did not load on the required MLX Metal backend."
                )
            }
            guard await loadedSession.sampleRate == Self.modelSampleRate else {
                await loadedSession.unload()
                throw MossFormer2VoiceCleaningError.loadFailed(
                    "MossFormer2 voice cleaning requires a 48 kHz model."
                )
            }
        } catch {
            state = .failed(modelID: modelID, reason: .loadFailed)
            if let error = error as? MossFormer2VoiceCleaningError {
                throw error
            }
            throw MossFormer2VoiceCleaningError.loadFailed(String(describing: error))
        }

        session = loadedSession
        loadedConfiguration = requestedConfiguration
        state = .preparing(modelID: modelID)
        if warmup {
            do {
                _ = try await loadedSession.enhance(
                    samples: Array(repeating: 0, count: Self.modelSampleRate / 4)
                )
            } catch {
                await releaseSession()
                state = .failed(modelID: modelID, reason: .warmupFailed)
                throw MossFormer2VoiceCleaningError.warmupFailed(String(describing: error))
            }
        }
        state = .ready(modelID: modelID)
    }

    public func unload() async {
        await releaseSession()
        state = .noModel
    }

    public func clean(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionAudioBuffer {
        guard audio.sampleRate == Self.inputSampleRate, audio.channelCount == 1 else {
            throw MossFormer2VoiceCleaningError.invalidAudioFormat(
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount
            )
        }
        guard !audio.samples.isEmpty else {
            throw MossFormer2VoiceCleaningError.emptyAudio
        }
        guard audio.samples.count <= Self.maximumAudioSamples else {
            throw MossFormer2VoiceCleaningError.audioTooLong(
                maximumSamples: Self.maximumAudioSamples,
                actualSamples: audio.samples.count
            )
        }
        guard let session else {
            throw MossFormer2VoiceCleaningError.notLoaded
        }

        do {
            let modelInput = try VoiceCleaningSampleRateConverter.convert(
                audio.samples,
                from: Self.inputSampleRate,
                to: Self.modelSampleRate
            )
            let enhanced = try await session.enhance(samples: modelInput)
            var canonical = try VoiceCleaningSampleRateConverter.convert(
                enhanced,
                from: Self.modelSampleRate,
                to: Self.inputSampleRate
            )
            if canonical.count > audio.samples.count {
                canonical.removeLast(canonical.count - audio.samples.count)
            } else if canonical.count < audio.samples.count {
                canonical.append(contentsOf: repeatElement(0, count: audio.samples.count - canonical.count))
            }
            canonical = canonical.map { sample in
                sample.isFinite ? min(1, max(-1, sample)) : 0
            }
            return TranscriptionAudioBuffer(
                sampleRate: Self.inputSampleRate,
                channelCount: 1,
                samples: canonical
            )
        } catch let error as MossFormer2VoiceCleaningError {
            throw error
        } catch {
            throw MossFormer2VoiceCleaningError.enhancementFailed(String(describing: error))
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

    private struct LoadedConfiguration: Equatable {
        let modelID: String
        let modelDirectory: String
        let variant: MossFormer2VoiceCleaningVariant
    }
}

enum VoiceCleaningSampleRateConverter {
    static func convert(_ samples: [Float], from sourceRate: Int, to destinationRate: Int) throws -> [Float] {
        guard sourceRate > 0, destinationRate > 0 else {
            throw MossFormer2VoiceCleaningError.resamplingFailed
        }
        guard sourceRate != destinationRate else {
            return samples
        }
        guard !samples.isEmpty,
              let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sourceRate),
                channels: 1,
                interleaved: false
              ),
              let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(destinationRate),
                channels: 1,
                interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
              ) else {
            throw MossFormer2VoiceCleaningError.resamplingFailed
        }

        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
        guard let inputChannel = inputBuffer.floatChannelData?[0] else {
            throw MossFormer2VoiceCleaningError.resamplingFailed
        }
        inputChannel.update(from: samples, count: samples.count)

        let ratio = Double(destinationRate) / Double(sourceRate)
        let outputCapacity = AVAudioFrameCount(ceil(Double(samples.count) * ratio) + 32)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            throw MossFormer2VoiceCleaningError.resamplingFailed
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error,
              conversionError == nil,
              let outputChannel = outputBuffer.floatChannelData?[0] else {
            throw MossFormer2VoiceCleaningError.resamplingFailed
        }
        return Array(
            UnsafeBufferPointer(
                start: outputChannel,
                count: Int(outputBuffer.frameLength)
            )
        )
    }
}
