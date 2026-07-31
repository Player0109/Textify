@preconcurrency import AVFoundation
import Foundation

public struct MicrophoneInputClient: Sendable {
    private let inputDevicesClosure:
        @Sendable () throws -> [MicrophoneDevice]
    private let levelStreamClosure:
        @Sendable (LiveAudioInput) -> AsyncThrowingStream<Float, Error>

    public init(
        inputDevices: @escaping @Sendable () throws -> [MicrophoneDevice],
        levelStream: @escaping @Sendable (
            LiveAudioInput
        ) -> AsyncThrowingStream<Float, Error>
    ) {
        self.inputDevicesClosure = inputDevices
        self.levelStreamClosure = levelStream
    }

    public func inputDevices() throws -> [MicrophoneDevice] {
        try inputDevicesClosure()
    }

    public func levelStream(
        for input: LiveAudioInput
    ) -> AsyncThrowingStream<Float, Error> {
        levelStreamClosure(input)
    }

    public static let live = MicrophoneInputClient.system(
        inputDevices: {
            try CoreAudioInputDevices.inputDevices()
        },
        makeEngine: { SystemAudioEngineClient() }
    )

    static func system(
        inputDevices: @escaping @Sendable () throws -> [MicrophoneDevice],
        makeEngine: @escaping @Sendable () -> any AudioEngineClient
    ) -> MicrophoneInputClient {
        MicrophoneInputClient(
            inputDevices: inputDevices,
            levelStream: { input in
                makeLevelStream(
                    input: input,
                    engineClient: makeEngine()
                )
            }
        )
    }

    private static func makeLevelStream(
        input: LiveAudioInput,
        engineClient: any AudioEngineClient
    ) -> AsyncThrowingStream<Float, Error> {
        AsyncThrowingStream(
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation in
            let inputChangeError: LiveAudioRecorderError
            switch input {
            case .systemDefault:
                inputChangeError = .inputNodeUnavailable
            case .device:
                inputChangeError = .selectedInputUnavailable
            }
            let session = MicrophoneLevelStreamSession(
                engineClient: engineClient
            )
            continuation.onTermination = { @Sendable _ in
                session.stop()
            }

            do {
                try session.start(
                    input: input,
                    inputChangeError: inputChangeError,
                    onLevel: { level in
                        continuation.yield(level)
                    },
                    onInputChange: {
                        Task {
                            continuation.finish(
                                throwing: inputChangeError
                            )
                        }
                    }
                )
            } catch {
                session.stop()
                continuation.finish(throwing: error)
            }
        }
    }
}

private final class MicrophoneLevelStreamSession: @unchecked Sendable {
    private let engineClient: any AudioEngineClient
    private let stateLock = NSLock()
    private let engineLock = NSLock()
    private let teardownQueue = DispatchQueue(
        label: "io.github.Player0109.Textify.microphone-level-teardown"
    )
    private var isStopped = false
    private var stopError: LiveAudioRecorderError?
    private var didTearDown = false

    init(engineClient: any AudioEngineClient) {
        self.engineClient = engineClient
    }

    func start(
        input: LiveAudioInput,
        inputChangeError: LiveAudioRecorderError,
        onLevel: @escaping @Sendable (Float) -> Void,
        onInputChange: @escaping @Sendable () -> Void
    ) throws {
        (engineClient as? AudioInputChangeObserving)?
            .setInputChangeHandler { [weak self] in
                self?.inputChanged(
                    with: inputChangeError,
                    onInputChange: onInputChange
                )
            }

        try performStartupStep {
            try engineClient.selectInput(input)
        }
        try performStartupStep {
            try engineClient.installTap { buffer, _ in
                onLevel(Self.normalizedLevel(from: buffer))
            }
        }
        try performStartupStep {
            try engineClient.start()
        }
    }

    func stop() {
        markStopped()
        tearDownEngine()
    }

    private func inputChanged(
        with error: LiveAudioRecorderError,
        onInputChange: @escaping @Sendable () -> Void
    ) {
        guard markStopped(with: error) else {
            return
        }

        teardownQueue.async { [weak self] in
            self?.tearDownEngine()
        }
        onInputChange()
    }

    private func performStartupStep(
        _ operation: () throws -> Void
    ) throws {
        engineLock.lock()
        defer { engineLock.unlock() }

        if let error = startupStopError() {
            tearDownEngineLocked()
            throw error
        }

        do {
            try operation()
        } catch {
            markStopped()
            tearDownEngineLocked()
            throw error
        }

        if let error = startupStopError() {
            tearDownEngineLocked()
            throw error
        }
    }

    @discardableResult
    private func markStopped(
        with error: LiveAudioRecorderError? = nil
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isStopped else {
            return false
        }
        isStopped = true
        stopError = error
        return true
    }

    private func startupStopError() -> Error? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isStopped else {
            return nil
        }
        return stopError ?? CancellationError()
    }

    private func tearDownEngine() {
        engineLock.lock()
        defer { engineLock.unlock() }
        tearDownEngineLocked()
    }

    private func tearDownEngineLocked() {
        stateLock.lock()
        guard !didTearDown else {
            stateLock.unlock()
            return
        }
        didTearDown = true
        stateLock.unlock()

        (engineClient as? AudioInputChangeObserving)?
            .setInputChangeHandler(nil)
        engineClient.removeTap()
        engineClient.stop()
        engineClient.reset()
    }

    deinit {
        markStopped()
        tearDownEngine()
    }

    private static func normalizedLevel(
        from buffer: AVAudioPCMBuffer
    ) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return 0
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return 0
        }

        var sumSquares = Double(0)
        var sampleCount = 0
        if buffer.format.isInterleaved {
            for index in 0..<(frameCount * channelCount) {
                let sample = Double(channelData[0][index])
                guard sample.isFinite else {
                    continue
                }
                sumSquares += sample * sample
                sampleCount += 1
            }
        } else {
            for channel in 0..<channelCount {
                for frame in 0..<frameCount {
                    let sample = Double(channelData[channel][frame])
                    guard sample.isFinite else {
                        continue
                    }
                    sumSquares += sample * sample
                    sampleCount += 1
                }
            }
        }

        guard sampleCount > 0 else {
            return 0
        }
        let rms = (sumSquares / Double(sampleCount)).squareRoot()
        guard rms.isFinite, rms > 0 else {
            return 0
        }

        let decibels = 20 * log10(rms)
        return Float(min(1, max(0, (decibels + 60) / 60)))
    }
}
