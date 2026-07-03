import Foundation
import TextifyAudio
import TextifyDiagnostics
import TextifyHotkeys
import TextifyInsertion
import TextifySettings
import TextifyTranscription
@testable import TextifyRuntime
import XCTest

@MainActor
final class AppDictationServiceTests: XCTestCase {
    func testBeginRecordingRefreshesReadinessBeforeStartingAudio() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)

        let snapshotCount = await fakes.permissions.snapshotCount()
        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(service.status, .recording(speechDetected: false))
    }

    func testReadinessBlockerPreventsAudioStart() async {
        let fakes = RuntimeFakes.blocked(blocker: .microphonePermissionDenied)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)

        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(service.status, .blocked(.readinessBlocked(.microphonePermissionDenied)))
    }

    func testCancellationDuringTranscriptionPreventsLateInsertion() async {
        let fakes = RuntimeFakes.ready(transcript: "late text")
        await fakes.transcriber.setSuspendUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let task = Task { await service.handleTriggerAction(.finishRecording) }
        await waitUntil { await fakes.transcriber.isSuspended() }

        await service.cancelActiveSession(reason: .escapeKey)
        await fakes.transcriber.release()
        await task.value

        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
        XCTAssertEqual(service.status, .cancelled(.escapeKey))
    }

    func testActivationTimerTokenIgnoresStaleTimerAfterCancellationAndRestart() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        _ = await service.handleTriggerEvent(.triggerDown(timestampMs: 0))
        await waitUntil { fakes.clock.sleepCount() == 1 }
        await service.cancelActiveSession(reason: .escapeKey)
        _ = await service.handleTriggerEvent(.triggerUp(timestampMs: 10))

        _ = await service.handleTriggerEvent(.triggerDown(timestampMs: 20))
        await waitUntil { fakes.clock.sleepCount() == 2 }

        if fakes.clock.sleepCount() > 0 {
            fakes.clock.fireOldestSleep(nowMilliseconds: 250)
        }
        await settle()
        let startCountAfterStaleTimer = await fakes.audio.startCount()
        XCTAssertEqual(startCountAfterStaleTimer, 0)

        if fakes.clock.sleepCount() > 0 {
            fakes.clock.fireOldestSleep(nowMilliseconds: 270)
        }
        await waitUntil { await fakes.audio.startCount() == 1 }
        XCTAssertEqual(service.status, .recording(speechDetected: false))
    }

    func testSpeechDetectedCallbackUpdatesStatusOnlyForActiveSession() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.cancelActiveSession(reason: .escapeKey)
        await service.handleTriggerAction(.beginRecording)

        await fakes.audio.emitSpeech(callbackIndex: 0)
        await settle()
        XCTAssertEqual(service.status, .recording(speechDetected: false))

        await fakes.audio.emitSpeech(callbackIndex: 1)
        await settle()
        XCTAssertEqual(service.status, .recording(speechDetected: true))
    }

    func testFinishWithEmptyAudioCancelsNoSpeechDetected() async {
        let fakes = RuntimeFakes.ready(audio: CanonicalAudioBuffer(samples: []))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .cancelled(.noSpeechDetected))
        let insertedTexts = await fakes.inserter.insertedTexts()
        let transcribeCount = await fakes.transcriber.transcribeCount()
        XCTAssertEqual(insertedTexts, [])
        XCTAssertEqual(transcribeCount, 0)
    }

    func testNoActiveModelAfterAudioFinishBlocksWithoutInsertion() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await fakes.models.setActiveModel(nil)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .blocked(.readinessBlocked(.noActiveModel)))
        let insertedTexts = await fakes.inserter.insertedTexts()
        let transcribeCount = await fakes.transcriber.transcribeCount()
        XCTAssertEqual(insertedTexts, [])
        XCTAssertEqual(transcribeCount, 0)
    }

    func testSuccessfulFinishPreparesTranscribesPostProcessesInsertsAndCompletesWithLengthBucket() async {
        let processed = String(repeating: "a", count: 51)
        let fakes = RuntimeFakes.ready(transcript: "raw transcript", processedText: processed)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        let prepareCount = await fakes.transcriber.prepareCount()
        let transcribeCount = await fakes.transcriber.transcribeCount()
        let processedRawTexts = await fakes.postProcessor.processedRawTexts()
        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(transcribeCount, 1)
        XCTAssertEqual(processedRawTexts, ["raw transcript"])
        XCTAssertEqual(insertedTexts, [processed])
        XCTAssertEqual(service.status, .completed(textLengthBucket: "51-200"))
    }

    func testEmptyProcessedTextDoesNotInsertAndReturnsIdle() async {
        let fakes = RuntimeFakes.ready(transcript: "raw transcript", processedText: " \n ")
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
        XCTAssertEqual(service.status, .idle)
    }

    func testInsertionFailureMapsToFailedInsertionFailed() async {
        let fakes = RuntimeFakes.ready(processedText: "insert me")
        await fakes.inserter.setOutcome(.notInserted(.pasteEventFailed))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .failed(.insertionFailed))
    }

    func testAudioFinishFailureMapsToFailedAudioFinishFailed() async {
        let fakes = RuntimeFakes.ready()
        await fakes.audio.setFinishError(LiveAudioRecorderError.engineStartFailed)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .failed(.audioFinishFailed))
        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
    }

    func testAudioEmptyRecordingErrorMapsToCancelledNoSpeechDetected() async {
        let fakes = RuntimeFakes.ready()
        await fakes.audio.setFinishError(LiveAudioRecorderError.emptyRecording)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .cancelled(.noSpeechDetected))
        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
    }

    func testTranscriptionFailureMapsToFailedTranscriptionFailed() async {
        let fakes = RuntimeFakes.ready()
        await fakes.transcriber.setTranscribeError(WhisperRuntimeError.transcriptionFailed("fixture"))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .failed(.transcriptionFailed))
        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
    }

    private func settle() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await condition() {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}

