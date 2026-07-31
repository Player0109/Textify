import AudioToolbox
import CoreAudio
import Foundation
import XCTest
@testable import TextifyAudio

final class CoreAudioInputDeviceObserverTests: XCTestCase {
    private let deviceID = AudioDeviceID(42)
    private let expectedUID = "test-device-uid"

    func testFiltersNotificationsToObservedBindingProperties() throws {
        let operations = FakeCoreAudioInputDeviceObserverOperations(
            bindingResults: [true, true, false]
        )
        let validationQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.validation"
        )
        let deliveryQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.delivery"
        )
        let changeCount = LockedCounter()
        let observer = makeObserver(
            operations: operations,
            validationQueue: validationQueue,
            deliveryQueue: deliveryQueue
        ) {
            changeCount.increment()
        }

        try observer.start()
        XCTAssertEqual(operations.bindingCallCount, 1)

        operations.emitObjectChange(
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        )
        operations.emitAudioUnitChange(
            audioUnit: fakeAudioUnit,
            propertyID: kAudioOutputUnitProperty_CurrentDevice,
            scope: kAudioUnitScope_Input,
            element: 0
        )
        flush(validationQueue, deliveryQueue)

        XCTAssertEqual(operations.bindingCallCount, 1)
        XCTAssertEqual(changeCount.value, 0)

        operations.emitObjectChange(
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        )
        flush(validationQueue, deliveryQueue)

        XCTAssertEqual(operations.bindingCallCount, 2)
        XCTAssertEqual(changeCount.value, 0)

        operations.emitAudioUnitChange(
            audioUnit: fakeAudioUnit,
            propertyID: kAudioOutputUnitProperty_CurrentDevice,
            scope: kAudioUnitScope_Global,
            element: 0
        )
        flush(validationQueue, deliveryQueue)

        XCTAssertEqual(operations.bindingCallCount, 3)
        XCTAssertEqual(changeCount.value, 1)
        observer.stop()
    }

    func testInputStreamMutationInvalidatesAnOtherwiseStableBinding()
        throws
    {
        let operations = FakeCoreAudioInputDeviceObserverOperations(
            bindingResults: [true, true]
        )
        let validationQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.stream-validation"
        )
        let deliveryQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.stream-delivery"
        )
        let changeCount = LockedCounter()
        let observer = makeObserver(
            operations: operations,
            validationQueue: validationQueue,
            deliveryQueue: deliveryQueue
        ) {
            changeCount.increment()
        }

        try observer.start()
        operations.emitObjectChange(
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
        )
        flush(validationQueue, deliveryQueue)

        XCTAssertEqual(operations.bindingCallCount, 1)
        XCTAssertEqual(changeCount.value, 1)
        observer.stop()
    }

    func testObjectRegistrationFailureRollsBackOnlySuccessfulRegistrations() {
        let operations = FakeCoreAudioInputDeviceObserverOperations(
            objectAddStatuses: [noErr, noErr, OSStatus(-1)]
        )
        let observer = makeObserver(operations: operations)

        XCTAssertThrowsError(try observer.start())

        XCTAssertEqual(
            operations.addedObjectSelectors,
            [
                kAudioHardwarePropertyDevices,
                kAudioDevicePropertyDeviceIsAlive,
                kAudioDevicePropertyStreams,
            ]
        )
        XCTAssertEqual(
            operations.removedObjectSelectors,
            [
                kAudioDevicePropertyDeviceIsAlive,
                kAudioHardwarePropertyDevices,
            ]
        )
        XCTAssertEqual(operations.audioUnitAddCallCount, 0)

        observer.stop()
        XCTAssertEqual(operations.objectRemoveCallCount, 2)
    }

    func testAudioUnitRegistrationFailureRollsBackObjectRegistrations() {
        let operations = FakeCoreAudioInputDeviceObserverOperations(
            audioUnitAddStatus: OSStatus(-1)
        )
        let observer = makeObserver(operations: operations)

        XCTAssertThrowsError(try observer.start())

        XCTAssertEqual(operations.objectAddCallCount, 3)
        XCTAssertEqual(operations.objectRemoveCallCount, 3)
        XCTAssertEqual(operations.audioUnitAddCallCount, 1)
        XCTAssertEqual(operations.audioUnitRemoveCallCount, 0)
    }

    func testStopWaitsForStartAndRemovesEveryCompletedRegistration() {
        let firstAddEntered = DispatchSemaphore(value: 0)
        let allowFirstAddToReturn = DispatchSemaphore(value: 0)
        let stopAttempted = DispatchSemaphore(value: 0)
        let startFinished = DispatchSemaphore(value: 0)
        let stopFinished = DispatchSemaphore(value: 0)
        let operations = FakeCoreAudioInputDeviceObserverOperations()
        operations.onAddObject = { index in
            guard index == 0 else {
                return
            }
            firstAddEntered.signal()
            allowFirstAddToReturn.wait()
        }
        let observer = makeObserver(operations: operations)
        let startResult = LockedResult()

        DispatchQueue.global().async {
            do {
                try observer.start()
                startResult.store(.success(()))
            } catch {
                startResult.store(.failure(error))
            }
            startFinished.signal()
        }

        XCTAssertEqual(firstAddEntered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            stopAttempted.signal()
            observer.stop()
            stopFinished.signal()
        }
        XCTAssertEqual(stopAttempted.wait(timeout: .now() + 2), .success)
        allowFirstAddToReturn.signal()

        XCTAssertEqual(startFinished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(stopFinished.wait(timeout: .now() + 2), .success)
        XCTAssertNil(startResult.error)
        XCTAssertEqual(operations.objectAddCallCount, 3)
        XCTAssertEqual(operations.objectRemoveCallCount, 3)
        XCTAssertEqual(operations.audioUnitAddCallCount, 1)
        XCTAssertEqual(operations.audioUnitRemoveCallCount, 1)
    }

    func testQueuedValidationDoesNotReadCoreAudioAfterStop() throws {
        let operations = FakeCoreAudioInputDeviceObserverOperations()
        let validationQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.blocked-validation"
        )
        let validationBlocked = DispatchSemaphore(value: 0)
        let releaseValidation = DispatchSemaphore(value: 0)
        let observer = makeObserver(
            operations: operations,
            validationQueue: validationQueue
        )

        try observer.start()
        validationQueue.async {
            validationBlocked.signal()
            releaseValidation.wait()
        }
        XCTAssertEqual(validationBlocked.wait(timeout: .now() + 2), .success)

        operations.emitObjectChange(
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        )
        observer.stop()
        releaseValidation.signal()
        validationQueue.sync {}

        XCTAssertEqual(operations.bindingCallCount, 1)
    }

    func testStopWaitsForInFlightDeliveryToComplete() throws {
        let operations = FakeCoreAudioInputDeviceObserverOperations(
            bindingResults: [true, false]
        )
        let validationQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.in-flight-validation"
        )
        let deliveryQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.in-flight-delivery"
        )
        let callbackEntered = DispatchSemaphore(value: 0)
        let allowCallbackReturn = DispatchSemaphore(value: 0)
        let stopAttempted = DispatchSemaphore(value: 0)
        let stopFinished = DispatchSemaphore(value: 0)
        let observer = makeObserver(
            operations: operations,
            validationQueue: validationQueue,
            deliveryQueue: deliveryQueue
        ) {
            callbackEntered.signal()
            allowCallbackReturn.wait()
        }

        try observer.start()
        operations.emitAudioUnitChange(
            audioUnit: fakeAudioUnit,
            propertyID: kAudioOutputUnitProperty_CurrentDevice,
            scope: kAudioUnitScope_Global,
            element: 0
        )
        XCTAssertEqual(
            callbackEntered.wait(timeout: .now() + 2),
            .success
        )

        DispatchQueue.global().async {
            stopAttempted.signal()
            observer.stop()
            stopFinished.signal()
        }
        XCTAssertEqual(
            stopAttempted.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(
            stopFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )

        allowCallbackReturn.signal()
        XCTAssertEqual(
            stopFinished.wait(timeout: .now() + 2),
            .success
        )
    }

    func testLateAudioUnitCallbackAfterFailedRemovalCannotReachReleasedState()
        throws
    {
        let operations = FakeCoreAudioInputDeviceObserverOperations(
            audioUnitRemoveStatus: OSStatus(-1),
            bindingResults: [true, false]
        )
        let validationQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.late-validation"
        )
        let deliveryQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.late-delivery"
        )
        let changeCount = LockedCounter()
        var observer: CoreAudioInputDeviceObserver? = makeObserver(
            operations: operations,
            validationQueue: validationQueue,
            deliveryQueue: deliveryQueue
        ) {
            changeCount.increment()
        }

        try observer?.start()
        observer?.stop()
        observer = nil

        operations.emitRemovedAudioUnitChange(
            audioUnit: fakeAudioUnit,
            propertyID: kAudioOutputUnitProperty_CurrentDevice,
            scope: kAudioUnitScope_Global,
            element: 0
        )
        flush(validationQueue, deliveryQueue)

        XCTAssertEqual(operations.bindingCallCount, 1)
        XCTAssertEqual(changeCount.value, 0)
    }

    func testStartAfterStopFailsWithoutRegisteringListeners() {
        let operations = FakeCoreAudioInputDeviceObserverOperations()
        let observer = makeObserver(operations: operations)

        observer.stop()

        XCTAssertThrowsError(try observer.start())
        XCTAssertEqual(operations.objectAddCallCount, 0)
        XCTAssertEqual(operations.audioUnitAddCallCount, 0)
    }

    private var fakeAudioUnit: AudioUnit {
        AudioUnit(bitPattern: 1)!
    }

    private func makeObserver(
        operations: FakeCoreAudioInputDeviceObserverOperations,
        validationQueue: DispatchQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.default-validation"
        ),
        deliveryQueue: DispatchQueue = DispatchQueue(
            label: "CoreAudioInputDeviceObserverTests.default-delivery"
        ),
        onChange: @escaping @Sendable () -> Void = {}
    ) -> CoreAudioInputDeviceObserver {
        CoreAudioInputDeviceObserver(
            deviceID: deviceID,
            expectedUID: expectedUID,
            audioUnit: fakeAudioUnit,
            operations: operations,
            validationQueue: validationQueue,
            deliveryQueue: deliveryQueue,
            onChange: onChange
        )
    }

    private func flush(_ queues: DispatchQueue...) {
        for queue in queues {
            queue.sync {}
        }
    }
}

