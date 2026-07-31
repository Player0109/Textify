import AudioToolbox
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

    static func isAvailable(
        deviceID: AudioDeviceID,
        expectedUID: String
    ) -> Bool {
        guard let currentDeviceIDs = try? deviceIDs(),
              currentDeviceIDs.contains(deviceID),
              let translatedDeviceID = try? Self.deviceID(
                forUID: expectedUID
              ),
              translatedDeviceID == deviceID,
              isAlive(deviceID),
              hasInputStreams(deviceID),
              let currentUID = try? stringProperty(
                kAudioDevicePropertyDeviceUID,
                of: deviceID
              )
        else {
            return false
        }
        return currentUID == expectedUID
    }

    static func deviceUID(for deviceID: AudioDeviceID) throws -> String {
        try stringProperty(
            kAudioDevicePropertyDeviceUID,
            of: deviceID
        )
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

protocol CoreAudioInputDeviceObserving: AnyObject, Sendable {
    func start() throws
    func stop()
}

protocol CoreAudioInputDeviceObserverOperations: AnyObject, Sendable {
    func addObjectPropertyListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus

    func removeObjectPropertyListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus

    func addAudioUnitPropertyListener(
        audioUnit: AudioUnit,
        listener: AudioUnitPropertyListenerProc,
        userData: UnsafeMutableRawPointer
    ) -> OSStatus

    func removeAudioUnitPropertyListener(
        audioUnit: AudioUnit,
        listener: AudioUnitPropertyListenerProc,
        userData: UnsafeMutableRawPointer
    ) -> OSStatus

    func bindingIsValid(
        deviceID: AudioDeviceID,
        expectedUID: String,
        audioUnit: AudioUnit
    ) -> Bool
}

final class SystemCoreAudioInputDeviceObserverOperations:
    CoreAudioInputDeviceObserverOperations,
    @unchecked Sendable
{
    func addObjectPropertyListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        var address = address
        return AudioObjectAddPropertyListenerBlock(
            objectID,
            &address,
            queue,
            listener
        )
    }

    func removeObjectPropertyListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        var address = address
        return AudioObjectRemovePropertyListenerBlock(
            objectID,
            &address,
            queue,
            listener
        )
    }

    func addAudioUnitPropertyListener(
        audioUnit: AudioUnit,
        listener: AudioUnitPropertyListenerProc,
        userData: UnsafeMutableRawPointer
    ) -> OSStatus {
        AudioUnitAddPropertyListener(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            listener,
            userData
        )
    }

    func removeAudioUnitPropertyListener(
        audioUnit: AudioUnit,
        listener: AudioUnitPropertyListenerProc,
        userData: UnsafeMutableRawPointer
    ) -> OSStatus {
        AudioUnitRemovePropertyListenerWithUserData(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            listener,
            userData
        )
    }

    func bindingIsValid(
        deviceID: AudioDeviceID,
        expectedUID: String,
        audioUnit: AudioUnit
    ) -> Bool {
        guard CoreAudioInputDevices.isAvailable(
            deviceID: deviceID,
            expectedUID: expectedUID
        ) else {
            return false
        }

        var currentDeviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &currentDeviceID,
            &dataSize
        ) == noErr && currentDeviceID == deviceID
    }
}

private final class CoreAudioInputDeviceObserverState: @unchecked Sendable {
    private enum Lifecycle {
        case waitingToStart
        case active
        case stopped
    }

    private let deviceID: AudioDeviceID
    private let expectedUID: String
    private let audioUnit: AudioUnit
    private let operations: any CoreAudioInputDeviceObserverOperations
    private let onChange: @Sendable () -> Void
    private let validationQueue: DispatchQueue
    private let deliveryQueue: DispatchQueue
    private let lock = NSLock()
    private var lifecycle = Lifecycle.waitingToStart
    private var didNotify = false

    init(
        deviceID: AudioDeviceID,
        expectedUID: String,
        audioUnit: AudioUnit,
        operations: any CoreAudioInputDeviceObserverOperations,
        validationQueue: DispatchQueue,
        deliveryQueue: DispatchQueue,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.deviceID = deviceID
        self.expectedUID = expectedUID
        self.audioUnit = audioUnit
        self.operations = operations
        self.validationQueue = validationQueue
        self.deliveryQueue = deliveryQueue
        self.onChange = onChange
    }

