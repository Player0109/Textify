import TextifyHotkeys
import XCTest

final class TriggerTestSessionTests: XCTestCase {
    func testPassesAfterDownActivationAndRelease() async {
        let session = TriggerTestSession()

        _ = await session.ingest(.triggerDown(timestampMs: 0))
        var result = await session.ingest(.timerFired(timestampMs: 250))
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
}