private struct RuntimeFakes {
    let settings: FakeRuntimeSettings
    let permissions: FakeRuntimePermissions
    let models: FakeRuntimeModels
    let audio: FakeRuntimeAudio
    let transcriber: FakeRuntimeTranscriber
    let inserter: FakeInsertionService
    let diagnostics: FakeRuntimeDiagnostics
    let postProcessor: FakeRuntimePostProcessor
    let clock: FakeRuntimeClock

    var dependencies: RuntimeDependencies {
        RuntimeDependencies(
            settings: settings,
            permissions: permissions,
            models: models,
            audio: audio,
            transcriber: transcriber,
            inserter: inserter,
            diagnostics: diagnostics,
            postProcessor: postProcessor,
            clock: clock
        )
    }

    static func ready(
        audio: CanonicalAudioBuffer = CanonicalAudioBuffer(samples: [0.1, 0.2, 0.3]),
        transcript: String = "hello period",
        processedText: String? = nil
    ) -> RuntimeFakes {
        RuntimeFakes(
            settings: FakeRuntimeSettings(preferences: .defaults),
            permissions: FakeRuntimePermissions(
                snapshot: RuntimePermissionSnapshot(
                    microphone: .granted,
                    accessibility: .granted,
                    inputMonitoring: .granted
                )
            ),
            models: FakeRuntimeModels(activeModel: .fixture),
            audio: FakeRuntimeAudio(audio: audio),
            transcriber: FakeRuntimeTranscriber(transcript: transcript),
            inserter: FakeInsertionService(),
            diagnostics: FakeRuntimeDiagnostics(),
            postProcessor: FakeRuntimePostProcessor(processedText: processedText),
            clock: FakeRuntimeClock()
        )
    }

