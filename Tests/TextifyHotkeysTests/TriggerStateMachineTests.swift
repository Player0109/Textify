import XCTest
import TextifyHotkeys

final class TriggerStateMachineTests: XCTestCase {
    func testDefaultTriggerIsRightCommand() {
        XCTAssertEqual(TriggerPreference.defaultTrigger, .rightCommand)

        let machine = TriggerStateMachine()

        XCTAssertEqual(machine.trigger, .rightCommand)
    }

    func testAllCuratedTriggersCanStartActivation() {
        for trigger in TriggerPreference.allCases {
            var machine = TriggerStateMachine(trigger: trigger)

            XCTAssertEqual(machine.handle(.triggerDown(timestampMs: 0)), .startActivationTimer(delayMs: 250))
        }
    }

    func testRightCommandHoldActivatesAfterThreshold() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        XCTAssertEqual(machine.handle(.triggerDown(timestampMs: 0)), .startActivationTimer(delayMs: 250))
        XCTAssertEqual(machine.handle(.timerFired(timestampMs: 250)), .beginRecording)
    }

    func testTriggerReleaseBeforeThresholdDoesNothing() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))

        XCTAssertEqual(machine.handle(.triggerUp(timestampMs: 120)), .none)
        XCTAssertEqual(machine.state, .idle)
    }

    func testNonTriggerKeyBeforeThresholdCancelsAsShortcut() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        XCTAssertEqual(machine.handle(.nonTriggerKeyDown(timestampMs: 120, isModifierOnly: false)), .cancelAsShortcut)
    }

    func testNonTriggerKeyAfterActivationBeforeSpeechCancelsAsShortcut() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.timerFired(timestampMs: 250))

        XCTAssertEqual(machine.handle(.nonTriggerKeyDown(timestampMs: 300, isModifierOnly: false)), .cancelAsShortcut)
        XCTAssertEqual(machine.state, .idle)
    }

    func testModifierOnlyKeyAfterActivationBeforeSpeechDoesNotCancel() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.timerFired(timestampMs: 250))

        XCTAssertEqual(machine.handle(.nonTriggerKeyDown(timestampMs: 300, isModifierOnly: true)), .none)
        XCTAssertEqual(machine.state, .recording(speechDetected: false))
    }

    func testSpeechPreventsShortcutCancellationAndReleaseFinishesRecording() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.timerFired(timestampMs: 250))
        XCTAssertEqual(machine.handle(.speechDetected(timestampMs: 400)), .none)

        XCTAssertEqual(machine.handle(.nonTriggerKeyDown(timestampMs: 500, isModifierOnly: false)), .none)
        XCTAssertEqual(machine.handle(.triggerUp(timestampMs: 900)), .finishRecording)
        XCTAssertEqual(machine.state, .idle)
    }

    func testReleaseWithoutSpeechDiscardsRecording() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.timerFired(timestampMs: 250))

        XCTAssertEqual(machine.handle(.triggerUp(timestampMs: 900)), .discardRecording)
        XCTAssertEqual(machine.state, .idle)
    }

    func testEscapeCancelsRecording() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.timerFired(timestampMs: 250))

        XCTAssertEqual(machine.handle(.escapeKeyDown(timestampMs: 300)), .cancelRecording)
        XCTAssertEqual(machine.state, .idle)
    }
}
