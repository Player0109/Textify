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

    func start() throws {
        withLock {
            state.started = true
        }
    }

    func stop() {
        withLock {
            state.stopped = true
        }
    }

    func reset() {}

    func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        withLock {
            state.tapInstalled = true
            state.tapHandler = handler
        }
    }

    func removeTap() {
        withLock {
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

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private struct State {
        var started = false
        var stopped = false
        var tapInstalled = false
        var tapHandler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
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
