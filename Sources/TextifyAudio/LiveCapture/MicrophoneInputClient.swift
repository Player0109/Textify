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
            let session = MicrophoneLevelStreamSession(
                engineClient: engineClient
            )
            continuation.onTermination = { @Sendable _ in
                session.stop()
            }

            do {
                try session.start(input: input) { level in
                    continuation.yield(level)
                }
            } catch {
                session.stop()
                continuation.finish(throwing: error)
            }
        }
    }
}

private final class MicrophoneLevelStreamSession: @unchecked Sendable {
    private let engineClient: any AudioEngineClient
    private let lock = NSLock()
    private var isStopped = false

    init(engineClient: any AudioEngineClient) {
        self.engineClient = engineClient
    }

    func start(
        input: LiveAudioInput,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        try engineClient.selectInput(input)
        try engineClient.installTap { buffer, _ in
            onLevel(Self.normalizedLevel(from: buffer))
        }
        try engineClient.start()
    }

    func stop() {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        isStopped = true
        lock.unlock()

        engineClient.removeTap()
        engineClient.stop()
        engineClient.reset()
    }

    deinit {
        stop()
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
