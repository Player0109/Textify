import TextifyRuntime
import XCTest

final class ReadinessSnapshotTests: XCTestCase {
    func testCanDictateWhenThereAreNoBlockers() {
        let snapshot = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .granted,
                accessibility: .granted,
                inputMonitoring: .granted
            ),
            model: .ready(modelID: "ggml-small.en-q5_1"),
            blockers: []
        )

        XCTAssertTrue(snapshot.canDictate)
    }

    func testCannotDictateWhenThereAreBlockers() {
        let snapshot = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .denied,
                accessibility: .granted,
                inputMonitoring: .granted
            ),
            model: .ready(modelID: "ggml-small.en-q5_1"),
            blockers: [.microphonePermissionDenied]
        )

        XCTAssertFalse(snapshot.canDictate)
    }
}
