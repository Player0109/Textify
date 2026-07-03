@testable import TextifyHotkeys
import XCTest

@MainActor
final class GlobalHotkeyMonitorTests: XCTestCase {
    func testDeniedInputMonitoringReportsFailureAndDoesNotStartTap() {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .denied },
                requestAccess: { .denied }
            ),
            eventTapClient: tap
        )
        let failures = Recorder<HotkeyMonitorError>()

        let result: Result<Void, HotkeyMonitorError> = monitor.start(
            onEvent: { _ in XCTFail("Denied permission should not emit events") },
            onFailure: { failures.append($0) }
        )

        XCTAssertEqual(result.failureValue, .inputMonitoringDenied)
        XCTAssertEqual(failures.values, [.inputMonitoringDenied])
        XCTAssertEqual(tap.startCount, 0)
    }

    func testUnknownInputMonitoringReportsPermissionRequiredAndDoesNotStartTap() {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .unknown },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )
        let failures = Recorder<HotkeyMonitorError>()

        let result: Result<Void, HotkeyMonitorError> = monitor.start(
            onEvent: { _ in XCTFail("Unknown permission should not emit events") },
            onFailure: { failures.append($0) }
        )

        XCTAssertEqual(result.failureValue, .inputMonitoringPermissionRequired)
        XCTAssertEqual(failures.values, [.inputMonitoringPermissionRequired])
        XCTAssertEqual(tap.startCount, 0)
    }

    func testStartReturnsSuccessWhenTapStarts() {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )
        let failures = Recorder<HotkeyMonitorError>()

        let result: Result<Void, HotkeyMonitorError> = monitor.start(
            onEvent: { _ in },
            onFailure: { failures.append($0) }
        )

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(failures.values, [])
        XCTAssertEqual(tap.startCount, 1)
    }

    func testRightCommandEventsAreMappedFromTapSnapshots() async {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )
        let events = Recorder<TriggerEvent>()

        monitor.start(
            onEvent: { events.append($0) },
            onFailure: { _ in XCTFail("Expected monitor start to succeed") }
        )
        tap.send(
            KeyboardEventSnapshot(
                type: .flagsChanged,
                keyCode: TriggerKeyMatcher.rightCommandKeyCode,
                flags: TriggerKeyMatcher.commandFlagMask,
                timestampMs: 100,
                isAutoRepeat: false
            )
        )
        await Task.yield()

        XCTAssertEqual(events.values, [.triggerDown(timestampMs: 100)])
    }

    func testQueuedCallbackFromStoppedSessionAfterRestartEmitsNothing() async {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )
        let oldEvents = Recorder<TriggerEvent>()
        let newEvents = Recorder<TriggerEvent>()

        monitor.start(
            onEvent: { oldEvents.append($0) },
            onFailure: { _ in XCTFail("Expected first monitor start to succeed") }
        )
        tap.send(
            KeyboardEventSnapshot(
                type: .flagsChanged,
                keyCode: TriggerKeyMatcher.rightCommandKeyCode,
                flags: TriggerKeyMatcher.commandFlagMask,
                timestampMs: 100,
                isAutoRepeat: false
            )
        )
        monitor.stop()
        monitor.start(
            onEvent: { newEvents.append($0) },
            onFailure: { _ in XCTFail("Expected second monitor start to succeed") }
        )
        await Task.yield()

        XCTAssertEqual(oldEvents.values, [])
        XCTAssertEqual(newEvents.values, [])
    }

    func testStopRestartAfterTriggerDownResetsMapperAndUsesNewSessionCallback() async {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )
        let oldEvents = Recorder<TriggerEvent>()
        let newEvents = Recorder<TriggerEvent>()

        monitor.start(
            onEvent: { oldEvents.append($0) },
            onFailure: { _ in XCTFail("Expected first monitor start to succeed") }
        )
        tap.send(
            KeyboardEventSnapshot(
                type: .flagsChanged,
                keyCode: TriggerKeyMatcher.rightCommandKeyCode,
                flags: TriggerKeyMatcher.commandFlagMask,
                timestampMs: 100,
                isAutoRepeat: false
            )
        )
        await Task.yield()
        monitor.stop()

        monitor.start(
            onEvent: { newEvents.append($0) },
            onFailure: { _ in XCTFail("Expected second monitor start to succeed") }
        )
        tap.send(
            KeyboardEventSnapshot(
                type: .flagsChanged,
                keyCode: TriggerKeyMatcher.rightCommandKeyCode,
                flags: TriggerKeyMatcher.commandFlagMask,
                timestampMs: 200,
                isAutoRepeat: false
            )
        )
        await Task.yield()

        XCTAssertEqual(oldEvents.values, [.triggerDown(timestampMs: 100)])
        XCTAssertEqual(newEvents.values, [.triggerDown(timestampMs: 200)])
    }

    func testMappedEventsAreEmittedOnMainThreadAfterTapCallbackHop() async {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )
        let emitted = expectation(description: "mapped event emitted")

        monitor.start(
            onEvent: { _ in
                XCTAssertTrue(Thread.isMainThread)
                emitted.fulfill()
            },
            onFailure: { _ in XCTFail("Expected monitor start to succeed") }
        )
        tap.sendFromBackground(
            KeyboardEventSnapshot(
                type: .flagsChanged,
                keyCode: TriggerKeyMatcher.rightCommandKeyCode,
                flags: TriggerKeyMatcher.commandFlagMask,
                timestampMs: 100,
                isAutoRepeat: false
            )
        )

        await fulfillment(of: [emitted], timeout: 1.0)
    }

    func testAlreadyRunningReportsFailure() {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )
        let failures = Recorder<HotkeyMonitorError>()

        monitor.start(onEvent: { _ in }, onFailure: { failures.append($0) })
        monitor.start(onEvent: { _ in }, onFailure: { failures.append($0) })

        XCTAssertEqual(tap.startCount, 1)
        XCTAssertEqual(failures.values, [.alreadyRunning])
    }

    func testStopStopsStartedTap() {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )

        monitor.start(onEvent: { _ in }, onFailure: { _ in XCTFail("Expected monitor start to succeed") })
        monitor.stop()

        XCTAssertEqual(tap.stopCount, 1)
    }

    func testTimeoutDisabledTapIsReEnabledWithoutFailure() async {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )
        let failures = Recorder<HotkeyMonitorError>()

        monitor.start(onEvent: { _ in }, onFailure: { failures.append($0) })
        tap.send(.tapDisabledByTimeout)
        await Task.yield()

        XCTAssertEqual(tap.setEnabledCalls, [true])
        XCTAssertEqual(failures.values, [])
        XCTAssertEqual(tap.stopCount, 0)
    }

    func testUserInputDisabledTapReportsFailureAndStopsTap() async {
        let tap = FakeCGEventTapClient()
        let monitor = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )
        let failures = Recorder<HotkeyMonitorError>()

        monitor.start(onEvent: { _ in }, onFailure: { failures.append($0) })
        tap.send(.tapDisabledByUserInput)
        await Task.yield()

        XCTAssertEqual(failures.values, [.eventTapDisabledByUserInput])
        XCTAssertEqual(tap.stopCount, 1)
    }

    func testDeinitStopsStartedTap() {
        let tap = FakeCGEventTapClient()
        var monitor: GlobalHotkeyMonitor? = GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: tap
        )

        monitor?.start(onEvent: { _ in }, onFailure: { _ in XCTFail("Expected monitor start to succeed") })
        monitor = nil

        XCTAssertEqual(tap.stopCount, 1)
    }
}

