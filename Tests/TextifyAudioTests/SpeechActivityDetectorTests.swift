import TextifyAudio
import XCTest

final class SpeechActivityDetectorTests: XCTestCase {
    func testSustainedSpeechMarksDetected() {
        var detector = SpeechActivityDetector()
        let quiet = Array(repeating: Float(-60.0), count: 4)
        let speech = Array(repeating: Float(-35.0), count: 6)

        for db in quiet {
            detector.ingest(frameRMSdBFS: db)
        }
        for db in speech {
            detector.ingest(frameRMSdBFS: db)
        }

        XCTAssertTrue(detector.speechDetected)
    }

    func testShortClickDoesNotMarkSpeech() {
        var detector = SpeechActivityDetector()

        detector.ingest(frameRMSdBFS: -20.0)

        XCTAssertFalse(detector.speechDetected)
    }
}
