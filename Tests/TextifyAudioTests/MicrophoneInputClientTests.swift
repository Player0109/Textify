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

    func testExplicitInputInvalidationFinishesStreamAndTearsDown() async throws {
        let engine = FakeAudioEngineClient()
        let client = MicrophoneInputClient.system(
            inputDevices: { [] },
            makeEngine: { engine }
        )
        let stream = client.levelStream(
            for: .device(deviceUID: "fixture-device-uid")
        )
        let consumer = Task { () -> LiveAudioRecorderError? in
            do {
                for try await _ in stream {}
                return nil
            } catch let error as LiveAudioRecorderError {
                return error
            } catch {
                return .engineStartFailed
            }
        }

        try await waitUntilLevelStream {
            engine.started && engine.tapInstalled
        }
        engine.emitInputChange()

        let error = await consumer.value
        XCTAssertEqual(error, .selectedInputUnavailable)
        try await waitUntilLevelStream {
            engine.stopped
                && !engine.tapInstalled
                && engine.resetCallCount == 1
        }
        XCTAssertEqual(
            Array(engine.callOrder.suffix(3)),
            [.removeTap, .stop, .reset]
        )
    }

    func testInputInvalidationDuringSelectionCannotStartCapture() async {
        let engine = SelectionInvalidatingAudioEngineClient()
        let client = MicrophoneInputClient.system(
            inputDevices: { [] },
            makeEngine: { engine }
        )
        let stream = client.levelStream(
            for: .device(deviceUID: "fixture-device-uid")
        )

        do {
            for try await _ in stream {}
            XCTFail("Expected selected input to become unavailable")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .selectedInputUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(engine.selectInputCallCount, 1)
        XCTAssertEqual(engine.installTapCallCount, 0)
        XCTAssertEqual(engine.startCallCount, 0)
        XCTAssertEqual(engine.removeTapCallCount, 1)
        XCTAssertEqual(engine.stopCallCount, 1)
        XCTAssertEqual(engine.resetCallCount, 1)
        XCTAssertFalse(engine.hasInputChangeHandler)
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

private final class SelectionInvalidatingAudioEngineClient:
    AudioEngineClient,
    AudioInputChangeObserving,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var state = State()

    var hasInputChangeHandler: Bool {
        withLock { state.inputChangeHandler != nil }
    }

    var selectInputCallCount: Int {
        withLock { state.selectInputCallCount }
    }

    var installTapCallCount: Int {
        withLock { state.installTapCallCount }
    }

    var startCallCount: Int {
        withLock { state.startCallCount }
    }

    var removeTapCallCount: Int {
        withLock { state.removeTapCallCount }
    }

    var stopCallCount: Int {
        withLock { state.stopCallCount }
    }

    var resetCallCount: Int {
        withLock { state.resetCallCount }
    }

    func selectInput(_: LiveAudioInput) throws {
        let handler = withLock {
            state.selectInputCallCount += 1
            return state.inputChangeHandler
        }
        handler?()
    }

    func installTap(
        _: @escaping @Sendable (
            AVAudioPCMBuffer,
            AVAudioTime
        ) -> Void
    ) throws {
        withLock {
            state.installTapCallCount += 1
        }
    }

    func start() throws {
        withLock {
            state.startCallCount += 1
        }
    }

    func removeTap() {
        withLock {
            state.removeTapCallCount += 1
        }
    }

    func stop() {
        withLock {
            state.stopCallCount += 1
        }
    }

    func reset() {
        withLock {
            state.resetCallCount += 1
        }
    }

    func setInputChangeHandler(
        _ handler: (@Sendable () -> Void)?
    ) {
        withLock {
            state.inputChangeHandler = handler
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private struct State {
        var inputChangeHandler: (@Sendable () -> Void)?
        var selectInputCallCount = 0
        var installTapCallCount = 0
        var startCallCount = 0
        var removeTapCallCount = 0
        var stopCallCount = 0
        var resetCallCount = 0
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
