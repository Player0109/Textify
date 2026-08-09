import AVFoundation
@testable import TextifyAudio
import XCTest

final class LiveAudioRecorderTests: XCTestCase {
    func testDefaultConfigurationCapsOneSessionAtFiveMinutes() {
        XCTAssertEqual(
            LiveAudioRecordingConfiguration.v1_1Default
                .maximumDurationSeconds,
            300
        )
    }

    func testPostReleaseGraceIsBoundedBySessionDeadline() {
        XCTAssertEqual(
            LiveAudioRecorder.boundedPostReleaseGraceNanoseconds(
                configuredGraceNanoseconds: 250_000_000,
                nowUptimeNanoseconds: 1_000_000_000,
                deadlineUptimeNanoseconds: 1_100_000_000
            ),
            100_000_000
        )
        XCTAssertEqual(
            LiveAudioRecorder.boundedPostReleaseGraceNanoseconds(
                configuredGraceNanoseconds: 250_000_000,
                nowUptimeNanoseconds: 1_100_000_000,
                deadlineUptimeNanoseconds: 1_100_000_000
            ),
            0
        )
    }

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

    func testRoutesExplicitInputBeforeInstallingTapAndStartingEngine() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(permissionClient: permission, engineClient: engine)
        let input = LiveAudioInput.device(deviceUID: "fixture-device-uid")

        try await recorder.startRecording(
            input: input,
            onSpeechDetected: {},
            onMaximumDurationReached: {}
        )

