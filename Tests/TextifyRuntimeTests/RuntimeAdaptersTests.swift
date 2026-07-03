import CryptoKit
import Foundation
import TextifyAudio
import TextifyCore
import TextifyDiagnostics
import TextifyHotkeys
import TextifyInsertion
import TextifyModels
import TextifySettings
import TextifyTranscription
@testable import TextifyRuntime
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

    func testWhisperAdapterCoalescesConcurrentSameModelPrepare() async throws {
        let runtime = FakeWhisperRuntime(suspendLoad: true)
        let adapter = WhisperRuntimeTranscribingAdapter(runtime: runtime)
        let model = Self.activeModel()

        let firstPrepare = Task {
            try await adapter.prepare(model: model)
        }
        while await runtime.loadCallCount() == 0 {
            await Task.yield()
        }

        let secondPrepare = Task {
            try await adapter.prepare(model: model)
        }
        await Task.yield()

        let loadCallCountWhilePreparing = await runtime.loadCallCount()
        XCTAssertEqual(loadCallCountWhilePreparing, 1)
        await runtime.releaseLoads()

        try await firstPrepare.value
        try await secondPrepare.value
        let finalLoadCallCount = await runtime.loadCallCount()
        XCTAssertEqual(finalLoadCallCount, 1)
    }

    func testWhisperAdapterStartsNewPrepareAfterFailedPrepare() async throws {
        let runtime = FakeWhisperRuntime(loadError: FakeWhisperRuntimeError.loadFailed)
        let adapter = WhisperRuntimeTranscribingAdapter(runtime: runtime)
        let model = Self.activeModel()

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected first prepare to fail")
        } catch FakeWhisperRuntimeError.loadFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await runtime.setLoadError(nil)
        try await adapter.prepare(model: model)

        let loadCallCount = await runtime.loadCallCount()
        XCTAssertEqual(loadCallCount, 2)
    }

    func testWhisperAdapterSkipsLoadWhenSameModelIsAlreadyReady() async throws {
        let model = Self.activeModel()
        let runtime = FakeWhisperRuntime(initialState: .ready(modelID: model.id))
        let adapter = WhisperRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(model: model)

        let loadCallCount = await runtime.loadCallCount()
        XCTAssertEqual(loadCallCount, 0)
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
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let modelURL = try Self.writeCanonicalModelFile(modelData, layout: layout)
        let model = Self.modelEntry(filename: modelURL.lastPathComponent, data: modelData)
        let store = Self.installedStore(model: model, localPath: modelURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertEqual(activeModel?.id, model.id)
        XCTAssertEqual(activeModel?.localModelPath, modelURL.path)
        let readiness = await resolver.readiness(for: activeModel)
        XCTAssertEqual(readiness, .ready(modelID: model.id))
    }

    func testModelResolverIgnoresStoredPathOutsideCanonicalLayout() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let canonicalURL = try layout.installedFileURL(
            modelID: Self.fixtureModelID,
            filename: Self.fixtureFilename
        )
        let model = Self.modelEntry(filename: canonicalURL.lastPathComponent, data: modelData)
        let outsideURL = directory.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).bin")
        let store = Self.installedStore(model: model, localPath: outsideURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertNil(activeModel)
    }

    func testModelResolverReportsMissingWhenCanonicalFileIsAbsent() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let canonicalURL = try layout.installedFileURL(
            modelID: Self.fixtureModelID,
            filename: Self.fixtureFilename
        )
        let model = Self.modelEntry(filename: canonicalURL.lastPathComponent, data: modelData)
        let store = Self.installedStore(model: model, localPath: canonicalURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertEqual(activeModel?.localModelPath, canonicalURL.path)
        let readiness = await resolver.readiness(for: activeModel)
        XCTAssertEqual(readiness, .missing(modelID: model.id))
    }

    func testModelResolverFailsReadinessForSizeMismatch() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let modelURL = try Self.writeCanonicalModelFile(modelData, layout: layout)
        let model = Self.modelEntry(
            filename: modelURL.lastPathComponent,
            data: modelData,
            sizeBytes: Int64(modelData.count + 1)
        )
        let store = Self.installedStore(model: model, localPath: modelURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)
        let readiness = await resolver.readiness(for: activeModel)

        XCTAssertEqual(readiness, .failed(modelID: model.id, reason: .checksumFailed))
    }

    func testModelResolverFailsReadinessForChecksumMismatch() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let modelURL = try Self.writeCanonicalModelFile(modelData, layout: layout)
        let model = Self.modelEntry(
            filename: modelURL.lastPathComponent,
            data: modelData,
            sha256: String(repeating: "0", count: 64)
        )
        let store = Self.installedStore(model: model, localPath: modelURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)
        let readiness = await resolver.readiness(for: activeModel)

        XCTAssertEqual(readiness, .failed(modelID: model.id, reason: .checksumFailed))
    }

    func testModelResolverDoesNotResolveModelOutsideInstalledStore() async {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = Self.modelResolver(
            layout: ModelStorageLayout(rootDirectory: directory),
            store: InstalledModelsStore()
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = "arbitrary-local-model"

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertNil(activeModel)
        let readiness = await resolver.readiness(for: activeModel)
        XCTAssertEqual(readiness, .noActiveModel)
    }

    func testPermissionAdapterMapsDeniedInputMonitoringToUnknown() async {
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
        XCTAssertEqual(snapshot.inputMonitoring, .unknown)
    }

    func testPermissionAdapterMapsUnknownInputMonitoringToUnknown() async {
        let adapter = SystemRuntimePermissionAdapter(
            microphone: MicrophonePermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            inputMonitoring: InputMonitoringPermissionClient(
                status: { .unknown },
                requestAccess: { .denied }
            ),
            accessibility: AccessibilityTrustClient(status: { .trusted })
        )

        let snapshot = await adapter.permissionSnapshot()

        XCTAssertEqual(snapshot.microphone, .granted)
        XCTAssertEqual(snapshot.accessibility, .granted)
        XCTAssertEqual(snapshot.inputMonitoring, .unknown)
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

    private static let fixtureModelID = "ggml-small.en-q5_1"
    private static let fixtureFilename = "ggml-small.en-q5_1.bin"

    private static func activeModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: fixtureModelID,
            displayName: "Balanced - Whisper small.en",
            tier: "balanced",
            localModelPath: "/tmp/textify-model.bin",
            useGPU: true,
            threadCount: 1
        )
    }

    private static func writeCanonicalModelFile(
        _ data: Data,
        layout: ModelStorageLayout,
        filename: String = fixtureFilename
    ) throws -> URL {
        let modelURL = try layout.installedFileURL(modelID: fixtureModelID, filename: filename)
        try FileManager.default.createDirectory(
            at: modelURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: modelURL)
        return modelURL
    }

    private static func installedStore(model: ModelEntry, localPath: String) -> InstalledModelsStore {
        InstalledModelsStore(records: [
            InstalledModelRecord(
                model: model,
                installedAt: "2026-07-03T00:00:00Z",
                localFilesByManifestFilename: [model.files[0].filename: localPath]
            )
        ])
    }

    private static func modelResolver(
        layout: ModelStorageLayout,
        store: InstalledModelsStore
    ) -> RuntimeModelResolverAdapter {
        let fixture = InstalledStoreFixture(store: store)
        return RuntimeModelResolverAdapter(layout: layout) {
            fixture.store
        }
    }

    private static func modelEntry(
        filename: String,
        data: Data,
        sha256: String? = nil,
        sizeBytes: Int64? = nil
    ) -> ModelEntry {
        ModelEntry(
            id: fixtureModelID,
            displayName: "Balanced - Whisper small.en",
            tier: "balanced",
            description: "Balanced local English dictation.",
            sizeBytes: sizeBytes ?? Int64(data.count),
            files: [
                ModelFile(
                    filename: filename,
                    url: "https://github.com/Player0109/Textify/releases/download/models-v1/\(filename)",
                    sha256: sha256 ?? sha256Hex(data),
                    sizeBytes: sizeBytes ?? Int64(data.count)
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

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum FakeWhisperRuntimeError: Error {
    case loadFailed
}

private struct InstalledStoreFixture: @unchecked Sendable {
    let store: InstalledModelsStore
}

private actor FakeWhisperRuntime: WhisperRuntimeLoading {
    private var mutableState: WhisperRuntimeState
    private var mutableLoadError: Error?
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private let suspendLoad: Bool
    private var loadCalls = 0

    init(
        initialState: WhisperRuntimeState = .noModel,
        suspendLoad: Bool = false,
        loadError: Error? = nil
    ) {
        self.mutableState = initialState
        self.suspendLoad = suspendLoad
        self.mutableLoadError = loadError
    }

    var state: WhisperRuntimeState {
        mutableState
    }

    func load(
        modelID: String,
        modelPath: String,
        useGPU: Bool,
        threadCount: Int,
        warmup: Bool
    ) async throws {
        loadCalls += 1
        if let mutableLoadError {
            throw mutableLoadError
        }

        mutableState = .loading(modelID: modelID)
        if suspendLoad {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        mutableState = .ready(modelID: modelID)
    }

    func transcribe(_ audio: TranscriptionAudioBuffer, options: WhisperTranscriptionOptions) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "hello",
            noSpeechProbability: 0,
            averageLogProbability: 0,
            compressionRatio: 0
        )
    }

    func loadCallCount() -> Int {
        loadCalls
    }

    func setLoadError(_ error: Error?) {
        mutableLoadError = error
    }

    func releaseLoads() {
        let pendingContinuations = continuations
        continuations.removeAll()
        for continuation in pendingContinuations {
            continuation.resume()
        }
    }
}
