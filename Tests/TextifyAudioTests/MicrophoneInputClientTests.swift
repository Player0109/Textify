import AVFoundation
@testable import TextifyAudio
import XCTest

final class MicrophoneInputClientTests: XCTestCase {
    func testClosureBackedClientListsCurrentDevices() throws {
        let expected = [
            MicrophoneDevice(id: "uid-b", displayName: "Studio Mic"),
            MicrophoneDevice(id: "uid-a", displayName: "Built-in Mic")
        ]
        let client = MicrophoneInputClient(
            inputDevices: { expected },
            levelStream: { _ in
                AsyncThrowingStream<Float, Error> { continuation in
                    continuation.finish()
                }
            }
        )

        XCTAssertEqual(try client.inputDevices(), expected)
    }

    func testSystemLevelStreamBuffersOnlyNewestScalar() async throws {
        let engine = FakeAudioEngineClient()
        let client = MicrophoneInputClient.system(
            inputDevices: { [] },
            makeEngine: { engine }
        )
        let stream = client.levelStream(
            for: .device(deviceUID: "fixture-device-uid")
        )

        try engine.emit(
            samples: Array(repeating: 0.001, count: 320),
            sampleRate: 16_000
        )
        try engine.emit(
            samples: Array(repeating: 0.8, count: 320),
            sampleRate: 16_000
        )

        var iterator = stream.makeAsyncIterator()
        let newestLevel = try await iterator.next()
        XCTAssertNotNil(newestLevel)
        XCTAssertGreaterThan(newestLevel ?? 0, 0.9)
    }

    func testUnavailableExplicitInputFinishesLevelStreamWithSpecificError() async {
        let engine = FakeAudioEngineClient()
        engine.selectInputError = .selectedInputUnavailable
        let client = MicrophoneInputClient.system(
            inputDevices: { [] },
            makeEngine: { engine }
        )
        let stream = client.levelStream(
            for: .device(deviceUID: "missing-device-uid")
        )

        do {
            for try await _ in stream {}
            XCTFail("Expected selected input to be unavailable")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .selectedInputUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            engine.selectedInputs,
            [.device(deviceUID: "missing-device-uid")]
        )
        XCTAssertFalse(engine.tapInstalled)
        XCTAssertFalse(engine.started)
        XCTAssertEqual(engine.resetCallCount, 1)
    }

    func testCancellingLevelStreamRemovesTapStopsAndResetsEngine() async throws {
        let engine = FakeAudioEngineClient()
        let client = MicrophoneInputClient.system(
            inputDevices: { [] },
            makeEngine: { engine }
        )
        let stream = client.levelStream(for: .systemDefault)
        let consumer = Task {
            for try await _ in stream {}
        }

        try await waitUntilLevelStream {
            engine.started && engine.tapInstalled
        }
        consumer.cancel()
        _ = await consumer.result
        try await waitUntilLevelStream {
            engine.stopped && !engine.tapInstalled && engine.resetCallCount == 1
        }
        XCTAssertEqual(
            Array(engine.callOrder.suffix(3)),
            [.removeTap, .stop, .reset]
        )
    }
}

private func waitUntilLevelStream(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @Sendable () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for level-stream condition")
}
