import XCTest
import TextifyTranscription

final class MockTranscriptionTests: XCTestCase {
    func testMockProviderReturnsQueuedResult() async throws {
        let provider = MockTranscriptionProvider(results: [
            TranscriptionResult(
                text: "hello period",
                noSpeechProbability: 0.01,
                averageLogProbability: -0.1,
                compressionRatio: 1.0
            )
        ])

        let result = try await provider.transcribe(.emptyForTests)

        XCTAssertEqual(result.text, "hello period")
        XCTAssertNil(result.timing)
    }

    func testMockProviderReturnsQueuedResultsInOrder() async throws {
        let provider = MockTranscriptionProvider(results: [
            TranscriptionResult(text: "first", noSpeechProbability: 0.02, averageLogProbability: -0.2, compressionRatio: 1.1),
            TranscriptionResult(text: "second", noSpeechProbability: 0.03, averageLogProbability: -0.3, compressionRatio: 1.2)
        ])

        let first = try await provider.transcribe(.emptyForTests)
        let second = try await provider.transcribe(.emptyForTests)

        XCTAssertEqual(first.text, "first")
        XCTAssertEqual(second.text, "second")
    }

    func testMockProviderThrowsWhenQueueIsEmpty() async {
        let provider = MockTranscriptionProvider(results: [])

        do {
            _ = try await provider.transcribe(.emptyForTests)
            XCTFail("Expected an empty mock queue to throw")
        } catch MockTranscriptionProviderError.noQueuedResult {
            // Expected path.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyAudioBufferForTestsUsesCanonicalShape() {
        let buffer = TranscriptionAudioBuffer.emptyForTests

        XCTAssertEqual(buffer.sampleRate, 16_000)
        XCTAssertEqual(buffer.channelCount, 1)
        XCTAssertTrue(buffer.samples.isEmpty)
    }

    func testWhisperRuntimeStateCarriesModelReadiness() {
        XCTAssertEqual(
            WhisperRuntimeState.ready(modelID: "whisper-base-en-fast"),
            .ready(modelID: "whisper-base-en-fast")
        )
    }
}