    func activateIfBindingIsValid() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard lifecycle == .waitingToStart else {
            return false
        }
        guard operations.bindingIsValid(
            deviceID: deviceID,
            expectedUID: expectedUID,
            audioUnit: audioUnit
        ) else {
            lifecycle = .stopped
            return false
        }
        lifecycle = .active
        return true
    }

    func scheduleObjectValidation(
        numberAddresses: UInt32,
        addresses: UnsafePointer<AudioObjectPropertyAddress>
    ) {
        switch Self.notificationAction(
            numberAddresses: numberAddresses,
            addresses: addresses
        ) {
        case .ignore:
            break
        case .validateBinding:
            scheduleValidation()
        case .invalidateBinding:
            scheduleInvalidation()
        }
    }

    func scheduleAudioUnitValidation(
        audioUnit: AudioUnit,
        propertyID: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement
    ) {
        guard audioUnit == self.audioUnit,
              propertyID == kAudioOutputUnitProperty_CurrentDevice,
              scope == kAudioUnitScope_Global,
              element == 0
        else {
            return
        }
        scheduleValidation()
    }

    func stop() {
        lock.lock()
        lifecycle = .stopped
        lock.unlock()
    }

    private func scheduleValidation() {
        validationQueue.async { [weak self] in
            self?.validateIfActive()
        }
    }

    private func scheduleInvalidation() {
        validationQueue.async { [weak self] in
            self?.invalidateIfActive()
        }
    }

    private func validateIfActive() {
        lock.lock()
        guard lifecycle == .active, !didNotify else {
            lock.unlock()
            return
        }

        let bindingIsValid = operations.bindingIsValid(
            deviceID: deviceID,
            expectedUID: expectedUID,
            audioUnit: audioUnit
        )
        guard !bindingIsValid else {
            lock.unlock()
            return
        }
        didNotify = true
        lock.unlock()
        scheduleDelivery()
    }

    private func invalidateIfActive() {
        lock.lock()
        guard lifecycle == .active, !didNotify else {
            lock.unlock()
            return
        }
        didNotify = true
        lock.unlock()
        scheduleDelivery()
    }

    private func scheduleDelivery() {
        deliveryQueue.async { [weak self] in
            self?.deliverChangeIfActive()
        }
    }

    private func deliverChangeIfActive() {
        lock.lock()
        guard lifecycle == .active else {
            lock.unlock()
            return
        }
        defer { lock.unlock() }
        onChange()
    }

    private enum ObjectNotificationAction {
        case ignore
        case validateBinding
        case invalidateBinding
    }

    private static func notificationAction(
        numberAddresses: UInt32,
        addresses: UnsafePointer<AudioObjectPropertyAddress>
    ) -> ObjectNotificationAction {
        var shouldValidateBinding = false
        for index in 0 ..< Int(numberAddresses) {
            let address = addresses[index]
            switch (
                address.mSelector,
                address.mScope,
                address.mElement
            ) {
            case (
                kAudioHardwarePropertyDevices,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            ),
            (
                kAudioDevicePropertyDeviceIsAlive,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            ):
                shouldValidateBinding = true
            case (
                kAudioDevicePropertyStreams,
                kAudioObjectPropertyScopeInput,
                kAudioObjectPropertyElementMain
            ):
                return .invalidateBinding
            default:
                continue
            }
        }
        return shouldValidateBinding ? .validateBinding : .ignore
    }
}

private final class CoreAudioInputDeviceObserverCallbackRegistry:
    @unchecked Sendable
{
    static let shared = CoreAudioInputDeviceObserverCallbackRegistry()

    private let lock = NSLock()
    private var nextToken: UInt = 1
    private var states: [UInt: CoreAudioInputDeviceObserverState] = [:]

    private init() {}

    func register(
        _ state: CoreAudioInputDeviceObserverState
    ) -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }

        let token = nextToken
        nextToken += 1
        states[token] = state
        return UnsafeMutableRawPointer(bitPattern: token)!
    }

    func state(
        for tokenPointer: UnsafeMutableRawPointer
    ) -> CoreAudioInputDeviceObserverState? {
        lock.lock()
        defer { lock.unlock() }
        return states[UInt(bitPattern: tokenPointer)]
    }

    func unregister(
        tokenPointer: UnsafeMutableRawPointer,
        state: CoreAudioInputDeviceObserverState
    ) {
        lock.lock()
        defer { lock.unlock() }
        let token = UInt(bitPattern: tokenPointer)
        guard states[token] === state else {
            return
        }
        states.removeValue(forKey: token)
    }
}

private func textifyAudioInputUnitPropertyDidChange(
    _ reference: UnsafeMutableRawPointer,
    _ audioUnit: AudioUnit,
    _ propertyID: AudioUnitPropertyID,
    _ scope: AudioUnitScope,
    _ element: AudioUnitElement
) {
    CoreAudioInputDeviceObserverCallbackRegistry.shared
        .state(for: reference)?
        .scheduleAudioUnitValidation(
            audioUnit: audioUnit,
            propertyID: propertyID,
            scope: scope,
            element: element
        )
}

