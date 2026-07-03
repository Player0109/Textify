import TextifyTranscription
import XCTest

final class WhisperTranscriptionOptionsTests: XCTestCase {
    func testV11EnglishOptionsPinEnglishLocalDictation() {
        let options = WhisperTranscriptionOptions.v1_1English

        XCTAssertEqual(options.language, "en")
        XCTAssertFalse(options.translate)
        XCTAssertEqual(options.temperature, 0)
        XCTAssertTrue(options.temperatureFallback.isEmpty)
        XCTAssertFalse(options.usePreviousContext)
        XCTAssertNil(options.initialPrompt)
    }

    func testTranscriptionResultCanCarryTimingMetrics() {
        let timing = TranscriptionTiming(audioDurationMs: 1200, inferenceDurationMs: 340)
        let result = TranscriptionResult(
            text: "hello",
            noSpeechProbability: 0.01,
            averageLogProbability: -0.1,
            compressionRatio: 1.0,
            timing: timing
        )

        XCTAssertEqual(result.timing, timing)
    }
}
