import TextifyAudio
import XCTest

final class RMSFrameEmitterTests: XCTestCase {
    func testFiresAfterSustainedSpeech() {
        var emitter = RMSFrameEmitter()

        for _ in 0..<4 {
            XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.001, count: 320), sampleRate: 16_000))
        }
        for _ in 0..<5 {
            XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000))
        }

        XCTAssertTrue(emitter.ingest(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000))
    }

    func testReturnsFalseAfterSustainedSpeechAlreadyEmitted() {
        var emitter = RMSFrameEmitter()

        for _ in 0..<4 {
            XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.001, count: 320), sampleRate: 16_000))
        }
        for _ in 0..<5 {
            XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000))
        }
        XCTAssertTrue(emitter.ingest(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000))

        XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000))
    }

    func testIgnoresShortSpike() {
        var emitter = RMSFrameEmitter()

        XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.8, count: 320), sampleRate: 16_000))
    }

    func testStartupGraceDoesNotEmitForInitialLoudFrames() {
        var emitter = RMSFrameEmitter()

        for _ in 0..<4 {
            XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.8, count: 320), sampleRate: 16_000))
        }
    }

    func testRejectsTransientBelowSustainedSpeechWindow() {
        var emitter = RMSFrameEmitter()

        for _ in 0..<4 {
            XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.001, count: 320), sampleRate: 16_000))
        }
        for _ in 0..<5 {
            XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.8, count: 320), sampleRate: 16_000))
        }
    }

    func testDetectsLowSpeechAboveQuietNoiseFloor() {
        var emitter = RMSFrameEmitter()

        for _ in 0..<4 {
            XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.001, count: 320), sampleRate: 16_000))
        }
        for _ in 0..<5 {
            XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.01, count: 320), sampleRate: 16_000))
        }

        XCTAssertTrue(emitter.ingest(samples: Array(repeating: 0.01, count: 320), sampleRate: 16_000))
    }
}
