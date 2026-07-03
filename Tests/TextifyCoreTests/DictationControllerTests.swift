import TextifyCore
import XCTest

final class DictationControllerTests: XCTestCase {
    func testTapBeforeThresholdDoesNothing() async {
        let controller = DictationController.fakingEverything()

        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.triggerUp(timestampMs: 120))

        let state = await controller.state
        let insertedTexts = await controller.fakeInsertion.insertedTexts
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(insertedTexts, [])
    }

    func testShortcutBeforeActivationCancelsHold() async {
        let controller = DictationController.fakingEverything()

        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.nonTriggerKeyDown(timestampMs: 100, isModifierOnly: false))
        await controller.handle(.activationThresholdPassed(timestampMs: 250))
        await controller.handle(.triggerUp(timestampMs: 350))

        let state = await controller.state
        let startedRecordingCount = await controller.fakeAudio.startedRecordingCount
        let insertedTexts = await controller.fakeInsertion.insertedTexts
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(startedRecordingCount, 0)
        XCTAssertEqual(insertedTexts, [])
    }

    func testShortcutAfterActivationBeforeSpeechCancels() async {
        let controller = DictationController.fakingEverything()

        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.activationThresholdPassed(timestampMs: 250))
        await controller.handle(.nonTriggerKeyDown(timestampMs: 300, isModifierOnly: false))
        await controller.handle(.triggerUp(timestampMs: 350))

        let state = await controller.state
        let discardedRecordingCount = await controller.fakeAudio.discardedRecordingCount
        let insertedTexts = await controller.fakeInsertion.insertedTexts
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(discardedRecordingCount, 1)
        XCTAssertEqual(insertedTexts, [])
    }

    func testEscapeCancelsRecordingBeforeSpeech() async {
        let controller = DictationController.fakingEverything()

        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.activationThresholdPassed(timestampMs: 250))
        await controller.handle(.escapeKeyDown(timestampMs: 300))
        await controller.handle(.triggerUp(timestampMs: 350))

        let state = await controller.state
        let discardedRecordingCount = await controller.fakeAudio.discardedRecordingCount
        let insertedTexts = await controller.fakeInsertion.insertedTexts
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(discardedRecordingCount, 1)
        XCTAssertEqual(insertedTexts, [])
    }

    func testEscapeCancelsRecordingAfterSpeech() async {
        let controller = DictationController.fakingEverything(transcript: "hello period")

        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.activationThresholdPassed(timestampMs: 250))
        await controller.handle(.speechDetected(timestampMs: 400))
        await controller.handle(.escapeKeyDown(timestampMs: 500))
        await controller.handle(.triggerUp(timestampMs: 900))

        let state = await controller.state
        let discardedRecordingCount = await controller.fakeAudio.discardedRecordingCount
        let insertedTexts = await controller.fakeInsertion.insertedTexts
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(discardedRecordingCount, 1)
        XCTAssertEqual(insertedTexts, [])
    }

    func testSpeechThenReleaseTranscribesAndInserts() async {
        let controller = DictationController.fakingEverything(transcript: "hello period")

        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.activationThresholdPassed(timestampMs: 250))
        await controller.handle(.speechDetected(timestampMs: 400))
        await controller.handle(.triggerUp(timestampMs: 900))

        let state = await controller.state
        let finishedRecordingCount = await controller.fakeAudio.finishedRecordingCount
        let insertedTexts = await controller.fakeInsertion.insertedTexts
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(finishedRecordingCount, 1)
        XCTAssertEqual(insertedTexts, ["hello period"])
    }

    func testReleaseWithNoSpeechSilentlyNoOps() async {
        let controller = DictationController.fakingEverything(transcript: "ignored")

        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.activationThresholdPassed(timestampMs: 250))
        await controller.handle(.triggerUp(timestampMs: 900))

        let state = await controller.state
        let discardedRecordingCount = await controller.fakeAudio.discardedRecordingCount
        let transcriptionCount = await controller.fakeTranscriber.transcriptionCount
        let insertedTexts = await controller.fakeInsertion.insertedTexts
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(discardedRecordingCount, 1)
        XCTAssertEqual(transcriptionCount, 0)
        XCTAssertEqual(insertedTexts, [])
    }

    func testBusyTriggerIsIgnored() async {
        let controller = DictationController.fakingEverything(transcript: "first")

        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.activationThresholdPassed(timestampMs: 250))
        await controller.handle(.speechDetected(timestampMs: 400))
        await controller.handle(.triggerDown(timestampMs: 500))
        await controller.handle(.triggerUp(timestampMs: 900))

        let state = await controller.state
        let startedRecordingCount = await controller.fakeAudio.startedRecordingCount
        let insertedTexts = await controller.fakeInsertion.insertedTexts
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(startedRecordingCount, 1)
        XCTAssertEqual(insertedTexts, ["first"])
    }
}
