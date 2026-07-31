@preconcurrency import AVFoundation
import Foundation

public actor LiveAudioRecorder {
    private let permissionClient: MicrophonePermissionClient
    private let configuration: LiveAudioRecordingConfiguration
    private let engineClient: AudioEngineClient

    private var lifecycle: Lifecycle = .idle
    private var nextSessionID: UInt64 = 0
    private var capturedSamples: [Float] = []
    private var speechDetected = false
    private var rmsEmitter = RMSFrameEmitter()
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
        input: LiveAudioInput? = nil,
        maximumDurationSeconds: Double? = nil,
        onSpeechDetected: @escaping @Sendable () -> Void,
        onMaximumDurationReached: @escaping @Sendable () -> Void
    ) async throws {
        let sessionID = try reserveStartupSession()

        do {
            try await ensureMicrophonePermission()
            guard lifecycle == .starting(sessionID) else {
                throw LiveAudioRecorderError.alreadyRecording
            }
        } catch let error as LiveAudioRecorderError {
            clearRecordingState(for: sessionID)
            throw error
        } catch {
            clearRecordingState(for: sessionID)
            throw LiveAudioRecorderError.microphonePermissionDenied
        }

        let (ingestionStream, ingestionPipeline) = LiveAudioIngestionPipeline.makeStream(sessionID: sessionID)
        self.ingestionPipeline = ingestionPipeline
        ingestionTask = Task { [weak self] in
            for await event in ingestionStream {
                await self?.handleIngestionEvent(event, onSpeechDetected: onSpeechDetected)
            }
        }

        do {
            try engineClient.selectInput(input ?? configuration.input)
            try engineClient.installTap { buffer, _ in
                ingestionPipeline.ingest(buffer)
            }
            try engineClient.start()
            lifecycle = .recording(sessionID)
            scheduleMaximumDurationCallback(
                for: sessionID,
                maximumDurationSeconds: maximumDurationSeconds,
                onMaximumDurationReached
            )
        } catch let error as LiveAudioRecorderError {
            stopEngine()
            await closeIngestionPipeline(for: sessionID, drain: false)
            clearRecordingState(for: sessionID)
            throw error
        } catch {
            stopEngine()
            await closeIngestionPipeline(for: sessionID, drain: false)
            clearRecordingState(for: sessionID)
            throw LiveAudioRecorderError.engineStartFailed
        }
    }

    public func finishRecording() async throws -> CanonicalAudioBuffer {
        let sessionID: RecordingSessionID
        switch lifecycle {
        case .recording(let activeSessionID):
            sessionID = activeSessionID
            lifecycle = .finishing(sessionID)
            cancelMaximumDurationCallback()
            await sleepForPostReleaseGrace()
            try await consumeTerminalErrorIfPresent(for: sessionID)
            stopEngine()
        case .stoppedAwaitingFinish(let activeSessionID, _):
            sessionID = activeSessionID
            lifecycle = .finishing(sessionID)
        case .failedAwaitingFinish(let activeSessionID, _):
            sessionID = activeSessionID
            try await consumeTerminalErrorIfPresent(for: sessionID)
            throw LiveAudioRecorderError.notRecording
        case .idle, .starting, .finishing:
            throw LiveAudioRecorderError.notRecording
        }

        await closeIngestionPipeline(for: sessionID, drain: true)
        try await consumeTerminalErrorIfPresent(for: sessionID)

        let buffer = CanonicalAudioBuffer(samples: capturedSamples)
        clearRecordingState(for: sessionID)

        guard !buffer.isEmpty else {
            throw LiveAudioRecorderError.emptyRecording
        }

        return buffer
    }

    public func discardRecording() async {
        guard let sessionID = lifecycle.sessionID else {
            return
        }

        if lifecycle.shouldStopEngine {
            stopEngine()
        }
        await closeIngestionPipeline(for: sessionID, drain: false)
        clearRecordingState(for: sessionID)
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
        case .audio(let sessionID, let canonical):
            ingest(canonical, for: sessionID, onSpeechDetected: onSpeechDetected)
        case .terminalError(let sessionID, let error):
            recordTerminalError(error, for: sessionID)
        }
    }

    private func ingest(
        _ canonical: CanonicalAudioBuffer,
        for sessionID: RecordingSessionID,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) {
        guard lifecycle.acceptsAudio(for: sessionID) else {
            return
        }

        capturedSamples.append(contentsOf: canonical.samples)
        if !speechDetected, rmsEmitter.ingest(samples: canonical.samples, sampleRate: canonical.sampleRate) {
            speechDetected = true
            onSpeechDetected()
        }
    }

    private func recordTerminalError(_ error: LiveAudioRecorderError, for sessionID: RecordingSessionID) {
        guard lifecycle.sessionID == sessionID else {
            return
        }

        switch lifecycle {
        case .recording, .finishing, .stoppedAwaitingFinish:
            lifecycle = .failedAwaitingFinish(sessionID, error)
            stopEngine()
        case .failedAwaitingFinish, .idle, .starting:
            return
        }
    }

    private func reserveStartupSession() throws -> RecordingSessionID {
        guard lifecycle == .idle else {
            throw LiveAudioRecorderError.alreadyRecording
        }

        nextSessionID += 1
        let sessionID = RecordingSessionID(rawValue: nextSessionID)
        lifecycle = .starting(sessionID)
        capturedSamples.removeAll(keepingCapacity: true)
        speechDetected = false
        rmsEmitter = RMSFrameEmitter()
        cancelMaximumDurationCallback()
        ingestionPipeline = nil
        ingestionTask = nil
        return sessionID
    }

    private func scheduleMaximumDurationCallback(
        for sessionID: RecordingSessionID,
        maximumDurationSeconds: Double?,
        _ onMaximumDurationReached: @escaping @Sendable () -> Void
    ) {
        cancelMaximumDurationCallback()
        let requestedDuration = maximumDurationSeconds ?? configuration.maximumDurationSeconds
        let duration = max(0, min(requestedDuration, configuration.maximumDurationSeconds))
        maximumDurationTask = Task { [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            await self?.maximumDurationReached(for: sessionID, onMaximumDurationReached)
        }
    }

    private func maximumDurationReached(
        for sessionID: RecordingSessionID,
        _ onMaximumDurationReached: @escaping @Sendable () -> Void
    ) {
        guard lifecycle == .recording(sessionID) else {
            return
        }
        lifecycle = .stoppedAwaitingFinish(sessionID, .maximumDurationReached)
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
        engineClient.reset()
        if cancelMaximumDuration {
            cancelMaximumDurationCallback()
        }
    }

    private func clearRecordingState(for sessionID: RecordingSessionID) {
        guard lifecycle.sessionID == sessionID else {
            return
        }

        cancelMaximumDurationCallback()
        capturedSamples.removeAll(keepingCapacity: false)
        speechDetected = false
        lifecycle = .idle
        rmsEmitter = RMSFrameEmitter()
    }

    private func closeIngestionPipeline(for sessionID: RecordingSessionID, drain: Bool) async {
        guard ingestionPipeline?.sessionID == sessionID else {
            return
        }

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

    private func consumeTerminalErrorIfPresent(for sessionID: RecordingSessionID) async throws {
        if case .failedAwaitingFinish(let activeSessionID, let terminalError) = lifecycle,
           activeSessionID == sessionID {
            await closeIngestionPipeline(for: sessionID, drain: false)
            clearRecordingState(for: sessionID)
            throw terminalError
        }
    }

    private func cancelMaximumDurationCallback() {
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
    }

    fileprivate struct RecordingSessionID: Equatable, Sendable {
        let rawValue: UInt64
    }

    private enum Lifecycle: Equatable {
        case idle
        case starting(RecordingSessionID)
        case recording(RecordingSessionID)
        case finishing(RecordingSessionID)
        case stoppedAwaitingFinish(RecordingSessionID, TerminalStopReason)
        case failedAwaitingFinish(RecordingSessionID, LiveAudioRecorderError)

        var sessionID: RecordingSessionID? {
            switch self {
            case .idle:
                return nil
            case .starting(let sessionID),
                 .recording(let sessionID),
                 .finishing(let sessionID),
                 .stoppedAwaitingFinish(let sessionID, _),
                 .failedAwaitingFinish(let sessionID, _):
                return sessionID
            }
        }

        var shouldStopEngine: Bool {
            switch self {
            case .recording, .finishing, .failedAwaitingFinish:
                return true
            case .idle, .starting, .stoppedAwaitingFinish:
                return false
            }
        }

        func acceptsAudio(for sessionID: RecordingSessionID) -> Bool {
            switch self {
            case .recording(let activeSessionID) where activeSessionID == sessionID,
                 .finishing(let activeSessionID) where activeSessionID == sessionID,
                 .stoppedAwaitingFinish(let activeSessionID, _) where activeSessionID == sessionID:
                return true
            case .idle, .starting, .recording, .finishing, .stoppedAwaitingFinish, .failedAwaitingFinish:
                return false
            }
        }
    }

    private enum TerminalStopReason: Equatable {
        case maximumDurationReached
    }
}

private enum LiveAudioIngestionEvent: Sendable {
    case audio(LiveAudioRecorder.RecordingSessionID, CanonicalAudioBuffer)
    case terminalError(LiveAudioRecorder.RecordingSessionID, LiveAudioRecorderError)
}

private final class LiveAudioIngestionPipeline: @unchecked Sendable {
    let sessionID: LiveAudioRecorder.RecordingSessionID

    private let lock = NSLock()
    private let conversionSession = CanonicalAudioConverter().makeSession()
    private let continuation: AsyncStream<LiveAudioIngestionEvent>.Continuation
    private var isFinished = false

    private init(
        sessionID: LiveAudioRecorder.RecordingSessionID,
        continuation: AsyncStream<LiveAudioIngestionEvent>.Continuation
    ) {
        self.sessionID = sessionID
        self.continuation = continuation
    }

    static func makeStream(
        sessionID: LiveAudioRecorder.RecordingSessionID
    ) -> (AsyncStream<LiveAudioIngestionEvent>, LiveAudioIngestionPipeline) {
        let streamPair = AsyncStream<LiveAudioIngestionEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        return (
            streamPair.stream,
            LiveAudioIngestionPipeline(sessionID: sessionID, continuation: streamPair.continuation)
        )
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
                continuation.yield(.audio(sessionID, canonical))
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
                continuation.yield(.audio(sessionID, drained))
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
            continuation.yield(.terminalError(sessionID, error))
        }
        isFinished = true
        continuation.finish()
    }
}
