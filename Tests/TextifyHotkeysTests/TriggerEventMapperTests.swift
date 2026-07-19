import AppKit
import TextifyHotkeys
import XCTest

final class TriggerEventMapperTests: XCTestCase {
    func testKeyboardSnapshotCanBeCreatedFromAppKitFlagsChangedEvent() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: .command,
                timestamp: 1.25,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: TriggerKeyMatcher.rightCommandKeyCode
            )
        )

        let snapshot = KeyboardEventSnapshot(event: event)

        XCTAssertEqual(snapshot?.type, .flagsChanged)
        XCTAssertEqual(snapshot?.keyCode, TriggerKeyMatcher.rightCommandKeyCode)
        XCTAssertEqual(snapshot?.flags, TriggerKeyMatcher.commandFlagMask)
        XCTAssertEqual(snapshot?.timestampMs, 1_250)
        XCTAssertEqual(snapshot?.isAutoRepeat, false)
    }

    func testRightCommandDownMapsToTriggerDown() {
        var mapper = TriggerEventMapper(trigger: .rightCommand)
        let event = KeyboardEventSnapshot(
            type: .flagsChanged,
            keyCode: TriggerKeyMatcher.rightCommandKeyCode,
            flags: TriggerKeyMatcher.commandFlagMask,
            timestampMs: 100,
            isAutoRepeat: false
        )

        XCTAssertEqual(mapper.map(event), .triggerDown(timestampMs: 100))
    }

    func testLeftCommandIsIgnored() {
        var mapper = TriggerEventMapper(trigger: .rightCommand)
        let event = KeyboardEventSnapshot(
            type: .flagsChanged,
            keyCode: TriggerKeyMatcher.leftCommandKeyCode,
            flags: TriggerKeyMatcher.commandFlagMask,
            timestampMs: 100,
            isAutoRepeat: false
        )

        XCTAssertNil(mapper.map(event))
    }

    func testRightCommandReleaseIsDetectedWhenLeftCommandRemainsHeld() {
        var mapper = TriggerEventMapper(trigger: .rightCommand)

        XCTAssertEqual(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .flagsChanged,
                    keyCode: TriggerKeyMatcher.rightCommandKeyCode,
                    flags: TriggerKeyMatcher.commandFlagMask,
                    timestampMs: 100,
                    isAutoRepeat: false
                )
            ),
            .triggerDown(timestampMs: 100)
        )
        XCTAssertNil(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .flagsChanged,
                    keyCode: TriggerKeyMatcher.leftCommandKeyCode,
                    flags: TriggerKeyMatcher.commandFlagMask,
                    timestampMs: 120,
                    isAutoRepeat: false
                )
            )
        )
        XCTAssertEqual(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .flagsChanged,
                    keyCode: TriggerKeyMatcher.rightCommandKeyCode,
                    flags: TriggerKeyMatcher.commandFlagMask,
                    timestampMs: 140,
                    isAutoRepeat: false
                )
            ),
            .triggerUp(timestampMs: 140)
        )
        XCTAssertNil(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .flagsChanged,
                    keyCode: TriggerKeyMatcher.leftCommandKeyCode,
                    flags: 0,
                    timestampMs: 160,
                    isAutoRepeat: false
                )
            )
        )
    }

    func testRightOptionMapsDownAndUp() {
        assertModifierTrigger(
            .rightOption,
            keyCode: TriggerKeyMatcher.rightOptionKeyCode,
            flagMask: TriggerKeyMatcher.optionFlagMask
        )
    }

    func testRightControlMapsDownAndUp() {
        assertModifierTrigger(
            .rightControl,
            keyCode: TriggerKeyMatcher.rightControlKeyCode,
            flagMask: TriggerKeyMatcher.controlFlagMask
        )
    }

    func testControlSpaceMapsKeyDownAndKeyUp() {
        var mapper = TriggerEventMapper(trigger: .controlSpace)

        XCTAssertEqual(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .keyDown,
                    keyCode: TriggerKeyMatcher.spaceKeyCode,
                    flags: TriggerKeyMatcher.controlFlagMask,
                    timestampMs: 100,
                    isAutoRepeat: false
                )
            ),
            .triggerDown(timestampMs: 100)
        )
        XCTAssertNil(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .keyDown,
                    keyCode: TriggerKeyMatcher.spaceKeyCode,
                    flags: TriggerKeyMatcher.controlFlagMask,
                    timestampMs: 110,
                    isAutoRepeat: true
                )
            )
        )
        XCTAssertEqual(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .keyUp,
                    keyCode: TriggerKeyMatcher.spaceKeyCode,
                    flags: TriggerKeyMatcher.controlFlagMask,
                    timestampMs: 140,
                    isAutoRepeat: false
                )
            ),
            .triggerUp(timestampMs: 140)
        )
    }

    func testControlSpaceEndsWhenControlIsReleasedFirst() {
        var mapper = TriggerEventMapper(trigger: .controlSpace)
        _ = mapper.map(
            KeyboardEventSnapshot(
                type: .keyDown,
                keyCode: TriggerKeyMatcher.spaceKeyCode,
                flags: TriggerKeyMatcher.controlFlagMask,
                timestampMs: 100,
                isAutoRepeat: false
            )
        )

        XCTAssertEqual(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .flagsChanged,
                    keyCode: TriggerKeyMatcher.leftControlKeyCode,
                    flags: 0,
                    timestampMs: 120,
                    isAutoRepeat: false
                )
            ),
            .triggerUp(timestampMs: 120)
        )
    }

    private func assertModifierTrigger(
        _ trigger: TriggerPreference,
        keyCode: UInt16,
        flagMask: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var mapper = TriggerEventMapper(trigger: trigger)
        XCTAssertEqual(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .flagsChanged,
                    keyCode: keyCode,
                    flags: flagMask,
                    timestampMs: 100,
                    isAutoRepeat: false
                )
            ),
            .triggerDown(timestampMs: 100),
            file: file,
            line: line
        )
        XCTAssertEqual(
            mapper.map(
                KeyboardEventSnapshot(
                    type: .flagsChanged,
                    keyCode: keyCode,
                    flags: 0,
                    timestampMs: 140,
                    isAutoRepeat: false
                )
            ),
            .triggerUp(timestampMs: 140),
            file: file,
            line: line
        )
    }
}
