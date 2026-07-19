import AVFoundation
@testable import TextifyAudio
import XCTest

final class LiveAudioRecorderTests: XCTestCase {
    func testDeniedMicrophonePermissionPreventsEngineStart() async throws {
        let permission = MicrophonePermissionClient(
            status: { .denied },
            requestAccess: { .denied }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(permissionClient: permission, engineClient: engine)

        do {
            try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
            XCTFail("Expected microphone permission denial")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .microphonePermissionDenied)
        }

        XCTAssertFalse(engine.started)
        XCTAssertFalse(engine.tapInstalled)
    }

    func testNotDeterminedPermissionRequestsAccessBeforeStartingEngine() async throws {
        let permission = MicrophonePermissionClient(
            status: { .notDetermined },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(permissionClient: permission, engineClient: engine)

        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})

        XCTAssertTrue(engine.tapInstalled)
        XCTAssertTrue(engine.started)
        await recorder.discardRecording()
    }

    func testConcurrentStartDuringPermissionRequestIsRejected() async throws {
        let permissionGate = PermissionRequestGate()
        let permission = MicrophonePermissionClient(
            status: { .notDetermined },
            requestAccess: { await permissionGate.requestAccess() }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(permissionClient: permission, engineClient: engine)

        let firstStart = Task {
            try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        }
        await permissionGate.waitForRequestCount(1)

        let secondStart = Task {
            try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        await permissionGate.resumeAll(with: .granted)
        try await firstStart.value

        do {
            try await secondStart.value
            XCTFail("Expected overlapping start to be rejected")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .alreadyRecording)
        }

        let permissionRequestCount = await permissionGate.requestCount()
        XCTAssertEqual(permissionRequestCount, 1)
        XCTAssertEqual(engine.startCallCount, 1)
        XCTAssertEqual(engine.installTapCallCount, 1)
        await recorder.discardRecording()
    }

    func testCapturesCanonicalAudioAndEmitsSpeechOnce() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(permissionClient: permission, engineClient: engine)
        let speechDetected = expectation(description: "speech detected")
        speechDetected.expectedFulfillmentCount = 1

        try await recorder.startRecording(
            onSpeechDetected: { speechDetected.fulfill() },
            onMaximumDurationReached: {}
        )

        for _ in 0..<10 {
            try engine.emit(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000)
        }

        await fulfillment(of: [speechDetected], timeout: 1)

        let audio = try await recorder.finishRecording()
        XCTAssertEqual(audio.sampleRate, 16_000)
        XCTAssertEqual(audio.channelCount, 1)
        XCTAssertEqual(audio.samples.count, 3_200)
        XCTAssertFalse(engine.tapInstalled)
        XCTAssertTrue(engine.stopped)
    }

    func testFinishRecordingDrainsOrderedTapBuffersBeforeReturningAudio() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(postReleaseGraceMilliseconds: 0),
            engineClient: engine
        )

        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})

        for chunkIndex in 0..<12 {
            try engine.emit(
                samples: Array(repeating: Float(chunkIndex) / 10.0, count: 320),
                sampleRate: 16_000
            )
        }

        let audio = try await recorder.finishRecording()
        XCTAssertEqual(audio.samples.count, 3_840)

        let chunkAverages = stride(from: 0, to: audio.samples.count, by: 320).map { startIndex in
            let chunk = audio.samples[startIndex..<(startIndex + 320)]
            return chunk.reduce(Float(0), +) / Float(chunk.count)
        }
        XCTAssertEqualSamples(chunkAverages, (0..<12).map { Float($0) / 10.0 })
    }

    func testStartDuringFinishDrainIsRejected() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(postReleaseGraceMilliseconds: 0),
            engineClient: engine
        )
        let reentrantStart = StartAttemptBox()
        engine.onStop = {
            reentrantStart.launch(recorder: recorder)
        }

        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        try engine.emit(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000)

        _ = try await recorder.finishRecording()

        let startDuringFinishOutcome = await reentrantStart.outcome()
        XCTAssertEqual(startDuringFinishOutcome, .failed(.alreadyRecording))
        XCTAssertEqual(engine.startCallCount, 1)
    }

    func testStaleOldSessionIngestionCannotCorruptNextRecording() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(postReleaseGraceMilliseconds: 0),
            engineClient: engine
        )
        let reentrantStart = StartAttemptBox()
        engine.onStop = {
            reentrantStart.launch(recorder: recorder)
            try? engine.emitRemovedTap(samples: Array(repeating: 0.9, count: 320), sampleRate: 16_000)
        }

        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        try engine.emit(samples: Array(repeating: 0.1, count: 320), sampleRate: 16_000)
        _ = try await recorder.finishRecording()

        let staleStartOutcome = await reentrantStart.outcome()
        XCTAssertEqual(staleStartOutcome, .failed(.alreadyRecording))

        engine.onStop = nil
        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        try engine.emit(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000)
        let nextAudio = try await recorder.finishRecording()

        XCTAssertEqual(nextAudio.samples.count, 320)
        XCTAssertEqualSamples(nextAudio.samples, Array(repeating: 0.2, count: 320))
    }

    func testMaximumDurationCallbackFires() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(
                maximumDurationSeconds: 0.01,
                postReleaseGraceMilliseconds: 0
            ),
            engineClient: engine
        )
        let maximumDurationReached = expectation(description: "maximum duration reached")

        try await recorder.startRecording(
            onSpeechDetected: {},
            onMaximumDurationReached: { maximumDurationReached.fulfill() }
        )
        try engine.emit(samples: Array(repeating: 0.1, count: 320), sampleRate: 16_000)

        await fulfillment(of: [maximumDurationReached], timeout: 1)
        XCTAssertFalse(engine.tapInstalled)
        XCTAssertTrue(engine.stopped)

        let audio = try await recorder.finishRecording()
        XCTAssertEqual(audio.samples.count, 320)
    }

    func testPerRecordingMaximumDurationOverridesLongerConfiguredMaximum() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(
                maximumDurationSeconds: 60,
                postReleaseGraceMilliseconds: 0
            ),
            engineClient: engine
        )
        let maximumDurationReached = expectation(description: "model maximum duration reached")

        try await recorder.startRecording(
            maximumDurationSeconds: 0.01,
            onSpeechDetected: {},
            onMaximumDurationReached: { maximumDurationReached.fulfill() }
        )
        try engine.emit(samples: Array(repeating: 0.1, count: 320), sampleRate: 16_000)

        await fulfillment(of: [maximumDurationReached], timeout: 1)
        let audio = try await recorder.finishRecording()
        XCTAssertEqual(audio.samples.count, 320)
    }

    func testFinishRecordingSurfacesConversionErrorDuringPostReleaseGrace() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(postReleaseGraceMilliseconds: 100),
            engineClient: engine
        )

        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        try engine.emit(samples: Array(repeating: 0.1, count: 320), sampleRate: 16_000)

        let finishTask = Task {
            try await recorder.finishRecording()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        try engine.emitInt16(samples: Array(repeating: 1, count: 320), sampleRate: 16_000)

        do {
            _ = try await finishTask.value
            XCTFail("Expected conversion error from post-release grace buffer")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .unsupportedInputFormat)
        }
    }

    func testTerminalConversionErrorBlocksNewStartUntilFinishConsumesIt() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(postReleaseGraceMilliseconds: 0),
            engineClient: engine
        )

        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        try engine.emitInt16(samples: Array(repeating: 1, count: 320), sampleRate: 16_000)
        try await waitUntil { engine.stopped }

        do {
            try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
            XCTFail("Expected terminal error state to block a new start")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .alreadyRecording)
        }

        do {
            _ = try await recorder.finishRecording()
            XCTFail("Expected finish to surface terminal conversion error")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .unsupportedInputFormat)
        }

        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        await recorder.discardRecording()
    }
}

