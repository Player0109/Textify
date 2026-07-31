@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio

public final class SystemAudioEngineClient: AudioEngineClient, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let resolveDeviceID:
        @Sendable (LiveAudioInput) throws -> AudioDeviceID
    private var tapInstalled = false

    public init() {
        self.resolveDeviceID = { input in
            try CoreAudioInputDevices.resolveDeviceID(for: input)
        }
    }

    init(
        resolveDeviceID: @escaping @Sendable (
            LiveAudioInput
        ) throws -> AudioDeviceID
    ) {
        self.resolveDeviceID = resolveDeviceID
    }

    public func selectInput(_ input: LiveAudioInput) throws {
        let deviceID = try resolveDeviceID(input)
        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            throw LiveAudioRecorderError.inputNodeUnavailable
        }

        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            if case .device = input {
                throw LiveAudioRecorderError.selectedInputUnavailable
            }
            throw LiveAudioRecorderError.inputNodeUnavailable
        }

        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            if case .device = input {
                throw LiveAudioRecorderError.selectedInputUnavailable
            }
            throw LiveAudioRecorderError.unsupportedInputFormat
        }
    }

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
        tapInstalled = true
    }

    public func removeTap() {
        guard tapInstalled else {
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }
}
