@preconcurrency import AVFoundation
import Foundation

public actor LiveAudioRecorder {
    private let permissionClient: MicrophonePermissionClient
    private let configuration: LiveAudioRecordingConfiguration
    private let engineClient: AudioEngineClient

    private var isRecording = false
    private var capturedSamples: [Float] = []
    private var speechDetected = false
    private var rmsEmitter = RMSFrameEmitter()
    private var terminalError: LiveAudioRecorderError?
    private var terminalStopReason: TerminalStopReason?
    private var maximumDurationTask: Task<Void, Never>?
    private var ingestionPipeline: LiveAudioIngestionPipeline?
    private var ingestionTask: Task<Void, Never>?

    public init(
        permissionClient: MicrophonePermissionClient = .live,
        configuration: LiveAudioRecordingConfiguration = .v1_1Default,
        engineClient: AudioEngineClient = SystemAudioEngineClient()
    ) {
        self.permissionClient = permissionClient
        self.configuration = configuration
        self.engineClient = engineClient
    }

    public func startRecording(
        onSpeechDetected: @escaping @Sendable () -> Void,
        onMaximumDurationReached: @escaping @Sendable () -> Void
    ) async throws {
        guard !isRecording, terminalStopReason == nil else {
            throw LiveAudioRecorderError.alreadyRecording
        }

        try await ensureMicrophonePermission()
        guard configuration.input == .systemDefault else {
            throw LiveAudioRecorderError.unsupportedInput
        }

        isRecording = true
        capturedSamples.removeAll(keepingCapacity: true)
        speechDetected = false
        terminalError = nil
        terminalStopReason = nil
        rmsEmitter = RMSFrameEmitter()

        let (ingestionStream, ingestionPipeline) = LiveAudioIngestionPipeline.makeStream()
        self.ingestionPipeline = ingestionPipeline
        ingestionTask = Task { [weak self] in
            for await event in ingestionStream {
                await self?.handleIngestionEvent(event, onSpeechDetected: onSpeechDetected)
            }
        }

        do {
            try engineClient.installTap { buffer, _ in
                ingestionPipeline.ingest(buffer)
            }
            try engineClient.start()
            scheduleMaximumDurationCallback(onMaximumDurationReached)
        } catch let error as LiveAudioRecorderError {
            stopEngine()
            await closeIngestionPipeline(drain: false)
            clearRecordingState()
            throw error
        } catch {
            stopEngine()
            await closeIngestionPipeline(drain: false)
            clearRecordingState()
            throw LiveAudioRecorderError.engineStartFailed
        }
    }

    public func finishRecording() async throws -> CanonicalAudioBuffer {
        try await consumeTerminalErrorIfPresent()

        guard isRecording || terminalStopReason != nil else {
            throw LiveAudioRecorderError.notRecording
        }

        if isRecording {
            cancelMaximumDurationCallback()
            await sleepForPostReleaseGrace()
            try await consumeTerminalErrorIfPresent()
            if isRecording {
                stopEngine()
            }
        }

        await closeIngestionPipeline(drain: true)
        try await consumeTerminalErrorIfPresent()

        let buffer = CanonicalAudioBuffer(samples: capturedSamples)
        clearRecordingState()

        guard !buffer.isEmpty else {
            throw LiveAudioRecorderError.emptyRecording
        }

        return buffer
    }

    public func discardRecording() async {
        if isRecording {
            stopEngine()
        }
        await closeIngestionPipeline(drain: false)
        clearRecordingState()
    }

    private func ensureMicrophonePermission() async throws {
        switch permissionClient.status() {
        case .granted:
            return
        case .notDetermined:
            guard await permissionClient.requestAccess() == .granted else {
                throw LiveAudioRecorderError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw LiveAudioRecorderError.microphonePermissionDenied
        }
    }

    private func handleIngestionEvent(
        _ event: LiveAudioIngestionEvent,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) {
        switch event {
        case .audio(let canonical):
            ingest(canonical, onSpeechDetected: onSpeechDetected)
        case .terminalError(let error):
            recordTerminalError(error)
        }
    }

    private func ingest(
        _ canonical: CanonicalAudioBuffer,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) {
        guard terminalError == nil else {
            return
        }

        capturedSamples.append(contentsOf: canonical.samples)
        if !speechDetected, rmsEmitter.ingest(samples: canonical.samples, sampleRate: canonical.sampleRate) {
            speechDetected = true
            onSpeechDetected()
        }
    }

    private func recordTerminalError(_ error: LiveAudioRecorderError) {
        guard terminalError == nil else {
            return
        }
        terminalError = error
        if isRecording {
            stopEngine()
        }
    }

    private func scheduleMaximumDurationCallback(_ onMaximumDurationReached: @escaping @Sendable () -> Void) {
        cancelMaximumDurationCallback()
        let duration = max(0, configuration.maximumDurationSeconds)
        maximumDurationTask = Task { [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            await self?.maximumDurationReached(onMaximumDurationReached)
        }
    }

    private func maximumDurationReached(_ onMaximumDurationReached: @escaping @Sendable () -> Void) {
        guard isRecording else {
            return
        }
        terminalStopReason = .maximumDurationReached
        stopEngine(cancelMaximumDuration: false)
        maximumDurationTask = nil
        onMaximumDurationReached()
    }

    private func sleepForPostReleaseGrace() async {
        let milliseconds = max(0, configuration.postReleaseGraceMilliseconds)
        guard milliseconds > 0 else {
            return
        }

        let nanoseconds = UInt64(milliseconds) * 1_000_000
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private func stopEngine(cancelMaximumDuration: Bool = true) {
        engineClient.removeTap()
        engineClient.stop()
        isRecording = false
        if cancelMaximumDuration {
            cancelMaximumDurationCallback()
        }
    }

    private func clearRecordingState() {
        cancelMaximumDurationCallback()
        capturedSamples.removeAll(keepingCapacity: false)
        speechDetected = false
        terminalError = nil
        terminalStopReason = nil
        isRecording = false
        rmsEmitter = RMSFrameEmitter()
    }

    private func closeIngestionPipeline(drain: Bool) async {
        let pipeline = ingestionPipeline
        let task = ingestionTask
        ingestionPipeline = nil
        ingestionTask = nil

        if drain {
            pipeline?.finish()
        } else {
            pipeline?.cancel()
        }
        await task?.value
    }

    private func consumeTerminalErrorIfPresent() async throws {
        if let terminalError {
            await closeIngestionPipeline(drain: false)
            clearRecordingState()
            throw terminalError
        }
    }

    private func cancelMaximumDurationCallback() {
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
    }

    private enum TerminalStopReason {
        case maximumDurationReached
    }
}

private enum LiveAudioIngestionEvent: Sendable {
    case audio(CanonicalAudioBuffer)
    case terminalError(LiveAudioRecorderError)
}

private final class LiveAudioIngestionPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let conversionSession = CanonicalAudioConverter().makeSession()
    private let continuation: AsyncStream<LiveAudioIngestionEvent>.Continuation
    private var isFinished = false

    private init(continuation: AsyncStream<LiveAudioIngestionEvent>.Continuation) {
        self.continuation = continuation
    }

    static func makeStream() -> (AsyncStream<LiveAudioIngestionEvent>, LiveAudioIngestionPipeline) {
        let streamPair = AsyncStream<LiveAudioIngestionEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        return (streamPair.stream, LiveAudioIngestionPipeline(continuation: streamPair.continuation))
    }

    func ingest(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else {
            return
        }

        do {
            let canonical = try conversionSession.convert(buffer)
            if !canonical.isEmpty {
                continuation.yield(.audio(canonical))
            }
        } catch let error as LiveAudioRecorderError {
            finishLocked(with: error)
        } catch {
            finishLocked(with: .conversionFailed)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else {
            return
        }

        do {
            let drained = try conversionSession.finish()
            if !drained.isEmpty {
                continuation.yield(.audio(drained))
            }
            finishLocked()
        } catch let error as LiveAudioRecorderError {
            finishLocked(with: error)
        } catch {
            finishLocked(with: .conversionFailed)
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else {
            return
        }

        finishLocked()
    }

    private func finishLocked(with error: LiveAudioRecorderError? = nil) {
        guard !isFinished else {
            return
        }

        if let error {
            continuation.yield(.terminalError(error))
        }
        isFinished = true
        continuation.finish()
    }
}