final class FakeAudioEngineClient: AudioEngineClient, @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()

    var started: Bool {
        withLock { state.started }
    }

    var stopped: Bool {
        withLock { state.stopped }
    }

    var tapInstalled: Bool {
        withLock { state.tapInstalled }
    }

    var startCallCount: Int {
        withLock { state.startCallCount }
    }

    var installTapCallCount: Int {
        withLock { state.installTapCallCount }
    }

    var onStop: (@Sendable () -> Void)? {
        get {
            withLock { state.onStop }
        }
        set {
            withLock {
                state.onStop = newValue
            }
        }
    }

    func start() throws {
        withLock {
            state.started = true
            state.startCallCount += 1
        }
    }

    func stop() {
        let hook = withLock {
            state.stopped = true
            return state.onStop
        }
        hook?()
    }

    func reset() {}

    func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        withLock {
            state.tapInstalled = true
            state.tapHandler = handler
            state.installTapCallCount += 1
        }
    }

    func removeTap() {
        withLock {
            state.removedTapHandler = state.tapHandler
            state.tapInstalled = false
            state.tapHandler = nil
        }
    }

    func emit(samples: [Float], sampleRate: Double) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        )
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for frame in samples.indices {
            channelData[0][frame] = samples[frame]
        }

        let handler = withLock { state.tapHandler }
        handler?(buffer, AVAudioTime(sampleTime: 0, atRate: sampleRate))
    }

    func emitRemovedTap(samples: [Float], sampleRate: Double) throws {
        let buffer = try makeFloatBuffer(samples: samples, sampleRate: sampleRate)
        let handler = withLock { state.removedTapHandler }
        handler?(buffer, AVAudioTime(sampleTime: 0, atRate: sampleRate))
    }

    func emitInt16(samples: [Int16], sampleRate: Double) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        )
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = try XCTUnwrap(buffer.int16ChannelData)
        for frame in samples.indices {
            channelData[0][frame] = samples[frame]
        }

        let handler = withLock { state.tapHandler }
        handler?(buffer, AVAudioTime(sampleTime: 0, atRate: sampleRate))
    }

    private func makeFloatBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        )
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for frame in samples.indices {
            channelData[0][frame] = samples[frame]
        }
        return buffer
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private struct State {
        var started = false
        var stopped = false
        var tapInstalled = false
        var startCallCount = 0
        var installTapCallCount = 0
        var tapHandler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
        var removedTapHandler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
        var onStop: (@Sendable () -> Void)?
    }
}