    static func blocked(blocker: ReadinessBlocker) -> RuntimeFakes {
        switch blocker {
        case .microphonePermissionDenied:
            return fixture(
                snapshot: RuntimePermissionSnapshot(
                    microphone: .denied,
                    accessibility: .granted,
                    inputMonitoring: .granted
                )
            )
        case .accessibilityPermissionDenied:
            return fixture(
                snapshot: RuntimePermissionSnapshot(
                    microphone: .granted,
                    accessibility: .denied,
                    inputMonitoring: .granted
                )
            )
        case .inputMonitoringPermissionDenied:
            return fixture(
                snapshot: RuntimePermissionSnapshot(
                    microphone: .granted,
                    accessibility: .granted,
                    inputMonitoring: .denied
                )
            )
        case .noActiveModel:
            return fixture(activeModel: nil, readiness: .noActiveModel)
        case let .activeModelMissing(modelID):
            return fixture(activeModel: .fixture, readiness: .missing(modelID: modelID))
        case let .activeModelNotReady(modelID):
            return fixture(activeModel: .fixture, readiness: .loading(modelID: modelID))
        case let .transcriptionRuntimeFailed(modelID):
            return fixture(activeModel: .fixture, readiness: .failed(modelID: modelID, reason: .loadFailed))
        }
    }

    private static func fixture(
        snapshot: RuntimePermissionSnapshot = RuntimePermissionSnapshot(
            microphone: .granted,
            accessibility: .granted,
            inputMonitoring: .granted
        ),
        activeModel: RuntimeActiveModel? = .fixture,
        readiness: RuntimeModelReadiness? = nil
    ) -> RuntimeFakes {
        RuntimeFakes(
            settings: FakeRuntimeSettings(preferences: .defaults),
            permissions: FakeRuntimePermissions(snapshot: snapshot),
            models: FakeRuntimeModels(activeModel: activeModel, readiness: readiness),
            audio: FakeRuntimeAudio(audio: CanonicalAudioBuffer(samples: [0.1, 0.2, 0.3])),
            transcriber: FakeRuntimeTranscriber(transcript: "hello period"),
            inserter: FakeInsertionService(),
            diagnostics: FakeRuntimeDiagnostics(),
            postProcessor: FakeRuntimePostProcessor(processedText: nil),
            clock: FakeRuntimeClock()
        )
    }
}

private actor FakeRuntimeSettings: RuntimeSettingsProviding {
    private var preferences: AppPreferences

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    func loadPreferences() async -> AppPreferences {
        return preferences
    }

    func savePreferences(_ preferences: AppPreferences) async {
        self.preferences = preferences
    }
}

private actor FakeRuntimePermissions: RuntimePermissionChecking {
    private var snapshot: RuntimePermissionSnapshot
    private var snapshotCountValue = 0

    func snapshotCount() -> Int {
        snapshotCountValue
    }

    init(snapshot: RuntimePermissionSnapshot) {
        self.snapshot = snapshot
    }

    func permissionSnapshot() async -> RuntimePermissionSnapshot {
        snapshotCountValue += 1
        return snapshot
    }

}

private actor FakeRuntimeModels: RuntimeModelResolving {
    private var activeModel: RuntimeActiveModel?
    private var readinessOverride: RuntimeModelReadiness?

    init(activeModel: RuntimeActiveModel?, readiness: RuntimeModelReadiness? = nil) {
        self.activeModel = activeModel
        self.readinessOverride = readiness
    }

    func resolveActiveModel(preferences: AppPreferences) async -> RuntimeActiveModel? {
        activeModel
    }

    func readiness(for model: RuntimeActiveModel?) async -> RuntimeModelReadiness {
        if let readinessOverride {
            return readinessOverride
        }
        guard let model else {
            return .noActiveModel
        }
        return .ready(modelID: model.id)
    }

    func setActiveModel(_ activeModel: RuntimeActiveModel?) {
        self.activeModel = activeModel
        readinessOverride = nil
    }

}

private actor FakeRuntimeAudio: RuntimeAudioRecording {
    private var audio: CanonicalAudioBuffer
    private var finishError: Error?
    private var callbacks: [@Sendable () -> Void] = []
    private var startCountValue = 0

    func startCount() -> Int {
        startCountValue
    }

    init(audio: CanonicalAudioBuffer) {
        self.audio = audio
    }

    func startRecording(
        microphone: MicrophoneSelection,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) async throws {
        startCountValue += 1
        callbacks.append(onSpeechDetected)
    }

    func finishRecording() async throws -> CanonicalAudioBuffer {
        if let finishError {
            throw finishError
        }
        return audio
    }

    func discardRecording() async {
    }

    func setFinishError(_ error: Error?) {
        finishError = error
    }

    func emitSpeech(callbackIndex: Int) {
        guard callbacks.indices.contains(callbackIndex) else {
            return
        }
        callbacks[callbackIndex]()
    }
}