        XCTAssertEqual(engine.selectedInputs, [input])
        XCTAssertEqual(engine.callOrder, [.selectInput, .installTap, .start])
        await recorder.discardRecording()
    }

    func testUnavailableExplicitInputDoesNotInstallTapOrStartEngine() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        engine.selectInputError = LiveAudioRecorderError.selectedInputUnavailable
        let recorder = LiveAudioRecorder(permissionClient: permission, engineClient: engine)

        do {
            try await recorder.startRecording(
                input: .device(deviceUID: "missing-device-uid"),
                onSpeechDetected: {},
                onMaximumDurationReached: {}
            )
            XCTFail("Expected unavailable explicit input to fail")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .selectedInputUnavailable)
        }

        XCTAssertFalse(engine.tapInstalled)
        XCTAssertFalse(engine.started)
        XCTAssertEqual(engine.resetCallCount, 1)
    }

    func testInputInvalidationDuringSelectionFailsBeforeTapOrStart() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        engine.onSelectInput = {
            engine.emitInputChange()
        }
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            engineClient: engine
        )

        do {
            try await recorder.startRecording(
                input: .device(deviceUID: "fixture-device-uid"),
                onSpeechDetected: {},
                onMaximumDurationReached: {}
            )
            XCTFail("Expected input invalidation during selection")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .deviceChangedDuringRecording)
        }

        XCTAssertEqual(engine.installTapCallCount, 0)
        XCTAssertEqual(engine.startCallCount, 0)
        XCTAssertFalse(engine.tapInstalled)
        XCTAssertTrue(engine.stopped)
        XCTAssertEqual(engine.resetCallCount, 1)
        XCTAssertFalse(engine.hasInputChangeHandler)
        XCTAssertEqual(
            engine.callOrder,
            [.selectInput, .removeTap, .stop, .reset]
        )

        engine.onSelectInput = nil
        try await recorder.startRecording(
            onSpeechDetected: {},
            onMaximumDurationReached: {}
        )
        try engine.emit(
            samples: Array(repeating: 0.1, count: 160),
            sampleRate: 16_000
        )
        let nextAudio = try await recorder.finishRecording()
        XCTAssertEqual(nextAudio.samples.count, 160)
        XCTAssertEqualSamples(
            nextAudio.samples,
            Array(repeating: 0.1, count: 160)
        )
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

    func testRetainedCanonicalAudioCannotExceedRequestedDuration() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(
                maximumDurationSeconds: 10,
                postReleaseGraceMilliseconds: 0
            ),
            engineClient: engine
        )
        let maximumDurationReached = expectation(
            description: "canonical sample budget reached"
        )

        try await recorder.startRecording(
            maximumDurationSeconds: 10,
            onSpeechDetected: {},
            onMaximumDurationReached: {
                maximumDurationReached.fulfill()
            }
        )
        try engine.emit(
            samples: Array(repeating: 0.1, count: 176_000),
            sampleRate: 16_000
        )
        await fulfillment(of: [maximumDurationReached], timeout: 1)

        let audio = try await recorder.finishRecording()

        XCTAssertEqual(audio.samples.count, 160_000)
        XCTAssertEqual(audio.durationSeconds, 10)
    }

    func testCaptureMilestonesFireOnceInOrderWithAbsoluteHostTimestamp() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let milestones = CaptureMilestoneLog()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(
                postReleaseGraceMilliseconds: 0
            ),
            engineClient: engine
        )
        let firstSampleHostTime = AVAudioTime.hostTime(forSeconds: 4_321.25)
        engine.onStart = {
            milestones.append("engine_start")
            try? engine.emit(
                samples: Array(repeating: 0.1, count: 320),
                sampleRate: 16_000,
                audioTime: AVAudioTime(hostTime: firstSampleHostTime)
            )
        }

        try await recorder.startRecording(
            onCaptureStarted: {
                milestones.append("capture_started")
            },
            onFirstAudio: { firstSampleUptimeMilliseconds in
                milestones.append("first_audio_\(firstSampleUptimeMilliseconds)")
            },
            onSpeechDetected: {},
            onMaximumDurationReached: {}
        )
        try engine.emit(
            samples: Array(repeating: 0.2, count: 320),
            sampleRate: 16_000,
            audioTime: AVAudioTime(
                hostTime: AVAudioTime.hostTime(forSeconds: 5_000)
            )
        )

        let audio = try await recorder.finishRecording()

        XCTAssertEqual(
            milestones.values,
            ["engine_start", "capture_started", "first_audio_4321250"]
        )
        XCTAssertEqual(audio.samples.count, 640)
    }

    func testFirstAudioFallsBackToTapUptimeMinusCanonicalDuration() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let milestones = CaptureMilestoneLog()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(
                postReleaseGraceMilliseconds: 0
            ),
            engineClient: engine
        )

        try await recorder.startRecording(
            onFirstAudio: { firstSampleUptimeMilliseconds in
                milestones.append("\(firstSampleUptimeMilliseconds)")
            },
            onSpeechDetected: {},
            onMaximumDurationReached: {}
        )

        let beforeTapMilliseconds = Int(
            DispatchTime.now().uptimeNanoseconds / 1_000_000
        )
        try engine.emit(
            samples: Array(repeating: 0.1, count: 320),
            sampleRate: 16_000
        )
        let afterTapMilliseconds = Int(
            DispatchTime.now().uptimeNanoseconds / 1_000_000
        )
        _ = try await recorder.finishRecording()

        let firstSampleUptimeMilliseconds = try XCTUnwrap(
            milestones.values.first.flatMap(Int.init)
        )
        XCTAssertGreaterThanOrEqual(
            firstSampleUptimeMilliseconds,
            beforeTapMilliseconds - 20
        )
        XCTAssertLessThanOrEqual(
            firstSampleUptimeMilliseconds,
            afterTapMilliseconds - 20
        )
    }

    func testFirstAudioCallbackDoesNotExecuteOnTapThread() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let milestones = CaptureMilestoneLog()
        let firstAudio = expectation(description: "first audio")
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(
                postReleaseGraceMilliseconds: 0
            ),
            engineClient: engine
        )

        try await recorder.startRecording(
            onFirstAudio: { _ in
                milestones.append(
                    engine.isExecutingTapOnCurrentThread ? "tap" : "ingestion"
                )
                firstAudio.fulfill()
            },
            onSpeechDetected: {},
            onMaximumDurationReached: {}
        )
        try engine.emit(
            samples: Array(repeating: 0.1, count: 320),
            sampleRate: 16_000
        )

        await fulfillment(of: [firstAudio], timeout: 1)
        await recorder.discardRecording()

        XCTAssertEqual(milestones.values, ["ingestion"])
    }

    func testCaptureMilestonesDoNotFireWhenEngineStartFails() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        engine.startError = .engineStartFailed
        engine.onStart = {
            try? engine.emit(
                samples: Array(repeating: 0.1, count: 320),
                sampleRate: 16_000
            )
        }
        let milestones = CaptureMilestoneLog()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            engineClient: engine
        )

        do {
            try await recorder.startRecording(
                onCaptureStarted: {
                    milestones.append("capture_started")
                },
                onFirstAudio: { firstSampleUptimeMilliseconds in
                    milestones.append("first_audio_\(firstSampleUptimeMilliseconds)")
                },
                onSpeechDetected: {},
                onMaximumDurationReached: {}
            )
            XCTFail("Expected engine start to fail")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .engineStartFailed)
        }

        XCTAssertTrue(milestones.values.isEmpty)
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
        let completionGate = IngestionTaskCompletionGate()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(postReleaseGraceMilliseconds: 0),
            engineClient: engine,
            beforeIngestionTaskCompletion: {
                await completionGate.wait()
            }
        )

        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        try engine.emit(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000)

        let finishTask = Task {
            try await recorder.finishRecording()
        }
        await completionGate.waitUntilEntered()

        var startError: LiveAudioRecorderError?
        do {
            try await recorder.startRecording(
                onSpeechDetected: {},
                onMaximumDurationReached: {}
            )
        } catch let error as LiveAudioRecorderError {
            startError = error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await completionGate.release()
        let audio = try await finishTask.value

        XCTAssertEqual(startError, .alreadyRecording)
        XCTAssertEqual(engine.startCallCount, 1)
        XCTAssertEqual(audio.samples.count, 320)
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
        engine.onStop = {
            try? engine.emitRemovedTap(samples: Array(repeating: 0.9, count: 320), sampleRate: 16_000)
        }

        try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
        try engine.emit(samples: Array(repeating: 0.1, count: 320), sampleRate: 16_000)
        _ = try await recorder.finishRecording()

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

        await fulfillment(of: [maximumDurationReached], timeout: 1)
        XCTAssertFalse(engine.tapInstalled)
        XCTAssertTrue(engine.stopped)
        await recorder.discardRecording()
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
        XCTAssertEqual(audio.samples.count, 160)
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

    func testInputInvalidationStopsAndDiscardsRecordingOnce() async throws {
        let permission = MicrophonePermissionClient(
            status: { .granted },
            requestAccess: { .granted }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(
            permissionClient: permission,
            configuration: LiveAudioRecordingConfiguration(
                postReleaseGraceMilliseconds: 0
            ),
            engineClient: engine
        )
        let recordingError = expectation(
            description: "recording error"
        )
        recordingError.expectedFulfillmentCount = 1

        try await recorder.startRecording(
            input: .device(deviceUID: "fixture-device-uid"),
            onSpeechDetected: {},
            onMaximumDurationReached: {},
            onRecordingError: { error in
                XCTAssertEqual(
                    error,
                    .deviceChangedDuringRecording
                )
                recordingError.fulfill()
            }
        )
        try engine.emit(
            samples: Array(repeating: 0.2, count: 320),
            sampleRate: 16_000
        )

        engine.emitInputChange()
        engine.emitInputChange()

        await fulfillment(of: [recordingError], timeout: 1)
        try await waitUntil { engine.stopped }
        XCTAssertFalse(engine.tapInstalled)

        do {
            _ = try await recorder.finishRecording()
            XCTFail("Expected input invalidation error")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .deviceChangedDuringRecording)
        }

        try await recorder.startRecording(
            onSpeechDetected: {},
            onMaximumDurationReached: {}
        )
        try engine.emit(
            samples: Array(repeating: 0.1, count: 160),
            sampleRate: 16_000
        )
        let nextAudio = try await recorder.finishRecording()
        XCTAssertEqual(nextAudio.samples.count, 160)
    }
}