private actor PermissionRequestGate {
    private var continuations: [CheckedContinuation<MicrophonePermissionStatus, Never>] = []
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var totalRequestCount = 0

    func requestAccess() async -> MicrophonePermissionStatus {
        await withCheckedContinuation { continuation in
            totalRequestCount += 1
            continuations.append(continuation)
            resumeReadyWaiters()
        }
    }

    func waitForRequestCount(_ count: Int) async {
        if continuations.count >= count {
            return
        }

        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func requestCount() -> Int {
        totalRequestCount
    }

    func resumeAll(with status: MicrophonePermissionStatus) {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: status)
        }
    }

    private func resumeReadyWaiters() {
        var stillWaiting: [(Int, CheckedContinuation<Void, Never>)] = []
        for waiter in requestWaiters {
            if continuations.count >= waiter.0 {
                waiter.1.resume()
            } else {
                stillWaiting.append(waiter)
            }
        }
        requestWaiters = stillWaiting
    }
}

private enum StartAttemptOutcome: Equatable, Sendable {
    case succeeded
    case failed(LiveAudioRecorderError)
    case failedUnexpectedly
}

private final class StartAttemptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<StartAttemptOutcome, Never>?

    func launch(recorder: LiveAudioRecorder) {
        lock.lock()
        defer { lock.unlock() }

        guard task == nil else {
            return
        }

        task = Task {
            do {
                try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
                return .succeeded
            } catch let error as LiveAudioRecorderError {
                return .failed(error)
            } catch {
                return .failedUnexpectedly
            }
        }
    }

    func outcome() async -> StartAttemptOutcome {
        let task = lock.withLock { self.task }
        return await task?.value ?? .failedUnexpectedly
    }
}

private func waitUntil(
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
    XCTFail("Timed out waiting for condition")
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private func XCTAssertEqualSamples(
    _ actual: [Float],
    _ expected: [Float],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (actualSample, expectedSample) in zip(actual, expected) {
        XCTAssertEqual(actualSample, expectedSample, accuracy: 0.0001, file: file, line: line)
    }
}
