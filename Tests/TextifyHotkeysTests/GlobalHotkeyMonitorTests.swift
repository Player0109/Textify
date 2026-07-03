@testable import TextifyHotkeys
import XCTest

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

        monitor.start(
            onEvent: { _ in XCTFail("Denied permission should not emit events") },
            onFailure: { failures.append($0) }
        )

        XCTAssertEqual(failures.values, [.inputMonitoringDenied])
        XCTAssertEqual(tap.startCount, 0)
    }

    func testRightCommandEventsAreMappedFromTapSnapshots() {
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

        XCTAssertEqual(events.values, [.triggerDown(timestampMs: 100)])
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
}

private final class FakeCGEventTapClient: CGEventTapClient, @unchecked Sendable {
    private var handler: (@Sendable (KeyboardEventSnapshot) -> Void)?
    var startCount = 0
    var stopCount = 0
    var startError: Error?

    func start(handler: @escaping @Sendable (KeyboardEventSnapshot) -> Void) throws -> CGEventTapHandle {
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

    func send(_ event: KeyboardEventSnapshot) {
        handler?(event)
    }
}

private final class Recorder<Value>: @unchecked Sendable {
    private(set) var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }
}
