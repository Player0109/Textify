import TextifyRuntime
import XCTest

final class ReadinessTests: XCTestCase {
    func testReadySnapshotHasNoBlockers() {
        let snapshot = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .granted,
                accessibility: .granted,
                inputMonitoring: .granted
            ),
            model: .ready(modelID: "ggml-small.en-q5_1")
        )

        XCTAssertTrue(snapshot.canDictate)
        XCTAssertEqual(snapshot.blockers, [])
    }

    func testPermissionAndModelStatesBecomeBlockers() {
        let snapshot = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .denied,
                accessibility: .denied,
                inputMonitoring: .denied
            ),
            model: .missing(modelID: "ggml-small.en-q5_1")
        )

        XCTAssertFalse(snapshot.canDictate)
        XCTAssertEqual(
            snapshot.blockers,
            [
                .microphonePermissionDenied,
                .accessibilityPermissionDenied,
                .inputMonitoringPermissionDenied,
                .activeModelMissing(modelID: "ggml-small.en-q5_1")
            ]
        )
    }

    func testLoadingAndWarmingModelsHaveNoBlockers() {
        let loading = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .granted,
                accessibility: .granted,
                inputMonitoring: .granted
            ),
            model: .loading(modelID: "ggml-small.en-q5_1")
        )
        let warming = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .granted,
                accessibility: .granted,
                inputMonitoring: .granted
            ),
            model: .warming(modelID: "ggml-small.en-q5_1")
        )

        XCTAssertTrue(loading.canDictate)
        XCTAssertEqual(loading.blockers, [])

        XCTAssertTrue(warming.canDictate)
        XCTAssertEqual(warming.blockers, [])
    }
}
