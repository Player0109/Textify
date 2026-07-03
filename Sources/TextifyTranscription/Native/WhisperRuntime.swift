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
    private var metrics = WhisperRuntimeMetrics()

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

        let loadStart = DispatchTime.now()
        guard let rawContext = textify_whisper_load(modelPath, useGPU ? 1 : 0, Int32(threadCount)) else {
            let message = Self.string(from: textify_whisper_last_error(nil))
            state = .failed(modelID: modelID, reason: .loadFailed)
            throw WhisperRuntimeError.loadFailed(message)
        }
        updateMetrics(lastLoadDurationMs: Self.elapsedMilliseconds(since: loadStart))

        nativeContext = NativeWhisperContext(rawValue: rawContext)
        activeModelID = modelID
        state = .preparing(modelID: modelID)

        if warmup {
            let warmupStart = DispatchTime.now()
            do {
                _ = try await transcribe(
                    TranscriptionAudioBuffer(samples: Array(repeating: 0.0, count: 1_600)),
                    options: .v1_1English
                )
                updateMetrics(lastWarmupDurationMs: Self.elapsedMilliseconds(since: warmupStart))
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

    public func snapshot() -> WhisperRuntimeSnapshot {
        WhisperRuntimeSnapshot(state: state, metrics: metrics)
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
        try await transcribe(audio, options: .v1_1English)
    }

    public func transcribe(
        _ audio: TranscriptionAudioBuffer,
        options: WhisperTranscriptionOptions
    ) async throws -> TranscriptionResult {
        guard audio.sampleRate == 16_000, audio.channelCount == 1 else {
            throw WhisperRuntimeError.invalidAudioFormat(sampleRate: audio.sampleRate, channelCount: audio.channelCount)
        }

        guard let nativeContext else {
            throw WhisperRuntimeError.notLoaded
        }

        let samples = audio.samples
        let audioDurationMs = Self.audioDurationMilliseconds(sampleCount: samples.count, sampleRate: audio.sampleRate)
        let queue = inferenceQueue
        let task = Task.detached(priority: .userInitiated) {
            try await Self.performTranscription(
                nativeContext: nativeContext,
                samples: samples,
                audioDurationMs: audioDurationMs,
                options: options,
                queue: queue
            )
        }
        inFlightTask = task

        do {
            let result = try await task.value
            inFlightTask = nil
            updateMetrics(lastInferenceDurationMs: result.timing?.inferenceDurationMs)
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
        audioDurationMs: Int,
        options: WhisperTranscriptionOptions,
        queue: DispatchQueue
    ) async throws -> TranscriptionResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let inferenceStart = DispatchTime.now()
                let returnCode = samples.withUnsafeBufferPointer { buffer in
                    options.language.withCString { language in
                        if let initialPrompt = options.initialPrompt {
                            return initialPrompt.withCString { prompt in
                                textify_whisper_transcribe(
                                    nativeContext.rawValue,
                                    buffer.baseAddress,
                                    Int32(buffer.count),
                                    language,
                                    options.translate ? 1 : 0,
                                    options.temperature,
                                    options.usePreviousContext ? 0 : 1,
                                    prompt
                                )
                            }
                        }

                        return textify_whisper_transcribe(
                            nativeContext.rawValue,
                            buffer.baseAddress,
                            Int32(buffer.count),
                            language,
                            options.translate ? 1 : 0,
                            options.temperature,
                            options.usePreviousContext ? 0 : 1,
                            nil
                        )
                    }
                }
                let inferenceDurationMs = Self.elapsedMilliseconds(since: inferenceStart)

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
                        compressionRatio: 0,
                        timing: TranscriptionTiming(
                            audioDurationMs: audioDurationMs,
                            inferenceDurationMs: inferenceDurationMs
                        )
                    )
                )
            }
        }
    }

    private func updateMetrics(
        lastLoadDurationMs: Int? = nil,
        lastWarmupDurationMs: Int? = nil,
        lastInferenceDurationMs: Int? = nil
    ) {
        metrics = WhisperRuntimeMetrics(
            lastLoadDurationMs: lastLoadDurationMs ?? metrics.lastLoadDurationMs,
            lastWarmupDurationMs: lastWarmupDurationMs ?? metrics.lastWarmupDurationMs,
            lastInferenceDurationMs: lastInferenceDurationMs ?? metrics.lastInferenceDurationMs
        )
    }

    private static func audioDurationMilliseconds(sampleCount: Int, sampleRate: Int) -> Int {
        Int((Double(sampleCount) / Double(sampleRate) * 1000).rounded())
    }

    private static func elapsedMilliseconds(since start: DispatchTime) -> Int {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        return Int((elapsedNanoseconds + 999_999) / 1_000_000)
    }

    private static func string(from cString: UnsafePointer<CChar>?) -> String {
        guard let cString else {
            return ""
        }

        return String(cString: cString)
    }
}
