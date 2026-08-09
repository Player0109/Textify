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

            XCTAssertEqual(machine.handle(.triggerDown(timestampMs: 0)), .beginArmedCapture(delayMs: 250))
        }
    }

    func testRightCommandHoldActivatesAfterThreshold() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        XCTAssertEqual(machine.handle(.triggerDown(timestampMs: 0)), .beginArmedCapture(delayMs: 250))
        XCTAssertEqual(machine.handle(.timerFired(timestampMs: 250)), .activateRecording)
    }

    func testTriggerReleaseBeforeThresholdDiscardsArmedCapture() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))

        XCTAssertEqual(machine.handle(.triggerUp(timestampMs: 120)), .discardRecording)
        XCTAssertEqual(machine.state, .idle)
    }

    func testTriggerReleaseAtThresholdFinishesWhenTimerDeliveryIsLate() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))

        XCTAssertEqual(
            machine.handle(.triggerUp(timestampMs: 250)),
            .finishRecording
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testEarlyReleaseDiscardsWhenTimerDeliveryArrivesFirst() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.timerFired(timestampMs: 250))

        XCTAssertEqual(
            machine.handle(.triggerUp(timestampMs: 249)),
            .discardRecording
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testNonTriggerKeyBeforeThresholdCancelsAsShortcut() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        XCTAssertEqual(machine.handle(.nonTriggerKeyDown(timestampMs: 120, isModifierOnly: false)), .cancelAsShortcut)
    }

    func testModifierOnlyKeyBeforeThresholdCancelsAsShortcut() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))

        XCTAssertEqual(
            machine.handle(.nonTriggerKeyDown(timestampMs: 120, isModifierOnly: true)),
            .cancelAsShortcut
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testSpeechDuringArmedCaptureLatchesWithoutBypassingThreshold() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))

        XCTAssertEqual(machine.handle(.speechDetected(timestampMs: 100)), .none)
        XCTAssertEqual(
            machine.state,
            .waitingForActivation(
                triggerDownTimestampMs: 0,
                speechDetected: true
            )
        )
        XCTAssertEqual(machine.handle(.timerFired(timestampMs: 250)), .activateRecording)
        XCTAssertEqual(machine.state, .recording(speechDetected: true))
    }

    func testNonTriggerKeyBeforeThresholdCancelsEvenAfterSpeech() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.speechDetected(timestampMs: 100))

        XCTAssertEqual(
            machine.handle(.nonTriggerKeyDown(timestampMs: 120, isModifierOnly: false)),
            .cancelAsShortcut
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testLateTimerDoesNotLetPostThresholdKeyCancelLatchedSpeech() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.speechDetected(timestampMs: 100))

        XCTAssertEqual(
            machine.handle(
                .nonTriggerKeyDown(
                    timestampMs: 260,
                    isModifierOnly: false
                )
            ),
            .activateRecording
        )
        XCTAssertEqual(machine.state, .recording(speechDetected: true))
    }

    func testDelayedPreThresholdKeyStillCancelsAfterTimerDelivery() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.speechDetected(timestampMs: 100))
        _ = machine.handle(.timerFired(timestampMs: 250))

        XCTAssertEqual(
            machine.handle(
                .nonTriggerKeyDown(
                    timestampMs: 249,
                    isModifierOnly: true
                )
            ),
            .cancelAsShortcut
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testReleaseBeforeThresholdDiscardsEvenAfterSpeech() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.speechDetected(timestampMs: 100))

        XCTAssertEqual(machine.handle(.triggerUp(timestampMs: 120)), .discardRecording)
        XCTAssertEqual(machine.state, .idle)
    }

    func testEscapeCancelsArmedCaptureBeforeActivation() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))

        XCTAssertEqual(machine.handle(.escapeKeyDown(timestampMs: 120)), .cancelRecording)
        XCTAssertEqual(machine.state, .idle)
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

    func testReleaseWithoutSpeechFinishesActivatedRecording() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        _ = machine.handle(.timerFired(timestampMs: 250))

        XCTAssertEqual(machine.handle(.triggerUp(timestampMs: 900)), .finishRecording)
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