private final class FakeCGEventTapClient: CGEventTapClient, @unchecked Sendable {
    private var handler: (@Sendable (CGEventTapMessage) -> Void)?
    var startCount = 0
    var stopCount = 0
    var setEnabledCalls: [Bool] = []
    var startError: Error?

    func start(handler: @escaping @Sendable (CGEventTapMessage) -> Void) throws -> CGEventTapHandle {
        if let startError {
            throw startError
        }
        startCount += 1
        self.handler = handler
        return CGEventTapHandle()
    }

    func stop(_ handle: CGEventTapHandle) {
        stopCount += 1
    }

    func setEnabled(_ handle: CGEventTapHandle, enabled: Bool) {
        setEnabledCalls.append(enabled)
    }

    func send(_ event: KeyboardEventSnapshot) {
        send(.keyboardEvent(event))
    }

    func send(_ message: CGEventTapMessage) {
        handler?(message)
    }

    func sendFromBackground(_ event: KeyboardEventSnapshot) {
        DispatchQueue.global().async { [handler] in
            handler?(.keyboardEvent(event))
        }
    }
}

private final class Recorder<Value>: @unchecked Sendable {
    private(set) var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }
}

private extension Result where Success == Void {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var failureValue: Failure? {
        if case let .failure(error) = self {
            return error
        }
        return nil
    }
}
