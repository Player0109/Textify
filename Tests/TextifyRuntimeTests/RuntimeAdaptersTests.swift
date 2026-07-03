import Foundation
import TextifyAudio
import TextifyCore
import TextifyDiagnostics
import TextifyHotkeys
import TextifyInsertion
import TextifyModels
import TextifyRuntime
import TextifySettings
import TextifyTranscription
import XCTest

final class RuntimeAdaptersTests: XCTestCase {
    func testSettingsAdapterLoadsAndSavesPreferences() async {
        let store = SettingsStore(storage: .memory)
        let adapter = RuntimeSettingsStoreAdapter(store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = "ggml-small.en-q5_1"

        await adapter.savePreferences(preferences)
        let loaded = await adapter.loadPreferences()

        XCTAssertEqual(loaded.activeModelID, "ggml-small.en-q5_1")
    }

    func testDiagnosticsAdapterWritesEvents() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = DiagnosticsLogger(directory: directory)
        let adapter = RuntimeDiagnosticsLoggerAdapter(logger: logger)

        await adapter.log(.appStarted(appVersion: "1.0.0", macOSVersion: "14.0"))

        let data = try Data(contentsOf: logger.logFileURL)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""event":"app_started""#))
    }

    func testAudioAdapterRejectsExplicitMicrophoneSelection() async throws {
        let adapter = RuntimeAudioRecorderAdapter(recorder: LiveAudioRecorder())

        do {
            try await adapter.startRecording(
                microphone: .device(deviceUID: "missing", lastSeenDisplayName: "Missing"),
                onSpeechDetected: {}
            )
            XCTFail("Expected explicit microphone selection to be rejected")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .unsupportedInput)
        }
    }

    func testWhisperAdapterReportsMissingModelAfterFailedPrepare() async throws {
        let runtime = WhisperRuntime()
        let adapter = WhisperRuntimeTranscribingAdapter(runtime: runtime)
        let model = RuntimeActiveModel(
            id: "ggml-small.en-q5_1",
            displayName: "Balanced - Whisper small.en",
            tier: "balanced",
            localModelPath: "/tmp/textify-missing-model.bin",
            useGPU: true,
            threadCount: 1
        )

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected missing model prepare to fail")
        } catch {
            let readiness = await adapter.readiness
            XCTAssertEqual(readiness, .failed(modelID: model.id, reason: .missingFile))
        }
    }

    func testPostProcessingAdapterUsesV1Pipeline() async {
        let adapter = RuntimePostProcessingAdapter()

        let output = await adapter.process(
            rawText: "hello comma this is textify period",
            preferences: .defaults
        )

        XCTAssertEqual(output, "Hello, this is textify.")
    }

    func testModelResolverReturnsInstalledActiveModelAndReadiness() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let modelURL = directory.appendingPathComponent("ggml-small.en-q5_1.bin")
        try Data("model".utf8).write(to: modelURL)
        let model = Self.modelEntry(filename: modelURL.lastPathComponent)
        let store = InstalledModelsStore(records: [
            InstalledModelRecord(
                model: model,
                installedAt: "2026-07-03T00:00:00Z",
                localFilesByManifestFilename: [modelURL.lastPathComponent: modelURL.path]
            )
        ])
        let resolver = RuntimeModelResolverAdapter(
            layout: ModelStorageLayout(rootDirectory: directory),
            loadStore: { store }
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertEqual(activeModel?.id, model.id)
        XCTAssertEqual(activeModel?.localModelPath, modelURL.path)
        let readiness = await resolver.readiness(for: activeModel)
        XCTAssertEqual(readiness, .ready(modelID: model.id))
    }

    func testModelResolverDoesNotResolveModelOutsideInstalledStore() async {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = RuntimeModelResolverAdapter(
            layout: ModelStorageLayout(rootDirectory: directory),
            loadStore: { InstalledModelsStore() }
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = "arbitrary-local-model"

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertNil(activeModel)
        let readiness = await resolver.readiness(for: activeModel)
        XCTAssertEqual(readiness, .noActiveModel)
    }

    func testPermissionAdapterMapsDomainClients() async {
        let adapter = SystemRuntimePermissionAdapter(
            microphone: MicrophonePermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            inputMonitoring: InputMonitoringPermissionClient(
                status: { .denied },
                requestAccess: { .denied }
            ),
            accessibility: AccessibilityTrustClient(status: { .notTrusted })
        )

        let snapshot = await adapter.permissionSnapshot()

        XCTAssertEqual(snapshot.microphone, .granted)
        XCTAssertEqual(snapshot.accessibility, .denied)
        XCTAssertEqual(snapshot.inputMonitoring, .denied)
    }

    func testSystemRuntimeClockReturnsMillisecondsAndSleepsForNonNegativeDurations() async {
        let clock = SystemRuntimeClock()

        XCTAssertGreaterThan(clock.nowMilliseconds(), 0)
        await clock.sleep(milliseconds: -10)
        await clock.sleep(milliseconds: 0)
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyRuntimeTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func modelEntry(filename: String) -> ModelEntry {
        ModelEntry(
            id: "ggml-small.en-q5_1",
            displayName: "Balanced - Whisper small.en",
            tier: "balanced",
            description: "Balanced local English dictation.",
            sizeBytes: 5,
            files: [
                ModelFile(
                    filename: filename,
                    url: "https://github.com/Player0109/Textify/releases/download/models-v1/\(filename)",
                    sha256: "abc",
                    sizeBytes: 5
                )
            ],
            licenses: [],
            provenance: ModelProvenance(
                sourceName: "ggerganov/whisper.cpp",
                sourceUrl: "https://huggingface.co/ggerganov/whisper.cpp",
                sourceRevision: "fixture",
                sourceFile: filename,
                originalModelName: "OpenAI Whisper small.en",
                originalModelUrl: "https://huggingface.co/openai/whisper-small.en",
                mirroredBy: "Textify",
                mirroredAt: "2026-07-03"
            ),
            runtimeParameters: RuntimeParameters(
                language: "en",
                detectLanguage: false,
                translate: false,
                strategy: "greedy",
                beamSize: 1,
                bestOf: 1,
                temperature: 0,
                temperatureFallback: [],
                noContext: true,
                tokenTimestamps: false,
                maxAudioSeconds: 60
            ),
            hallucinationThresholds: HallucinationThresholds(
                noSpeechProbabilityMax: 0.60,
                avgLogProbabilityMin: -1.00,
                compressionRatioMax: 2.40
            ),
            minAppVersion: "0.1.0"
        )
    }
}
