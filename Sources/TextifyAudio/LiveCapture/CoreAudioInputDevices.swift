import CoreAudio
import Foundation

enum CoreAudioInputDevices {
    static func inputDevices() throws -> [MicrophoneDevice] {
        let devices = try deviceIDs().compactMap { deviceID -> MicrophoneDevice? in
            guard isAlive(deviceID),
                  hasInputStreams(deviceID),
                  let uid = try? stringProperty(
                    kAudioDevicePropertyDeviceUID,
                    of: deviceID
                  ),
                  let name = try? stringProperty(
                    kAudioObjectPropertyName,
                    of: deviceID
                  )
            else {
                return nil
            }

            return MicrophoneDevice(id: uid, displayName: name)
        }

        return devices.sorted { lhs, rhs in
            let lhsName = lhs.displayName.lowercased()
            let rhsName = rhs.displayName.lowercased()
            if lhsName != rhsName {
                return lhsName < rhsName
            }
            if lhs.displayName != rhs.displayName {
                return lhs.displayName < rhs.displayName
            }
            return lhs.id < rhs.id
        }
    }

    static func resolveDeviceID(for input: LiveAudioInput) throws -> AudioDeviceID {
        switch input {
        case .systemDefault:
            let deviceID = try defaultInputDeviceID()
            guard deviceID != kAudioObjectUnknown,
                  isAlive(deviceID),
                  hasInputStreams(deviceID)
            else {
                throw LiveAudioRecorderError.inputNodeUnavailable
            }
            return deviceID
        case .device(let deviceUID):
            guard let deviceID = try? deviceID(forUID: deviceUID),
                  deviceID != kAudioObjectUnknown,
                  isAlive(deviceID),
                  hasInputStreams(deviceID)
            else {
                throw LiveAudioRecorderError.selectedInputUnavailable
            }
            return deviceID
        }
    }

    private static func deviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            throw LiveAudioRecorderError.inputNodeUnavailable
        }

        guard dataSize % UInt32(MemoryLayout<AudioDeviceID>.size) == 0 else {
            throw LiveAudioRecorderError.inputNodeUnavailable
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else {
            return []
        }

        var deviceIDs = [AudioDeviceID](
            repeating: kAudioObjectUnknown,
            count: count
        )
        let status = deviceIDs.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                bytes.baseAddress!
            )
        }
        guard status == noErr else {
            throw LiveAudioRecorderError.inputNodeUnavailable
        }
        return deviceIDs
    }

    private static func defaultInputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        ) == noErr else {
            throw LiveAudioRecorderError.inputNodeUnavailable
        }
        return deviceID
    }

    private static func deviceID(forUID deviceUID: String) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var qualifier = deviceUID as CFString
        var deviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &qualifier) { qualifierPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                qualifierPointer,
                &dataSize,
                &deviceID
            )
        }
        guard status == noErr else {
            throw LiveAudioRecorderError.selectedInputUnavailable
        }
        return deviceID
    }

    private static func isAlive(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        ) == noErr && value != 0
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr && dataSize >= MemoryLayout<AudioStreamID>.size
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        of deviceID: AudioDeviceID
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        ) == noErr,
              let value
        else {
            throw LiveAudioRecorderError.inputNodeUnavailable
        }
        return value.takeRetainedValue() as String
    }
}
