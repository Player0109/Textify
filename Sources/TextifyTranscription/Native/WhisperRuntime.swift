import Foundation
import TextifyWhisperShim

public enum WhisperRuntimeError: Error, Equatable, Sendable {
    case missingModelFile(String)
    case loadFailed(String)
    case warmupFailed(String)
    case notLoaded
    case invalidAudioFormat(sampleRate: Int, channelCount: Int)
    case unsupportedTemperatureFallback
    case transcriptionFailed(String)
}

struct NativeWhisperContext: @unchecked Sendable {
    let rawValue: OpaquePointer
}

struct WhisperRuntimeBackend: Sendable {
    let load: @Sendable (_ modelPath: String, _ useGPU: Bool, _ threadCount: Int32) -> NativeWhisperContext?
    let free: @Sendable (_ context: NativeWhisperContext) -> Void
    let transcribe: @Sendable (_ context: NativeWhisperContext, _ samples: [Float], _ options: WhisperTranscriptionOptions) -> Int32
    let lastText: @Sendable (_ context: NativeWhisperContext) -> String
    let lastError: @Sendable (_ context: NativeWhisperContext?) -> String

    static let native = WhisperRuntimeBackend(
        load: { modelPath, useGPU, threadCount in
            guard let rawContext = textify_whisper_load(modelPath, useGPU ? 1 : 0, threadCount) else {
                return nil
            }

            return NativeWhisperContext(rawValue: rawContext)
        },
        free: { context in
            textify_whisper_free(context.rawValue)
        },
        transcribe: { context, samples, options in
            samples.withUnsafeBufferPointer { buffer in
                options.language.withCString { language in
                    if let initialPrompt = options.initialPrompt {
                        return initialPrompt.withCString { prompt in
                            textify_whisper_transcribe(
                                context.rawValue,
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
                        context.rawValue,
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
        },
        lastText: { context in
            whisperString(from: textify_whisper_last_text(context.rawValue))
        },
        lastError: { context in
            whisperString(from: textify_whisper_last_error(context?.rawValue))
        }
    )
}

private struct InFlightTranscription {
    let id: UUID
    let task: Task<TranscriptionResult, Error>
}

public actor WhisperRuntime: TranscriptionProvider {
    private var nativeContext: NativeWhisperContext?
    private var activeModelID: String?
    private var inFlightTask: InFlightTranscription?
    private let inferenceQueue: DispatchQueue
    private let backend: WhisperRuntimeBackend
    private var metrics = WhisperRuntimeMetrics()

    public private(set) var state: WhisperRuntimeState = .noModel

    public init(queueLabel: String = "io.github.Player0109.Textify.whisper-runtime") {
        self.init(queueLabel: queueLabel, backend: .native)
    }

    init(
        queueLabel: String = "io.github.Player0109.Textify.whisper-runtime",
        backend: WhisperRuntimeBackend
    ) {
        self.inferenceQueue = DispatchQueue(label: queueLabel, qos: .userInitiated)
        self.backend = backend
    }

    deinit {
        if let nativeContext {
            backend.free(nativeContext)
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
        guard let loadedContext = backend.load(modelPath, useGPU, Int32(threadCount)) else {
            let message = backend.lastError(nil)
            state = .failed(modelID: modelID, reason: .loadFailed)
            throw WhisperRuntimeError.loadFailed(message)
        }
        updateMetrics(lastLoadDurationMs: Self.elapsedMilliseconds(since: loadStart))

        nativeContext = loadedContext
        activeModelID = modelID
        state = .preparing(modelID: modelID)

        if warmup {
            let warmupTask = makeTranscriptionTask(
                nativeContext: loadedContext,
                samples: Array(repeating: 0.0, count: 1_600),
                audioDurationMs: 100,
                options: .v1_1English
            )
            inFlightTask = warmupTask

            do {
                let result = try await warmupTask.task.value
                clearInFlightTaskIfCurrent(id: warmupTask.id)
                updateMetrics(lastWarmupDurationMs: result.timing?.inferenceDurationMs)
            } catch {
                clearInFlightTaskIfCurrent(id: warmupTask.id)
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
        guard options.temperatureFallback.isEmpty else {
            throw WhisperRuntimeError.unsupportedTemperatureFallback
        }

        guard audio.sampleRate == 16_000, audio.channelCount == 1 else {
            throw WhisperRuntimeError.invalidAudioFormat(sampleRate: audio.sampleRate, channelCount: audio.channelCount)
        }

        await waitForInFlight()

        guard let nativeContext else {
            throw WhisperRuntimeError.notLoaded
        }

        let samples = audio.samples
        let audioDurationMs = Self.audioDurationMilliseconds(sampleCount: samples.count, sampleRate: audio.sampleRate)
        let task = makeTranscriptionTask(
            nativeContext: nativeContext,
            samples: samples,
            audioDurationMs: audioDurationMs,
            options: options
        )
        inFlightTask = task

        do {
            let result = try await task.task.value
            clearInFlightTaskIfCurrent(id: task.id)
            updateMetrics(lastInferenceDurationMs: result.timing?.inferenceDurationMs)
            return result
        } catch {
            clearInFlightTaskIfCurrent(id: task.id)
            throw error
        }
    }

    private func waitForInFlight() async {
        guard let inFlightTask else {
            return
        }

        _ = try? await inFlightTask.task.value
        clearInFlightTaskIfCurrent(id: inFlightTask.id)
    }

    private func clearInFlightTaskIfCurrent(id: UUID) {
        guard inFlightTask?.id == id else {
            return
        }

        inFlightTask = nil
    }

    private func releaseLoadedContext(markUnloaded: Bool) {
        if let nativeContext {
            backend.free(nativeContext)
            self.nativeContext = nil
        }

        if markUnloaded, let activeModelID {
            state = .unloadedToSaveMemory(modelID: activeModelID)
        }
    }

    private func makeTranscriptionTask(
        nativeContext: NativeWhisperContext,
        samples: [Float],
        audioDurationMs: Int,
        options: WhisperTranscriptionOptions
    ) -> InFlightTranscription {
        let id = UUID()
        let queue = inferenceQueue
        let backend = backend
        let task = Task.detached(priority: .userInitiated) {
            try await Self.performTranscription(
                nativeContext: nativeContext,
                samples: samples,
                audioDurationMs: audioDurationMs,
                options: options,
                backend: backend,
                queue: queue
            )
        }

        return InFlightTranscription(id: id, task: task)
    }

    private static func performTranscription(
        nativeContext: NativeWhisperContext,
        samples: [Float],
        audioDurationMs: Int,
        options: WhisperTranscriptionOptions,
        backend: WhisperRuntimeBackend,
        queue: DispatchQueue
    ) async throws -> TranscriptionResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let inferenceStart = DispatchTime.now()
                let returnCode = backend.transcribe(nativeContext, samples, options)
                let inferenceDurationMs = Self.elapsedMilliseconds(since: inferenceStart)

                guard returnCode == 0 else {
                    let message = backend.lastError(nativeContext)
                    continuation.resume(throwing: WhisperRuntimeError.transcriptionFailed(message))
                    return
                }

                let text = backend.lastText(nativeContext)
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

}

private func whisperString(from cString: UnsafePointer<CChar>?) -> String {
    guard let cString else {
        return ""
    }

    return String(cString: cString)
}
