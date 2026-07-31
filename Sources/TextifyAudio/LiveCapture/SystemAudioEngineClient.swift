@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio

public final class SystemAudioEngineClient:
    AudioEngineClient,
    AudioInputChangeObserving,
    @unchecked Sendable
{
    private let engine = AVAudioEngine()
    private let resolveDeviceID:
        @Sendable (LiveAudioInput) throws -> AudioDeviceID
    private let makeInputDeviceObserver: (
        AudioDeviceID,
        String,
        AudioUnit,
        @escaping @Sendable () -> Void
    ) -> any CoreAudioInputDeviceObserving
    private let observationLock = NSLock()
    private var inputChangeHandler: (@Sendable () -> Void)?
    private var inputDeviceObserver: (any CoreAudioInputDeviceObserving)?
    private var tapInstalled = false

    public convenience init() {
        self.init(resolveDeviceID: { input in
            try CoreAudioInputDevices.resolveDeviceID(for: input)
        })
    }

    init(
        resolveDeviceID: @escaping @Sendable (
            LiveAudioInput
        ) throws -> AudioDeviceID,
        makeInputDeviceObserver: @escaping (
            AudioDeviceID,
            String,
            AudioUnit,
            @escaping @Sendable () -> Void
        ) -> any CoreAudioInputDeviceObserving = {
            deviceID,
            expectedUID,
            audioUnit,
            onChange in
            CoreAudioInputDeviceObserver(
                deviceID: deviceID,
                expectedUID: expectedUID,
                audioUnit: audioUnit,
                onChange: onChange
            )
        }
    ) {
        self.resolveDeviceID = resolveDeviceID
        self.makeInputDeviceObserver = makeInputDeviceObserver
    }

    public func selectInput(_ input: LiveAudioInput) throws {
        stopInputObservation()
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

        do {
            let deviceUID = try CoreAudioInputDevices.deviceUID(
                for: deviceID
            )
            if case let .device(expectedUID) = input,
               deviceUID != expectedUID
            {
                throw LiveAudioRecorderError.selectedInputUnavailable
            }
            observationLock.lock()
            let selectedInputChangeHandler = inputChangeHandler
            observationLock.unlock()
            let observer = makeInputDeviceObserver(
                deviceID,
                deviceUID,
                audioUnit
            ) {
                selectedInputChangeHandler?()
            }
            observationLock.lock()
            inputDeviceObserver = observer
            observationLock.unlock()

            do {
                try observer.start()
            } catch {
                observationLock.lock()
                if let currentObserver = inputDeviceObserver,
                   currentObserver === observer
                {
                    inputDeviceObserver = nil
                }
                observationLock.unlock()
                observer.stop()
                throw error
            }
        } catch {
            if case .device = input {
                throw LiveAudioRecorderError.selectedInputUnavailable
            }
            throw LiveAudioRecorderError.inputNodeUnavailable
        }
    }

    public func start() throws {
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        stopInputObservation()
        engine.stop()
    }

    public func reset() {
        stopInputObservation()
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

    func setInputChangeHandler(
        _ handler: (@Sendable () -> Void)?
    ) {
        observationLock.lock()
        inputChangeHandler = handler
        observationLock.unlock()
    }

    private func stopInputObservation() {
        observationLock.lock()
        let observer = inputDeviceObserver
        inputDeviceObserver = nil
        observationLock.unlock()
        observer?.stop()
    }
}
