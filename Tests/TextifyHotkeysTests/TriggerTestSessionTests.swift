import TextifyHotkeys
import XCTest

final class TriggerTestSessionTests: XCTestCase {
    func testPassesAfterDownActivationAndRelease() async {
        let session = TriggerTestSession()

        var result = await session.ingest(.triggerDown(timestampMs: 0))
        XCTAssertFalse(result.sawBeginRecording)

        result = await session.ingest(.timerFired(timestampMs: 250))
        XCTAssertFalse(result.passed)

        result = await session.ingest(.triggerUp(timestampMs: 400))

        XCTAssertTrue(result.sawDown)
        XCTAssertTrue(result.sawBeginRecording)
        XCTAssertTrue(result.sawUp)
        XCTAssertTrue(result.passed)
    }

    func testTapDoesNotPassWithoutActivation() async {
        let session = TriggerTestSession()

        _ = await session.ingest(.triggerDown(timestampMs: 0))
        let result = await session.ingest(.triggerUp(timestampMs: 100))

        XCTAssertTrue(result.sawDown)
        XCTAssertFalse(result.sawBeginRecording)
        XCTAssertTrue(result.sawUp)
        XCTAssertFalse(result.passed)
    }

    func testPassesWhenReleaseCrossesThresholdBeforeTimerDelivery() async {
        let session = TriggerTestSession()

        _ = await session.ingest(.triggerDown(timestampMs: 0))
        let result = await session.ingest(.triggerUp(timestampMs: 250))

        XCTAssertTrue(result.sawDown)
        XCTAssertTrue(result.sawBeginRecording)
        XCTAssertTrue(result.sawUp)
        XCTAssertTrue(result.passed)
    }

    func testReleaseBeforeDownCannotSatisfyMatchingRelease() async {
        let session = TriggerTestSession()

        _ = await session.ingest(.triggerUp(timestampMs: 0))
        _ = await session.ingest(.triggerDown(timestampMs: 100))
        var result = await session.ingest(.timerFired(timestampMs: 350))

        XCTAssertTrue(result.sawDown)
        XCTAssertTrue(result.sawBeginRecording)
        XCTAssertTrue(result.sawUp)
        XCTAssertFalse(result.passed)

        result = await session.ingest(.triggerUp(timestampMs: 400))
        XCTAssertTrue(result.passed)
    }

    func testPriorTapCannotSatisfyLaterHoldsMatchingRelease() async {
        let session = TriggerTestSession()

        _ = await session.ingest(.triggerDown(timestampMs: 0))
        _ = await session.ingest(.triggerUp(timestampMs: 100))
        _ = await session.ingest(.triggerDown(timestampMs: 200))
        var result = await session.ingest(.timerFired(timestampMs: 450))

        XCTAssertTrue(result.sawDown)
        XCTAssertTrue(result.sawBeginRecording)
        XCTAssertTrue(result.sawUp)
        XCTAssertFalse(result.passed)

        result = await session.ingest(.triggerUp(timestampMs: 500))
        XCTAssertTrue(result.passed)
    }

    func testEscapeDuringRecognizedHoldPreventsPassing() async {
        let session = TriggerTestSession()

        _ = await session.ingest(.triggerDown(timestampMs: 0))
        _ = await session.ingest(.timerFired(timestampMs: 250))
        var result = await session.ingest(.escapeKeyDown(timestampMs: 300))
        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(result.passed)

        result = await session.ingest(.triggerUp(timestampMs: 400))

        XCTAssertTrue(result.sawDown)
        XCTAssertTrue(result.sawBeginRecording)
        XCTAssertTrue(result.sawUp)
        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(result.passed)
    }

    func testExtraKeyAfterRecognizedHoldDoesNotFailTriggerTest() async {
        let session = TriggerTestSession()

        _ = await session.ingest(.triggerDown(timestampMs: 0))
        _ = await session.ingest(.timerFired(timestampMs: 250))
        var result = await session.ingest(.nonTriggerKeyDown(timestampMs: 300, isModifierOnly: false))
        XCTAssertFalse(result.wasCancelled)
        XCTAssertFalse(result.passed)

        result = await session.ingest(.triggerUp(timestampMs: 400))

        XCTAssertTrue(result.sawDown)
        XCTAssertTrue(result.sawBeginRecording)
        XCTAssertTrue(result.sawUp)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertTrue(result.passed)
    }
}
