import TextifyAudio
import XCTest

final class EdgeSilenceTrimmerTests: XCTestCase {
    func testTrimsOnlyEdgesAndKeepsSafetyPad() {
        let leadingSilence = Array(repeating: Float(0.0), count: 300)
        let firstSpeech = Array(repeating: Float(0.1), count: 200)
        let middleSilence = Array(repeating: Float(0.0), count: 200)
        let secondSpeech = Array(repeating: Float(0.1), count: 200)
        let trailingSilence = Array(repeating: Float(0.0), count: 300)
        let buffer = CanonicalAudioBuffer(
            sampleRate: 1_000,
            channelCount: 1,
            samples: leadingSilence + firstSpeech + middleSilence + secondSpeech + trailingSilence
        )

        let trimmed = EdgeSilenceTrimmer().trim(buffer)

        XCTAssertEqual(trimmed.sampleRate, 1_000)
        XCTAssertEqual(trimmed.channelCount, 1)
        XCTAssertEqual(trimmed.samples.count, 900)
        XCTAssertEqual(trimmed.samples[350], 0.0)
    }

    func testFullSilenceReturnsEmptyBuffer() {
        let buffer = CanonicalAudioBuffer(
            sampleRate: 1_000,
            channelCount: 1,
            samples: Array(repeating: Float(0.0), count: 500)
        )

        let trimmed = EdgeSilenceTrimmer().trim(buffer)

        XCTAssertTrue(trimmed.samples.isEmpty)
    }
}