final class CoreAudioInputDeviceObserver:
    CoreAudioInputDeviceObserving,
    @unchecked Sendable
{
    private struct Registration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
    }

    private let state: CoreAudioInputDeviceObserverState
    private let deviceID: AudioDeviceID
    private let audioUnit: AudioUnit
    private let operations: any CoreAudioInputDeviceObserverOperations
    private let queue: DispatchQueue
    private let listener: AudioObjectPropertyListenerBlock
    private let lifecycleLock = NSLock()
    private var registrations: [Registration] = []
    private var audioUnitCallbackToken: UnsafeMutableRawPointer?
    private var isStarted = false
    private var isStopped = false

    init(
        deviceID: AudioDeviceID,
        expectedUID: String,
        audioUnit: AudioUnit,
        operations: any CoreAudioInputDeviceObserverOperations =
            SystemCoreAudioInputDeviceObserverOperations(),
        validationQueue: DispatchQueue = DispatchQueue(
            label: "io.github.Player0109.Textify.audio-input-observer"
        ),
        deliveryQueue: DispatchQueue = DispatchQueue(
            label:
                "io.github.Player0109.Textify.audio-input-observer-delivery"
        ),
        onChange: @escaping @Sendable () -> Void
    ) {
        let state = CoreAudioInputDeviceObserverState(
            deviceID: deviceID,
            expectedUID: expectedUID,
            audioUnit: audioUnit,
            operations: operations,
            validationQueue: validationQueue,
            deliveryQueue: deliveryQueue,
            onChange: onChange
        )
        self.deviceID = deviceID
        self.audioUnit = audioUnit
        self.operations = operations
        self.queue = validationQueue
        self.state = state
        self.listener = { numberAddresses, addresses in
            state.scheduleObjectValidation(
                numberAddresses: numberAddresses,
                addresses: addresses
            )
        }
    }

    func start() throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard !isStopped else {
            throw LiveAudioRecorderError.selectedInputUnavailable
        }
        guard !isStarted else {
            return
        }

        for registration in requestedRegistrations {
            let status = operations.addObjectPropertyListener(
                objectID: registration.objectID,
                address: registration.address,
                queue: queue,
                listener: listener
            )
            guard status == noErr else {
                stopAndRemoveRegistrationsLocked()
                throw LiveAudioRecorderError.selectedInputUnavailable
            }
            registrations.append(registration)
        }

        let callbackToken =
            CoreAudioInputDeviceObserverCallbackRegistry.shared.register(
                state
            )
        let audioUnitStatus = operations.addAudioUnitPropertyListener(
            audioUnit: audioUnit,
            listener: textifyAudioInputUnitPropertyDidChange,
            userData: callbackToken
        )
        guard audioUnitStatus == noErr else {
            CoreAudioInputDeviceObserverCallbackRegistry.shared.unregister(
                tokenPointer: callbackToken,
                state: state
            )
            stopAndRemoveRegistrationsLocked()
            throw LiveAudioRecorderError.selectedInputUnavailable
        }
        audioUnitCallbackToken = callbackToken

        guard state.activateIfBindingIsValid() else {
            stopAndRemoveRegistrationsLocked()
            throw LiveAudioRecorderError.selectedInputUnavailable
        }
        isStarted = true
    }

    func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        stopAndRemoveRegistrationsLocked()
    }

    deinit {
        stop()
    }

    private var requestedRegistrations: [Registration] {
        [
            Registration(
                objectID: AudioObjectID(kAudioObjectSystemObject),
                address: AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDevices,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
            ),
            Registration(
                objectID: deviceID,
                address: AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceIsAlive,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
            ),
            Registration(
                objectID: deviceID,
                address: AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreams,
                    mScope: kAudioObjectPropertyScopeInput,
                    mElement: kAudioObjectPropertyElementMain
                )
            ),
        ]
    }

    private func stopAndRemoveRegistrationsLocked() {
        guard !isStopped else {
            return
        }
        isStopped = true
        state.stop()

        if let callbackToken = audioUnitCallbackToken {
            _ = operations.removeAudioUnitPropertyListener(
                audioUnit: audioUnit,
                listener: textifyAudioInputUnitPropertyDidChange,
                userData: callbackToken
            )
            CoreAudioInputDeviceObserverCallbackRegistry.shared.unregister(
                tokenPointer: callbackToken,
                state: state
            )
            audioUnitCallbackToken = nil
        }

        for registration in registrations.reversed() {
            _ = operations.removeObjectPropertyListener(
                objectID: registration.objectID,
                address: registration.address,
                queue: queue,
                listener: listener
            )
        }
        registrations.removeAll()
        isStarted = false
    }
}
