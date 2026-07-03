import TextifyHotkeys
import XCTest

final class TriggerEventMapperTests: XCTestCase {
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
}