final class FakeAudioEngineClient:
    AudioEngineClient,
    AudioInputChangeObserving,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var state = State()
    private static let tapThreadMarker =
        "TextifyAudioTests.FakeAudioEngineClient.tap.\(UUID().uuidString)"

    enum Call: Equatable {
        case selectInput
        case installTap
        case start
        case removeTap
        case stop
        case reset
    }

    var started: Bool {
        withLock { state.started }
    }

    var stopped: Bool {
        withLock { state.stopped }
    }

    var tapInstalled: Bool {
        withLock { state.tapInstalled }
    }

    var hasInputChangeHandler: Bool {
        withLock { state.inputChangeHandler != nil }
    }

    var startCallCount: Int {
        withLock { state.startCallCount }
    }

    var installTapCallCount: Int {
        withLock { state.installTapCallCount }
    }

    var resetCallCount: Int {
        withLock { state.resetCallCount }
    }

    var selectedInputs: [LiveAudioInput] {
        withLock { state.selectedInputs }
    }

    var callOrder: [Call] {
        withLock { state.callOrder }
    }

    var isExecutingTapOnCurrentThread: Bool {
        Thread.current.threadDictionary[Self.tapThreadMarker] != nil
    }

    var selectInputError: LiveAudioRecorderError? {
        get {
            withLock { state.selectInputError }
        }
        set {
            withLock {
                state.selectInputError = newValue
            }
        }
    }

    var startError: LiveAudioRecorderError? {
        get {
            withLock { state.startError }
        }
        set {
            withLock {
                state.startError = newValue
            }
        }
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

    var onSelectInput: (@Sendable () -> Void)? {
        get {
            withLock { state.onSelectInput }
        }
        set {
            withLock {
                state.onSelectInput = newValue
            }
        }
    }

    var onStart: (@Sendable () -> Void)? {
        get {
            withLock { state.onStart }
        }
        set {
            withLock {
                state.onStart = newValue
            }
        }
    }

    func start() throws {
        let (hook, startError) = withLock {
            state.startCallCount += 1
            state.callOrder.append(.start)
            if state.startError == nil {
                state.started = true
            }
            return (state.onStart, state.startError)
        }
        hook?()
        if let startError {
            throw startError
        }
    }

    func stop() {
        let hook = withLock {
            state.stopped = true
            state.callOrder.append(.stop)
            return state.onStop
        }
        hook?()
    }

    func reset() {
        withLock {
            state.resetCallCount += 1
            state.callOrder.append(.reset)
        }
    }

    func selectInput(_ input: LiveAudioInput) throws {
        let hook = try withLock {
            state.selectedInputs.append(input)
            state.callOrder.append(.selectInput)
            if let selectInputError = state.selectInputError {
                throw selectInputError
            }
            return state.onSelectInput
        }
        hook?()
    }

    func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        withLock {
            state.tapInstalled = true
            state.tapHandler = handler
            state.installTapCallCount += 1
            state.callOrder.append(.installTap)
        }
    }

    func removeTap() {
        withLock {
            state.removedTapHandler = state.tapHandler
            state.tapInstalled = false
            state.tapHandler = nil
            state.callOrder.append(.removeTap)
        }
    }

    func setInputChangeHandler(
        _ handler: (@Sendable () -> Void)?
    ) {
        withLock {
            state.inputChangeHandler = handler
        }
    }

    func emitInputChange() {
        let handler = withLock { state.inputChangeHandler }
        handler?()
    }

    func emit(
        samples: [Float],
        sampleRate: Double,
        audioTime: AVAudioTime? = nil
    ) throws {
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
        invokeTapHandler(
            handler,
            buffer: buffer,
            audioTime: audioTime
                ?? AVAudioTime(sampleTime: 0, atRate: sampleRate)
        )
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

    private func invokeTapHandler(
        _ handler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?,
        buffer: AVAudioPCMBuffer,
        audioTime: AVAudioTime
    ) {
        Thread.current.threadDictionary[Self.tapThreadMarker] = true
        defer {
            Thread.current.threadDictionary.removeObject(
                forKey: Self.tapThreadMarker
            )
        }
        handler?(buffer, audioTime)
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
        var resetCallCount = 0
        var selectedInputs: [LiveAudioInput] = []
        var selectInputError: LiveAudioRecorderError?
        var startError: LiveAudioRecorderError?
        var callOrder: [Call] = []
        var tapHandler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
        var removedTapHandler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
        var inputChangeHandler: (@Sendable () -> Void)?
        var onStop: (@Sendable () -> Void)?
        var onSelectInput: (@Sendable () -> Void)?
        var onStart: (@Sendable () -> Void)?
    }
}

private final class CaptureMilestoneLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.withLock { storedValues }
    }

    func append(_ value: String) {
        lock.withLock {
            storedValues.append(value)
        }
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

private actor IngestionTaskCompletionGate {
    private var hasEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        hasEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else {
            return
        }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
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
