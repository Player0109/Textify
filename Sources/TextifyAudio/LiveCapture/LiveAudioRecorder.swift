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
        guard !isRecording else {
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

        do {
            let tapConverter = CanonicalAudioConverter()
            try engineClient.installTap { [weak self] buffer, _ in
                do {
                    let canonical = try tapConverter.convert(buffer)
                    Task { await self?.ingest(canonical, onSpeechDetected: onSpeechDetected) }
                } catch let error as LiveAudioRecorderError {
                    Task { await self?.recordTerminalError(error) }
                } catch {
                    Task { await self?.recordTerminalError(.conversionFailed) }
                }
            }
            try engineClient.start()
            scheduleMaximumDurationCallback(onMaximumDurationReached)
        } catch let error as LiveAudioRecorderError {
            stopEngine()
            throw error
        } catch {
            stopEngine()
            throw LiveAudioRecorderError.engineStartFailed
        }
    }

    public func finishRecording() async throws -> CanonicalAudioBuffer {
        try consumeTerminalErrorIfPresent()

        guard isRecording || terminalStopReason != nil else {
            throw LiveAudioRecorderError.notRecording
        }

        if isRecording {
            cancelMaximumDurationCallback()
            await sleepForPostReleaseGrace()
            try consumeTerminalErrorIfPresent()
            if isRecording {
                stopEngine()
            }
            try consumeTerminalErrorIfPresent()
        }

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

    private func ingest(
        _ canonical: CanonicalAudioBuffer,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) {
        guard isRecording else {
            return
        }

        capturedSamples.append(contentsOf: canonical.samples)
        if !speechDetected, rmsEmitter.ingest(samples: canonical.samples, sampleRate: canonical.sampleRate) {
            speechDetected = true
            onSpeechDetected()
        }
    }

    private func recordTerminalError(_ error: LiveAudioRecorderError) {
        guard isRecording else {
            return
        }
        terminalError = error
        stopEngine()
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

    private func consumeTerminalErrorIfPresent() throws {
        if let terminalError {
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