private actor FakeRuntimeTranscriber: RuntimeTranscribing {
    private let transcript: String
    private var readinessValue: RuntimeModelReadiness
    private var prepareCountValue = 0
    private var transcribeCountValue = 0
    private var transcribeError: Error?
    private var suspendUntilReleased = false
    private var suspensionContinuation: CheckedContinuation<Void, Never>?

    var readiness: RuntimeModelReadiness {
        get async {
            readinessValue
        }
    }

    func prepareCount() -> Int {
        prepareCountValue
    }

    func transcribeCount() -> Int {
        transcribeCountValue
    }

    func isSuspended() -> Bool {
        suspensionContinuation != nil
    }

    init(transcript: String) {
        self.transcript = transcript
        self.readinessValue = .ready(modelID: RuntimeActiveModel.fixture.id)
    }

    func prepare(model: RuntimeActiveModel) async throws {
        prepareCountValue += 1
        readinessValue = .ready(modelID: model.id)
    }

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        transcribeCountValue += 1
        if suspendUntilReleased {
            await withCheckedContinuation { continuation in
                suspensionContinuation = continuation
            }
        }
        if let transcribeError {
            throw transcribeError
        }
        return TranscriptionResult(
            text: transcript,
            noSpeechProbability: 0.01,
            averageLogProbability: -0.1,
            compressionRatio: 1.0
        )
    }

    func setSuspendUntilReleased(_ suspendUntilReleased: Bool) {
        self.suspendUntilReleased = suspendUntilReleased
    }

    func setTranscribeError(_ error: Error?) {
        self.transcribeError = error
    }

    func release() {
        let continuation = suspensionContinuation
        suspensionContinuation = nil
        continuation?.resume()
    }
}

private actor FakeInsertionService: InsertionService {
    private var outcome: InsertionOutcome = .pasted(
        PasteInsertionReport(pasteboardRestored: true, pasteboardRestoreFailed: false)
    )
    private var insertedTextsValue: [String] = []

    func insertedTexts() -> [String] {
        insertedTextsValue
    }

    func insert(_ request: InsertionRequest) async -> InsertionOutcome {
        insertedTextsValue.append(request.text)
        return outcome
    }

    func setOutcome(_ outcome: InsertionOutcome) {
        self.outcome = outcome
    }
}

private actor FakeRuntimeDiagnostics: RuntimeDiagnosticsLogging {
    func log(_ event: DiagnosticEvent) async {
    }
}

private actor FakeRuntimePostProcessor: RuntimePostProcessing {
    private let processedText: String?
    private var processedRawTextsValue: [String] = []

    func processedRawTexts() -> [String] {
        processedRawTextsValue
    }

    init(processedText: String?) {
        self.processedText = processedText
    }

    func process(rawText: String, preferences: AppPreferences) async -> String {
        processedRawTextsValue.append(rawText)
        return processedText ?? rawText
    }
}

private final class FakeRuntimeClock: RuntimeClock, @unchecked Sendable {
    private struct SleepRequest {
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var nowMillisecondsValue = 0
    private var sleeps: [SleepRequest] = []

    func nowMilliseconds() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return nowMillisecondsValue
    }

    func sleep(milliseconds: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            sleeps.append(SleepRequest(continuation: continuation))
            lock.unlock()
        }
    }

    func sleepCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sleeps.count
    }

    func fireOldestSleep(nowMilliseconds: Int) {
        lock.lock()
        nowMillisecondsValue = nowMilliseconds
        let request = sleeps.removeFirst()
        lock.unlock()
        request.continuation.resume()
    }
}

private extension RuntimeActiveModel {
    static let fixture = RuntimeActiveModel(
        id: "ggml-small.en-q5_1",
        displayName: "Balanced - Whisper small.en",
        tier: "balanced",
        localModelPath: "/tmp/ggml-small.en-q5_1.bin",
        useGPU: true,
        threadCount: 1
    )
}
