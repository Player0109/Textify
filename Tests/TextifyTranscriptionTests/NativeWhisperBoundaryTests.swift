import XCTest
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
}
