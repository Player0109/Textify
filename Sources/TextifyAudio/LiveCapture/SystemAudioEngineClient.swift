@preconcurrency import AVFoundation

public final class SystemAudioEngineClient: AudioEngineClient {
    private let engine = AVAudioEngine()

    public init() {}

    public func start() throws {
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    public func reset() {
        engine.reset()
    }

    public func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, time in
            handler(buffer, time)
        }
    }

    public func removeTap() {
        engine.inputNode.removeTap(onBus: 0)
    }
}
