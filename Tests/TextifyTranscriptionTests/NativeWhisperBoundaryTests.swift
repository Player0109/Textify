import XCTest
import Foundation
import TextifyTranscription
import TextifyWhisperShim

final class NativeWhisperBoundaryTests: XCTestCase {
    func testNativeShimReportsMetalEnabledAndCoreMLDisabled() {
        XCTAssertEqual(textify_whisper_compiled_with_metal(), 1)
        XCTAssertEqual(textify_whisper_compiled_with_coreml(), 0)
    }

    func testNativeShimReportsMissingModelLoadError() {
        let context = textify_whisper_load("/tmp/textify-missing-model.bin", 1, 1)

        XCTAssertNil(context)
        XCTAssertNotNil(textify_whisper_last_error(nil))
        XCTAssertFalse(String(cString: textify_whisper_last_error(nil)).isEmpty)
    }

    func testWhisperRuntimeStartsWithoutLoadedModel() async {
        let runtime = WhisperRuntime()

        let state = await runtime.state

        XCTAssertEqual(state, .noModel)
    }

    func testWhisperRuntimeSnapshotStartsWithoutMetrics() async {
        let runtime = WhisperRuntime()

        let snapshot = await runtime.snapshot()

        XCTAssertEqual(snapshot.state, .noModel)
        XCTAssertEqual(snapshot.metrics, WhisperRuntimeMetrics())
    }

    func testNativeShimRequiresExplicitTranscriptionOptions() {
        let returnCode = textify_whisper_transcribe(
            nil,
            nil,
            0,
            "en",
            0,
            Float(0),
            1,
            nil
        )

        XCTAssertEqual(returnCode, -1)
    }

    func testNativeWhisperVerifiesMetalBackendWhenIntegrationTestsAreEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TEXTIFY_RUN_WHISPER_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set TEXTIFY_RUN_WHISPER_INTEGRATION_TESTS=1 to run the local Metal smoke test.")
        }
        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let modelURL = applicationSupport
            .appendingPathComponent("Textify/Models/installed/ggml-small.en-q5_1", isDirectory: true)
            .appendingPathComponent("ggml-small.en-q5_1.bin")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("The curated Whisper model is not installed.")
        }
        let runtime = WhisperRuntime()

        try await runtime.load(
            modelID: "whisper-metal-integration",
            modelPath: modelURL.path,
            useGPU: true
        )

        let state = await runtime.state
        XCTAssertEqual(state, .ready(modelID: "whisper-metal-integration"))
        await runtime.unload()
    }
}
