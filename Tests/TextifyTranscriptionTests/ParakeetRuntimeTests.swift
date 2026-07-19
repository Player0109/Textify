import Foundation
@testable import TextifyTranscription
import XCTest

final class ParakeetRuntimeTests: XCTestCase {
    func testVariantsVerifyTheModelContainingTheirEncoder() {
        XCTAssertEqual(ParakeetModelVariant.tdtV2.neuralEngineVerificationModelNameFragments, ["encoder"])
        XCTAssertEqual(ParakeetModelVariant.tdtV3.neuralEngineVerificationModelNameFragments, ["encoder"])
        XCTAssertEqual(ParakeetModelVariant.tdtJapanese.neuralEngineVerificationModelNameFragments, ["encoder"])
        XCTAssertEqual(
            ParakeetModelVariant.tdtCtc110M.neuralEngineVerificationModelNameFragments,
            ["preprocessor"]
        )
    }

    func testNativeBackendLoadsCachedParakeetV3WhenIntegrationTestsAreEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TEXTIFY_RUN_PARAKEET_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set TEXTIFY_RUN_PARAKEET_INTEGRATION_TESTS=1 to run the local Core ML smoke test.")
        }
        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let modelDirectory = applicationSupport
            .appendingPathComponent("FluidAudio/Models/parakeet-tdt-0.6b-v3", isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw XCTSkip("Cached Parakeet V3 assets are not installed.")
        }
        let runtime = ParakeetRuntime()

        try await runtime.load(
            modelID: "parakeet-v3-integration",
            modelDirectory: modelDirectory.path,
            variant: .tdtV3,
            languageCode: "en"
        )

        let state = await runtime.state
        XCTAssertEqual(state, .ready(modelID: "parakeet-v3-integration"))
        await runtime.unload()
    }

    func testLoadWarmsAndTranscribesWithResidentSession() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = FakeParakeetSession()
        let loads = ParakeetLoadRecorder()
        let runtime = ParakeetRuntime(
            backend: ParakeetRuntimeBackend { modelDirectory, variant, computeRoute in
                await loads.record(
                    directory: modelDirectory,
                    variant: variant,
                    computeRoute: computeRoute
                )
                return session
            }
        )

        try await runtime.load(
            modelID: "parakeet-v3-int8",
            modelDirectory: directory.path,
            variant: .tdtV3,
            languageCode: "en"
        )

        let readyState = await runtime.state
        XCTAssertEqual(readyState, .ready(modelID: "parakeet-v3-int8"))
        let load = await loads.snapshot()
        XCTAssertEqual(load?.directory.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(load?.variant, .tdtV3)
        XCTAssertEqual(load?.computeRoute, .neuralEngine)
        let warmupSampleCounts = await session.sampleCounts()
        XCTAssertEqual(warmupSampleCounts, [6_400])

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 16_000))
        )

        XCTAssertEqual(result.text, "hello from parakeet")
        XCTAssertEqual(result.noSpeechProbability, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(result.averageLogProbability, log(0.95), accuracy: 0.000_001)
        XCTAssertEqual(result.timing?.audioDurationMs, 1_000)
        XCTAssertNotNil(result.timing?.inferenceDurationMs)
        let sampleCounts = await session.sampleCounts()
        let languageCodes = await session.languageCodes()
        XCTAssertEqual(sampleCounts, [6_400, 16_000])
        XCTAssertEqual(languageCodes, ["en", "en"])
    }

    func testLoadRejectsMissingModelDirectoryBeforeBackendCall() async {
        let loads = ParakeetLoadRecorder()
        let runtime = ParakeetRuntime(
            backend: ParakeetRuntimeBackend { modelDirectory, variant, computeRoute in
                await loads.record(
                    directory: modelDirectory,
                    variant: variant,
                    computeRoute: computeRoute
                )
                return FakeParakeetSession()
            }
        )
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyMissingParakeet-\(UUID().uuidString)")
            .path

        do {
            try await runtime.load(
                modelID: "parakeet-v3-int8",
                modelDirectory: path,
                variant: .tdtV3
            )
            XCTFail("Expected missing directory to fail")
        } catch let error as ParakeetRuntimeError {
            XCTAssertEqual(error, .missingModelDirectory(path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let load = await loads.snapshot()
        let failureState = await runtime.state
        XCTAssertNil(load)
        XCTAssertEqual(
            failureState,
            .failed(modelID: "parakeet-v3-int8", reason: .missingModelDirectory)
        )
    }

    func testWarmupFailureUnloadsSessionAndReportsFailure() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = FakeParakeetSession(errorOnCall: 1)
        let runtime = ParakeetRuntime(
            backend: ParakeetRuntimeBackend { _, _, _ in session }
        )

        do {
            try await runtime.load(
                modelID: "parakeet-v3-int8",
                modelDirectory: directory.path,
                variant: .tdtV3
            )
            XCTFail("Expected warmup failure")
        } catch let error as ParakeetRuntimeError {
            guard case .warmupFailed = error else {
                return XCTFail("Unexpected Parakeet error: \(error)")
            }
        }

        let unloadCallCount = await session.unloadCallCount()
        let failureState = await runtime.state
        XCTAssertEqual(unloadCallCount, 1)
        XCTAssertEqual(
            failureState,
            .failed(modelID: "parakeet-v3-int8", reason: .warmupFailed)
        )
    }

    func testTranscriptionRequiresCanonicalAudio() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = ParakeetRuntime(
            backend: ParakeetRuntimeBackend { _, _, _ in FakeParakeetSession() }
        )
        try await runtime.load(
            modelID: "parakeet-v3-int8",
            modelDirectory: directory.path,
            variant: .tdtV3,
            warmup: false
        )

        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(sampleRate: 44_100, channelCount: 2, samples: [])
            )
            XCTFail("Expected invalid audio format")
        } catch let error as ParakeetRuntimeError {
            XCTAssertEqual(error, .invalidAudioFormat(sampleRate: 44_100, channelCount: 2))
        }
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyParakeetRuntimeTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private enum FakeParakeetError: Error {
    case failed
}

private actor FakeParakeetSession: ParakeetRuntimeSession {
    private let errorOnCall: Int?
    private var calls: [(sampleCount: Int, languageCode: String?)] = []
    private var unloadCalls = 0

    init(errorOnCall: Int? = nil) {
        self.errorOnCall = errorOnCall
    }

    func transcribe(samples: [Float], languageCode: String?) async throws -> ParakeetSessionResult {
        calls.append((samples.count, languageCode))
        if calls.count == errorOnCall {
            throw FakeParakeetError.failed
        }
        return ParakeetSessionResult(
            text: calls.count == 1 ? "" : "hello from parakeet",
            confidence: 0.95,
            processingTimeSeconds: 0.01
        )
    }

    func unload() {
        unloadCalls += 1
    }

    func sampleCounts() -> [Int] {
        calls.map(\.sampleCount)
    }

    func languageCodes() -> [String?] {
        calls.map(\.languageCode)
    }

    func unloadCallCount() -> Int {
        unloadCalls
    }
}

private actor ParakeetLoadRecorder {
    struct Invocation: Sendable {
        let directory: URL
        let variant: ParakeetModelVariant
        let computeRoute: ParakeetComputeRoute
    }

    private var invocation: Invocation?

    func record(
        directory: URL,
        variant: ParakeetModelVariant,
        computeRoute: ParakeetComputeRoute
    ) {
        invocation = Invocation(
            directory: directory,
            variant: variant,
            computeRoute: computeRoute
        )
    }

    func snapshot() -> Invocation? {
        invocation
    }
}
