import Foundation
@testable import TextifyTranscription
import XCTest

final class ParaformerRuntimeTests: XCTestCase {
    func testNativeBackendLoadsCachedParaformerWhenIntegrationTestsAreEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TEXTIFY_RUN_PARAFORMER_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set TEXTIFY_RUN_PARAFORMER_INTEGRATION_TESTS=1 to run the local Core ML smoke test.")
        }
        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let modelDirectory = applicationSupport
            .appendingPathComponent("FluidAudio/Models/paraformer-large-zh", isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw XCTSkip("Cached Paraformer assets are not installed.")
        }
        let runtime = ParaformerRuntime()

        try await runtime.load(
            modelID: "paraformer-zh-integration",
            modelDirectory: modelDirectory.path,
            variant: .largeZhInt8
        )

        let state = await runtime.state
        XCTAssertEqual(state, .ready(modelID: "paraformer-zh-integration"))
        await runtime.unload()
    }

    func testLoadWarmsAndTranscribesWithResidentSession() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = FakeParaformerSession()
        let loads = ParaformerLoadRecorder()
        let runtime = ParaformerRuntime(
            backend: ParaformerRuntimeBackend { modelDirectory, variant in
                await loads.record(directory: modelDirectory, variant: variant)
                return session
            }
        )

        try await runtime.load(
            modelID: "paraformer-large-zh-int8",
            modelDirectory: directory.path,
            variant: .largeZhInt8
        )

        let readyState = await runtime.state
        XCTAssertEqual(readyState, .ready(modelID: "paraformer-large-zh-int8"))
        let load = await loads.snapshot()
        XCTAssertEqual(load?.directory.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(load?.variant, .largeZhInt8)
        let warmupSampleCounts = await session.sampleCounts()
        XCTAssertEqual(warmupSampleCounts, [6_400])

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 16_000))
        )

        XCTAssertEqual(result.text, "中文听写")
        XCTAssertEqual(result.noSpeechProbability, 0)
        XCTAssertEqual(result.averageLogProbability, 0)
        XCTAssertEqual(result.timing?.audioDurationMs, 1_000)
        XCTAssertNotNil(result.timing?.inferenceDurationMs)
        let finalSampleCounts = await session.sampleCounts()
        XCTAssertEqual(finalSampleCounts, [6_400, 16_000])
    }

    func testLoadRejectsMissingModelDirectoryBeforeBackendCall() async {
        let loads = ParaformerLoadRecorder()
        let runtime = ParaformerRuntime(
            backend: ParaformerRuntimeBackend { modelDirectory, variant in
                await loads.record(directory: modelDirectory, variant: variant)
                return FakeParaformerSession()
            }
        )
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyMissingParaformer-\(UUID().uuidString)")
            .path

        do {
            try await runtime.load(
                modelID: "paraformer-large-zh-int8",
                modelDirectory: path,
                variant: .largeZhInt8
            )
            XCTFail("Expected missing directory to fail")
        } catch let error as ParaformerRuntimeError {
            XCTAssertEqual(error, .missingModelDirectory(path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let load = await loads.snapshot()
        let failureState = await runtime.state
        XCTAssertNil(load)
        XCTAssertEqual(
            failureState,
            .failed(modelID: "paraformer-large-zh-int8", reason: .missingModelDirectory)
        )
    }

    func testWarmupFailureUnloadsSessionAndReportsFailure() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = FakeParaformerSession(errorOnCall: 1)
        let runtime = ParaformerRuntime(
            backend: ParaformerRuntimeBackend { _, _ in session }
        )

        do {
            try await runtime.load(
                modelID: "paraformer-large-zh-int8",
                modelDirectory: directory.path,
                variant: .largeZhInt8
            )
            XCTFail("Expected warmup failure")
        } catch let error as ParaformerRuntimeError {
            guard case .warmupFailed = error else {
                return XCTFail("Unexpected Paraformer error: \(error)")
            }
        }

        let unloadCallCount = await session.unloadCallCount()
        let failureState = await runtime.state
        XCTAssertEqual(unloadCallCount, 1)
        XCTAssertEqual(
            failureState,
            .failed(modelID: "paraformer-large-zh-int8", reason: .warmupFailed)
        )
    }

    func testTranscriptionRequiresCanonicalAudio() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = ParaformerRuntime(
            backend: ParaformerRuntimeBackend { _, _ in FakeParaformerSession() }
        )
        try await runtime.load(
            modelID: "paraformer-large-zh-int8",
            modelDirectory: directory.path,
            variant: .largeZhInt8,
            warmup: false
        )

        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(sampleRate: 44_100, channelCount: 2, samples: [])
            )
            XCTFail("Expected invalid audio format")
        } catch let error as ParaformerRuntimeError {
            XCTAssertEqual(error, .invalidAudioFormat(sampleRate: 44_100, channelCount: 2))
        }
    }

    func testTranscriptionRejectsAudioBeyondNativeWindowWithoutCallingBackend() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = FakeParaformerSession()
        let runtime = ParaformerRuntime(
            backend: ParaformerRuntimeBackend { _, _ in session }
        )
        try await runtime.load(
            modelID: "paraformer-large-zh-int8",
            modelDirectory: directory.path,
            variant: .largeZhInt8,
            warmup: false
        )
        let actualSamples = ParaformerRuntime.maximumAudioSamples + 1

        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: Array(repeating: 0, count: actualSamples))
            )
            XCTFail("Expected oversized audio to fail instead of being truncated")
        } catch let error as ParaformerRuntimeError {
            XCTAssertEqual(
                error,
                .audioTooLong(
                    maximumSamples: ParaformerRuntime.maximumAudioSamples,
                    actualSamples: actualSamples
                )
            )
        }

        let sampleCounts = await session.sampleCounts()
        XCTAssertEqual(sampleCounts, [])
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyParaformerRuntimeTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private enum FakeParaformerError: Error {
    case failed
}

private actor FakeParaformerSession: ParaformerRuntimeSession {
    private let errorOnCall: Int?
    private var calls: [Int] = []
    private var unloadCalls = 0

    init(errorOnCall: Int? = nil) {
        self.errorOnCall = errorOnCall
    }

    func transcribe(samples: [Float]) throws -> String {
        calls.append(samples.count)
        if calls.count == errorOnCall {
            throw FakeParaformerError.failed
        }
        return calls.count == 1 ? "" : "中文听写"
    }

    func unload() {
        unloadCalls += 1
    }

    func sampleCounts() -> [Int] {
        calls
    }

    func unloadCallCount() -> Int {
        unloadCalls
    }
}

private actor ParaformerLoadRecorder {
    struct Invocation: Sendable {
        let directory: URL
        let variant: ParaformerModelVariant
    }

    private var invocation: Invocation?

    func record(directory: URL, variant: ParaformerModelVariant) {
        invocation = Invocation(directory: directory, variant: variant)
    }

    func snapshot() -> Invocation? {
        invocation
    }
}