private final class FakeCoreAudioInputDeviceObserverOperations:
    CoreAudioInputDeviceObserverOperations,
    @unchecked Sendable
{
    struct ObjectRegistration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let listener: AudioObjectPropertyListenerBlock
    }

    private struct AudioUnitRegistration {
        let audioUnit: AudioUnit
        let listener: AudioUnitPropertyListenerProc
        let userData: UnsafeMutableRawPointer
    }

    private let lock = NSLock()
    private var objectAddStatuses: [OSStatus]
    private let audioUnitAddStatus: OSStatus
    private let audioUnitRemoveStatus: OSStatus
    private var bindingResults: [Bool]
    private var objectRegistrations: [ObjectRegistration] = []
    private var audioUnitRegistration: AudioUnitRegistration?
    private var removedAudioUnitRegistration: AudioUnitRegistration?
    private var addedObjectAddresses: [AudioObjectPropertyAddress] = []
    private var removedObjectAddresses: [AudioObjectPropertyAddress] = []
    private var storedAudioUnitAddCallCount = 0
    private var storedAudioUnitRemoveCallCount = 0
    private var storedBindingCallCount = 0
    var onAddObject: ((Int) -> Void)?

    init(
        objectAddStatuses: [OSStatus] = [],
        audioUnitAddStatus: OSStatus = noErr,
        audioUnitRemoveStatus: OSStatus = noErr,
        bindingResults: [Bool] = [true]
    ) {
        self.objectAddStatuses = objectAddStatuses
        self.audioUnitAddStatus = audioUnitAddStatus
        self.audioUnitRemoveStatus = audioUnitRemoveStatus
        self.bindingResults = bindingResults
    }

    var objectAddCallCount: Int {
        lock.withLock { addedObjectAddresses.count }
    }

    var objectRemoveCallCount: Int {
        lock.withLock { removedObjectAddresses.count }
    }

    var audioUnitAddCallCount: Int {
        lock.withLock { storedAudioUnitAddCallCount }
    }

    var audioUnitRemoveCallCount: Int {
        lock.withLock { storedAudioUnitRemoveCallCount }
    }

    var bindingCallCount: Int {
        lock.withLock { storedBindingCallCount }
    }

    var addedObjectSelectors: [AudioObjectPropertySelector] {
        lock.withLock { addedObjectAddresses.map(\.mSelector) }
    }

    var removedObjectSelectors: [AudioObjectPropertySelector] {
        lock.withLock { removedObjectAddresses.map(\.mSelector) }
    }

    func addObjectPropertyListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue _: DispatchQueue,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        let (index, status, hook) = lock.withLock {
            let index = addedObjectAddresses.count
            addedObjectAddresses.append(address)
            let status = objectAddStatuses.isEmpty
                ? noErr
                : objectAddStatuses.removeFirst()
            return (index, status, onAddObject)
        }
        hook?(index)
        if status == noErr {
            lock.withLock {
                objectRegistrations.append(
                    ObjectRegistration(
                        objectID: objectID,
                        address: address,
                        listener: listener
                    )
                )
            }
        }
        return status
    }

    func removeObjectPropertyListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue _: DispatchQueue,
        listener _: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        lock.withLock {
            removedObjectAddresses.append(address)
            if let index = objectRegistrations.firstIndex(where: {
                $0.objectID == objectID
                    && Self.addressesEqual($0.address, address)
            }) {
                objectRegistrations.remove(at: index)
            }
        }
        return noErr
    }

    func addAudioUnitPropertyListener(
        audioUnit: AudioUnit,
        listener: AudioUnitPropertyListenerProc,
        userData: UnsafeMutableRawPointer
    ) -> OSStatus {
        lock.withLock {
            storedAudioUnitAddCallCount += 1
            if audioUnitAddStatus == noErr {
                audioUnitRegistration = AudioUnitRegistration(
                    audioUnit: audioUnit,
                    listener: listener,
                    userData: userData
                )
            }
        }
        return audioUnitAddStatus
    }

    func removeAudioUnitPropertyListener(
        audioUnit _: AudioUnit,
        listener _: AudioUnitPropertyListenerProc,
        userData _: UnsafeMutableRawPointer
    ) -> OSStatus {
        lock.withLock {
            storedAudioUnitRemoveCallCount += 1
            removedAudioUnitRegistration = audioUnitRegistration
            audioUnitRegistration = nil
        }
        return audioUnitRemoveStatus
    }

    func bindingIsValid(
        deviceID _: AudioDeviceID,
        expectedUID _: String,
        audioUnit _: AudioUnit
    ) -> Bool {
        lock.withLock {
            storedBindingCallCount += 1
            if bindingResults.count > 1 {
                return bindingResults.removeFirst()
            }
            return bindingResults.first ?? true
        }
    }

    func emitObjectChange(_ address: AudioObjectPropertyAddress) {
        let listener = lock.withLock {
            objectRegistrations.first?.listener
        }
        var address = address
        withUnsafePointer(to: &address) { pointer in
            listener?(1, pointer)
        }
    }

    func emitAudioUnitChange(
        audioUnit: AudioUnit,
        propertyID: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement
    ) {
        guard let registration = lock.withLock({
            audioUnitRegistration
        }) else {
            return
        }
        registration.listener(
            registration.userData,
            audioUnit,
            propertyID,
            scope,
            element
        )
    }

    func emitRemovedAudioUnitChange(
        audioUnit: AudioUnit,
        propertyID: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement
    ) {
        guard let registration = lock.withLock({
            removedAudioUnitRegistration
        }) else {
            return
        }
        registration.listener(
            registration.userData,
            audioUnit,
            propertyID,
            scope,
            element
        )
    }

    private static func addressesEqual(
        _ lhs: AudioObjectPropertyAddress,
        _ rhs: AudioObjectPropertyAddress
    ) -> Bool {
        lhs.mSelector == rhs.mSelector
            && lhs.mScope == rhs.mScope
            && lhs.mElement == rhs.mElement
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}

private final class LockedResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    var error: Error? {
        lock.withLock {
            guard case let .failure(error) = result else {
                return nil
            }
            return error
        }
    }

    func store(_ result: Result<Void, Error>) {
        lock.withLock {
            self.result = result
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
