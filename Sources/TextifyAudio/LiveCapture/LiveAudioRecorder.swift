@preconcurrency import AVFoundation
import Dispatch
import Foundation

public actor LiveAudioRecorder {
    private let permissionClient: MicrophonePermissionClient
    private let configuration: LiveAudioRecordingConfiguration
    private let engineClient: AudioEngineClient
    private let beforeIngestionTaskCompletion:
        (@Sendable () async -> Void)?

    private var lifecycle: Lifecycle = .idle
    private var nextSessionID: UInt64 = 0
    private var capturedSamples: [Float] = []
    private var speechDetected = false
    private var rmsEmitter = RMSFrameEmitter()
    private var maximumDurationTask: Task<Void, Never>?
    private var maximumDurationDeadlineUptimeNanoseconds: UInt64?
    private var maximumCaptureDurationSeconds: Double?
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
        self.beforeIngestionTaskCompletion = nil
    }

    init(
        permissionClient: MicrophonePermissionClient,
        configuration: LiveAudioRecordingConfiguration,
        engineClient: AudioEngineClient,
        beforeIngestionTaskCompletion:
            @escaping @Sendable () async -> Void
    ) {
        self.permissionClient = permissionClient
        self.configuration = configuration
        self.engineClient = engineClient
        self.beforeIngestionTaskCompletion = beforeIngestionTaskCompletion
    }

    public func startRecording(
        input: LiveAudioInput? = nil,
        maximumDurationSeconds: Double? = nil,
        onCaptureStarted: @escaping @Sendable () -> Void = {},
        onFirstAudio:
            @escaping @Sendable (_ firstSampleUptimeMilliseconds: Int) -> Void = { _ in },
        onSpeechDetected: @escaping @Sendable () -> Void,
        onMaximumDurationReached: @escaping @Sendable () -> Void,
        onRecordingError:
            @escaping @Sendable (LiveAudioRecorderError) -> Void = { _ in }
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

        let (ingestionStream, ingestionPipeline) =
            LiveAudioIngestionPipeline.makeStream(sessionID: sessionID)
        self.ingestionPipeline = ingestionPipeline
        let beforeIngestionTaskCompletion = self.beforeIngestionTaskCompletion
        ingestionTask = Task { [weak self] in
            for await event in ingestionStream {
                await self?.handleIngestionEvent(
                    event,
                    onFirstAudio: onFirstAudio,
                    onSpeechDetected: onSpeechDetected,
                    onMaximumDurationReached: onMaximumDurationReached,
                    onRecordingError: onRecordingError
                )
            }
            await beforeIngestionTaskCompletion?()
        }

        do {
            let selectedInput = input ?? configuration.input
            (engineClient as? AudioInputChangeObserving)?
                .setInputChangeHandler {
                    ingestionPipeline.fail(
                        with: .deviceChangedDuringRecording
                    )
                }
            try engineClient.selectInput(selectedInput)
            try ingestionPipeline.throwIfFailed()
            try engineClient.installTap { buffer, audioTime in
                ingestionPipeline.ingest(
                    buffer,
                    at: audioTime,
                    tapUptimeNanoseconds:
                        DispatchTime.now().uptimeNanoseconds
                )
            }
            try ingestionPipeline.throwIfFailed()
            try engineClient.start()
            try ingestionPipeline.throwIfFailed()
            lifecycle = .recording(sessionID)
            // The actor cannot consume queued tap events until this callback
            // returns, so capture-start always precedes first-audio delivery.
            onCaptureStarted()
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
            let deadlineUptimeNanoseconds =
                maximumDurationDeadlineUptimeNanoseconds
            cancelMaximumDurationCallback()
            await sleepForPostReleaseGrace(
                deadlineUptimeNanoseconds: deadlineUptimeNanoseconds
            )
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
        onFirstAudio:
            @escaping @Sendable (_ firstSampleUptimeMilliseconds: Int) -> Void,
        onSpeechDetected: @escaping @Sendable () -> Void,
        onMaximumDurationReached: @escaping @Sendable () -> Void,
        onRecordingError:
            @escaping @Sendable (LiveAudioRecorderError) -> Void
    ) {
        switch event {
        case .audio(
            let sessionID,
            let canonical,
            let firstAudioMilestone
        ):
            // Startup-failure cleanup drains the stream while the lifecycle is
            // still `.starting`, suppressing every queued capture milestone.
            guard lifecycle.acceptsAudio(for: sessionID) else {
                return
            }
            if let firstAudioMilestone {
                onFirstAudio(
                    firstAudioMilestone.firstSampleUptimeMilliseconds
                )
            }
            if ingest(
                canonical,
                for: sessionID,
                onSpeechDetected: onSpeechDetected
            ) {
                maximumDurationReached(
                    for: sessionID,
                    onMaximumDurationReached
                )
            }
        case .terminalError(let sessionID, let error):
            if recordTerminalError(error, for: sessionID) {
                onRecordingError(error)
            }
        }
    }

    @discardableResult
    private func ingest(
        _ canonical: CanonicalAudioBuffer,
        for sessionID: RecordingSessionID,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) -> Bool {
        guard lifecycle.acceptsAudio(for: sessionID) else {
            return false
        }

        let retainedSamples: ArraySlice<Float>
        let maximumSampleCount: Int?
        if let maximumCaptureDurationSeconds {
            let limit = max(
                0,
                Int(
                    maximumCaptureDurationSeconds
                        * Double(canonical.sampleRate)
                )
            )
            maximumSampleCount = limit
            let remainingSampleCount = max(
                0,
                limit - capturedSamples.count
            )
            retainedSamples = canonical.samples.prefix(remainingSampleCount)
        } else {
            maximumSampleCount = nil
            retainedSamples = canonical.samples[...]
        }

        capturedSamples.append(contentsOf: retainedSamples)
        if !speechDetected,
           rmsEmitter.ingest(
               samples: Array(retainedSamples),
               sampleRate: canonical.sampleRate
           ) {
            speechDetected = true
            onSpeechDetected()
        }
        return maximumSampleCount.map {
            capturedSamples.count >= $0
        } ?? false
    }

    @discardableResult
    private func recordTerminalError(
        _ error: LiveAudioRecorderError,
        for sessionID: RecordingSessionID
    ) -> Bool {
        guard lifecycle.sessionID == sessionID else {
            return false
        }

        switch lifecycle {
        case .recording, .finishing, .stoppedAwaitingFinish:
            lifecycle = .failedAwaitingFinish(sessionID, error)
            capturedSamples.removeAll(keepingCapacity: false)
            stopEngine()
            return true
        case .failedAwaitingFinish, .idle, .starting:
            return false
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
        maximumCaptureDurationSeconds = nil
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
        maximumCaptureDurationSeconds = duration
        let nanoseconds = UInt64(duration * 1_000_000_000)
        let nowUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let (deadline, overflow) =
            nowUptimeNanoseconds.addingReportingOverflow(nanoseconds)
        maximumDurationDeadlineUptimeNanoseconds =
            overflow ? UInt64.max : deadline
        maximumDurationTask = Task { [weak self] in
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
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        maximumDurationDeadlineUptimeNanoseconds = nil
        onMaximumDurationReached()
    }

    private func sleepForPostReleaseGrace(
        deadlineUptimeNanoseconds: UInt64?
    ) async {
        let milliseconds = max(0, configuration.postReleaseGraceMilliseconds)
        guard milliseconds > 0 else {
            return
        }

        let configuredGraceNanoseconds = UInt64(milliseconds) * 1_000_000
        let nanoseconds = Self.boundedPostReleaseGraceNanoseconds(
            configuredGraceNanoseconds: configuredGraceNanoseconds,
            nowUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            deadlineUptimeNanoseconds: deadlineUptimeNanoseconds
        )
        guard nanoseconds > 0 else {
            return
        }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    nonisolated static func boundedPostReleaseGraceNanoseconds(
        configuredGraceNanoseconds: UInt64,
        nowUptimeNanoseconds: UInt64,
        deadlineUptimeNanoseconds: UInt64?
    ) -> UInt64 {
        guard let deadlineUptimeNanoseconds else {
            return configuredGraceNanoseconds
        }
        guard deadlineUptimeNanoseconds > nowUptimeNanoseconds else {
            return 0
        }
        return min(
            configuredGraceNanoseconds,
            deadlineUptimeNanoseconds - nowUptimeNanoseconds
        )
    }

    private func stopEngine(cancelMaximumDuration: Bool = true) {
        (engineClient as? AudioInputChangeObserving)?
            .setInputChangeHandler(nil)
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
        maximumCaptureDurationSeconds = nil
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
        maximumDurationDeadlineUptimeNanoseconds = nil
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
    case audio(
        LiveAudioRecorder.RecordingSessionID,
        CanonicalAudioBuffer,
        LiveAudioFirstAudioMilestone?
    )
    case terminalError(LiveAudioRecorder.RecordingSessionID, LiveAudioRecorderError)
}

private struct LiveAudioFirstAudioMilestone: Sendable {
    let firstSampleUptimeMilliseconds: Int
}

private struct LiveAudioTapTiming: Sendable {
    let hostUptimeMilliseconds: Int?
    let tapUptimeNanoseconds: UInt64

    init(
        audioTime: AVAudioTime,
        tapUptimeNanoseconds: UInt64
    ) {
        if audioTime.isHostTimeValid {
            let hostMilliseconds =
                AVAudioTime.seconds(forHostTime: audioTime.hostTime) * 1_000
            if hostMilliseconds.isFinite,
               hostMilliseconds >= 0,
               hostMilliseconds <= Double(Int.max) {
                hostUptimeMilliseconds = Int(
                    hostMilliseconds.rounded(.down)
                )
            } else {
                hostUptimeMilliseconds = nil
            }
        } else {
            hostUptimeMilliseconds = nil
        }
        self.tapUptimeNanoseconds = tapUptimeNanoseconds
    }

    func firstSampleUptimeMilliseconds(
        canonicalDurationSeconds: Double
    ) -> Int {
        if let hostUptimeMilliseconds {
            return hostUptimeMilliseconds
        }

        let canonicalDurationNanoseconds = UInt64(
            max(0, canonicalDurationSeconds * 1_000_000_000).rounded()
        )
        let firstSampleUptimeNanoseconds =
            tapUptimeNanoseconds >= canonicalDurationNanoseconds
                ? tapUptimeNanoseconds - canonicalDurationNanoseconds
                : 0
        return Int(firstSampleUptimeNanoseconds / 1_000_000)
    }
}

private final class LiveAudioIngestionPipeline: @unchecked Sendable {
    let sessionID: LiveAudioRecorder.RecordingSessionID

    private let lock = NSLock()
    private let conversionSession = CanonicalAudioConverter().makeSession()
    private let continuation: AsyncStream<LiveAudioIngestionEvent>.Continuation
    private var isFinished = false
    private var terminalError: LiveAudioRecorderError?
    private var pendingFirstTapTiming: LiveAudioTapTiming?
    private var didEnqueueFirstAudioMilestone = false

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
            LiveAudioIngestionPipeline(
                sessionID: sessionID,
                continuation: streamPair.continuation
            )
        )
    }

    func ingest(
        _ buffer: AVAudioPCMBuffer,
        at audioTime: AVAudioTime,
        tapUptimeNanoseconds: UInt64
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else {
            return
        }

        if !didEnqueueFirstAudioMilestone,
           pendingFirstTapTiming == nil,
           buffer.frameLength > 0 {
            pendingFirstTapTiming = LiveAudioTapTiming(
                audioTime: audioTime,
                tapUptimeNanoseconds: tapUptimeNanoseconds
            )
        }

        do {
            let canonical = try conversionSession.convert(buffer)
            if !canonical.isEmpty {
                continuation.yield(
                    .audio(
                        sessionID,
                        canonical,
                        makeFirstAudioMilestoneIfNeeded(for: canonical)
                    )
                )
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
                continuation.yield(
                    .audio(
                        sessionID,
                        drained,
                        makeFirstAudioMilestoneIfNeeded(for: drained)
                    )
                )
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

    func fail(with error: LiveAudioRecorderError) {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else {
            return
        }
        finishLocked(with: error)
    }

    func throwIfFailed() throws {
        lock.lock()
        defer { lock.unlock() }

        if let terminalError {
            throw terminalError
        }
    }

    private func finishLocked(with error: LiveAudioRecorderError? = nil) {
        guard !isFinished else {
            return
        }

        if let error {
            terminalError = error
            continuation.yield(.terminalError(sessionID, error))
        }
        isFinished = true
        continuation.finish()
    }

    private func makeFirstAudioMilestoneIfNeeded(
        for canonical: CanonicalAudioBuffer
    ) -> LiveAudioFirstAudioMilestone? {
        guard !didEnqueueFirstAudioMilestone,
              let pendingFirstTapTiming
        else {
            return nil
        }

        didEnqueueFirstAudioMilestone = true
        self.pendingFirstTapTiming = nil
        return LiveAudioFirstAudioMilestone(
            firstSampleUptimeMilliseconds:
                pendingFirstTapTiming.firstSampleUptimeMilliseconds(
                    canonicalDurationSeconds: canonical.durationSeconds
                )
        )
    }
}
