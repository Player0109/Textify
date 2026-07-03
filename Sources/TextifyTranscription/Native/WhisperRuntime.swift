import Foundation
import TextifyWhisperShim

public enum WhisperRuntimeError: Error, Equatable, Sendable {
    case missingModelFile(String)
    case loadFailed(String)
    case warmupFailed(String)
    case notLoaded
    case invalidAudioFormat(sampleRate: Int, channelCount: Int)
    case transcriptionFailed(String)
}

private struct NativeWhisperContext: @unchecked Sendable {
    let rawValue: OpaquePointer
}

public actor WhisperRuntime: TranscriptionProvider {
    private var nativeContext: NativeWhisperContext?
    private var activeModelID: String?
    private var inFlightTask: Task<TranscriptionResult, Error>?
    private let inferenceQueue: DispatchQueue

    public private(set) var state: WhisperRuntimeState = .noModel

    public init(queueLabel: String = "io.github.Player0109.Textify.whisper-runtime") {
        self.inferenceQueue = DispatchQueue(label: queueLabel, qos: .userInitiated)
    }

    deinit {
        if let nativeContext {
            textify_whisper_free(nativeContext.rawValue)
        }
    }

    public func load(
        modelID: String,
        modelPath: String,
        useGPU: Bool = true,
        threadCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        warmup: Bool = true
    ) async throws {
        await waitForInFlight()

        state = .loading(modelID: modelID)

        guard FileManager.default.fileExists(atPath: modelPath) else {
            state = .failed(modelID: modelID, reason: .missingModelFile)
            throw WhisperRuntimeError.missingModelFile(modelPath)
        }

        releaseLoadedContext(markUnloaded: false)

        guard let rawContext = textify_whisper_load(modelPath, useGPU ? 1 : 0, Int32(threadCount)) else {
            let message = Self.string(from: textify_whisper_last_error(nil))
            state = .failed(modelID: modelID, reason: .loadFailed)
            throw WhisperRuntimeError.loadFailed(message)
        }

        nativeContext = NativeWhisperContext(rawValue: rawContext)
        activeModelID = modelID
        state = .preparing(modelID: modelID)

        if warmup {
            do {
                _ = try await transcribe(TranscriptionAudioBuffer(samples: Array(repeating: 0.0, count: 1_600)))
            } catch {
                releaseLoadedContext(markUnloaded: false)
                state = .failed(modelID: modelID, reason: .warmupFailed)
                throw WhisperRuntimeError.warmupFailed(String(describing: error))
            }
        }

        state = .ready(modelID: modelID)
    }

    public func switchModel(
        modelID: String,
        modelPath: String,
        useGPU: Bool = true,
        threadCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        warmup: Bool = true
    ) async throws {
        await waitForInFlight()
        releaseLoadedContext(markUnloaded: false)
        activeModelID = nil
        state = .noModel
        try await load(modelID: modelID, modelPath: modelPath, useGPU: useGPU, threadCount: threadCount, warmup: warmup)
    }

    public func unloadToSaveMemory() async {
        await waitForInFlight()
        releaseLoadedContext(markUnloaded: true)
    }

    public func unload() async {
        await waitForInFlight()
        activeModelID = nil
        releaseLoadedContext(markUnloaded: false)
        state = .noModel
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        guard audio.sampleRate == 16_000, audio.channelCount == 1 else {
            throw WhisperRuntimeError.invalidAudioFormat(sampleRate: audio.sampleRate, channelCount: audio.channelCount)
        }

        guard let nativeContext else {
            throw WhisperRuntimeError.notLoaded
        }

        let samples = audio.samples
        let queue = inferenceQueue
        let task = Task.detached(priority: .userInitiated) {
            try await Self.performTranscription(nativeContext: nativeContext, samples: samples, queue: queue)
        }
        inFlightTask = task

        do {
            let result = try await task.value
            inFlightTask = nil
            return result
        } catch {
            inFlightTask = nil
            throw error
        }
    }

    private func waitForInFlight() async {
        guard let task = inFlightTask else {
            return
        }

        _ = try? await task.value
        inFlightTask = nil
    }

    private func releaseLoadedContext(markUnloaded: Bool) {
        if let nativeContext {
            textify_whisper_free(nativeContext.rawValue)
            self.nativeContext = nil
        }

        if markUnloaded, let activeModelID {
            state = .unloadedToSaveMemory(modelID: activeModelID)
        }
    }

    private static func performTranscription(
        nativeContext: NativeWhisperContext,
        samples: [Float],
        queue: DispatchQueue
    ) async throws -> TranscriptionResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let returnCode = samples.withUnsafeBufferPointer { buffer in
                    textify_whisper_transcribe(nativeContext.rawValue, buffer.baseAddress, Int32(buffer.count))
                }

                guard returnCode == 0 else {
                    let message = Self.string(from: textify_whisper_last_error(nativeContext.rawValue))
                    continuation.resume(throwing: WhisperRuntimeError.transcriptionFailed(message))
                    return
                }

                let text = Self.string(from: textify_whisper_last_text(nativeContext.rawValue))
                continuation.resume(
                    returning: TranscriptionResult(
                        text: text,
                        noSpeechProbability: 0,
                        averageLogProbability: 0,
                        compressionRatio: 0
                    )
                )
            }
        }
    }

    private static func string(from cString: UnsafePointer<CChar>?) -> String {
        guard let cString else {
            return ""
        }

        return String(cString: cString)
    }
}
