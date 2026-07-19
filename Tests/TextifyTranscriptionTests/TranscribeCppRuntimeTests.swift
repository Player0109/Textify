@preconcurrency import AVFoundation
import Foundation
@testable import TextifyTranscription
import XCTest

final class TranscribeCppRuntimeTests: XCTestCase {
    func testNativeRuntimeLoadsPinnedQ8OnMetalWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TEXTIFY_RUN_FUNASR_NATIVE_TESTS"] == "1" else {
            throw XCTSkip("Set TEXTIFY_RUN_FUNASR_NATIVE_TESTS=1 for the pinned Metal smoke test.")
        }
        guard let modelPath = environment["TEXTIFY_FUNASR_Q8_MODEL_PATH"],
              !modelPath.isEmpty
        else {
            XCTFail("TEXTIFY_FUNASR_Q8_MODEL_PATH must point to the pinned Q8_0 GGUF.")
            return
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimeDirectory = repositoryRoot
            .appendingPathComponent("Vendor/transcribe.cpp/v0.1.3/lib", isDirectory: true)
        let runtime = TranscribeCppRuntime(runtimeDirectory: runtimeDirectory.path)

        try await runtime.load(
            modelID: "funasr-mlt-nano-2512-q8",
            modelPath: modelPath,
            variant: .funASRMLTNanoQ8,
            languageCode: "en",
            warmup: false
        )

        let state = await runtime.state
        XCTAssertEqual(state, .ready(modelID: "funasr-mlt-nano-2512-q8"))
        let audioURL = repositoryRoot.appendingPathComponent(
            "Benchmarks/RealtimeASR/.benchmark-data/fleurs-funasr-mlt-31-sample/en/0.wav"
        )
        let result = try await runtime.transcribe(Self.loadPCMMono16K(from: audioURL))
        XCTAssertEqual(
            result.text,
            "When you call someone who is thousands of miles away, you are using a satellite."
        )
        XCTAssertLessThan(result.timing?.inferenceDurationMs ?? .max, 700)
        await runtime.unload()
    }

    func testLoadWarmsResidentMetalSessionAndTranscribes() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelURL = try Self.makeTemporaryModelFile()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelURL.deletingLastPathComponent())
        }

        let session = FakeTranscribeCppSession()
        let loads = TranscribeCppLoadRecorder()
        let runtime = TranscribeCppRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: TranscribeCppRuntimeBackend {
                runtimeDirectory,
                modelURL,
                variant,
                threadCount in
                await loads.record(
                    runtimeDirectory: runtimeDirectory,
                    modelURL: modelURL,
                    variant: variant,
                    threadCount: threadCount
                )
                return session
            }
        )

        try await runtime.load(
            modelID: "funasr-mlt-nano-2512-q8",
            modelPath: modelURL.path,
            variant: .funASRMLTNanoQ8,
            languageCode: "en-US"
        )

        let state = await runtime.state
        XCTAssertEqual(state, .ready(modelID: "funasr-mlt-nano-2512-q8"))
        let load = await loads.snapshot()
        XCTAssertEqual(load?.runtimeDirectory.standardizedFileURL, runtimeDirectory.standardizedFileURL)
        XCTAssertEqual(load?.modelURL.standardizedFileURL, modelURL.standardizedFileURL)
        XCTAssertEqual(load?.variant, .funASRMLTNanoQ8)
        XCTAssertEqual(load?.threadCount, 4)
        let warmupCalls = await session.callsSnapshot()
        XCTAssertEqual(warmupCalls.map(\.sampleCount), [6_400])
        XCTAssertEqual(warmupCalls.map(\.sampleRate), [16_000])
        XCTAssertEqual(warmupCalls.map(\.languageCode), ["en"])

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 16_000))
        )

        XCTAssertEqual(result.text, "Fast local transcription")
        XCTAssertEqual(result.noSpeechProbability, 0)
        XCTAssertEqual(result.averageLogProbability, 0)
        XCTAssertEqual(result.timing?.audioDurationMs, 1_000)
        XCTAssertNotNil(result.timing?.inferenceDurationMs)
        let calls = await session.callsSnapshot()
        XCTAssertEqual(calls.map(\.sampleCount), [6_400, 16_000])
        XCTAssertEqual(calls.map(\.languageCode), ["en", "en"])
    }

    func testLoadRejectsNonMetalBackend() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelURL = try Self.makeTemporaryModelFile()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelURL.deletingLastPathComponent())
        }
        let session = FakeTranscribeCppSession(backendName: "cpu")
        let runtime = TranscribeCppRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: TranscribeCppRuntimeBackend { _, _, _, _ in session }
        )

        do {
            try await runtime.load(
                modelID: "funasr-mlt-nano-2512-q8",
                modelPath: modelURL.path,
                variant: .funASRMLTNanoQ8,
                languageCode: "en",
                warmup: false
            )
            XCTFail("Expected CPU fallback to fail")
        } catch let error as TranscribeCppRuntimeError {
            guard case let .loadFailed(message) = error else {
                return XCTFail("Unexpected transcribe.cpp error: \(error)")
            }
            XCTAssertTrue(message.contains("Metal"))
        }

        let unloaded = await session.unloadCallCount()
        let state = await runtime.state
        XCTAssertEqual(unloaded, 1)
        XCTAssertEqual(
            state,
            .failed(modelID: "funasr-mlt-nano-2512-q8", reason: .loadFailed)
        )
    }

    func testLoadRejectsAutomaticAndUnpromotedLanguages() async throws {
        XCTAssertThrowsError(try TranscribeCppRuntime.requireSupportedLanguage("auto")) { error in
            XCTAssertEqual(
                error as? TranscribeCppRuntimeError,
                .automaticLanguageDetectionUnsupported
            )
        }
        XCTAssertThrowsError(try TranscribeCppRuntime.requireSupportedLanguage("hi")) { error in
            XCTAssertEqual(error as? TranscribeCppRuntimeError, .unsupportedLanguage("hi"))
        }
        XCTAssertEqual(
            try TranscribeCppRuntime.requireSupportedLanguage("YUE-Hant-HK"),
            "yue"
        )
    }

    func testSilenceBackstopMarksHallucinatedTextAsNoSpeech() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelURL = try Self.makeTemporaryModelFile()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelURL.deletingLastPathComponent())
        }
        let session = FakeTranscribeCppSession(resultText: "hallucinated text")
        let runtime = TranscribeCppRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: TranscribeCppRuntimeBackend { _, _, _, _ in session }
        )
        try await runtime.load(
            modelID: "funasr-mlt-nano-2512-q8",
            modelPath: modelURL.path,
            variant: .funASRMLTNanoQ8,
            languageCode: "en",
            warmup: false
        )

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 16_000))
        )

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.noSpeechProbability, 1)
        XCTAssertEqual(result.averageLogProbability, -10)
        XCTAssertEqual(result.timing?.inferenceDurationMs, 0)
        let calls = await session.callsSnapshot()
        XCTAssertTrue(calls.isEmpty)
    }

    func testRejectsAudioLongerThanSixtySeconds() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelURL = try Self.makeTemporaryModelFile()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelURL.deletingLastPathComponent())
        }
        let runtime = TranscribeCppRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: TranscribeCppRuntimeBackend { _, _, _, _ in FakeTranscribeCppSession() }
        )
        try await runtime.load(
            modelID: "funasr-mlt-nano-2512-q8",
            modelPath: modelURL.path,
            variant: .funASRMLTNanoQ8,
            languageCode: "en",
            warmup: false
        )
        let actualSamples = TranscribeCppRuntime.maximumAudioSamples + 1

        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: actualSamples))
            )
            XCTFail("Expected overlong audio to fail")
        } catch let error as TranscribeCppRuntimeError {
            XCTAssertEqual(
                error,
                .audioTooLong(
                    maximumSamples: TranscribeCppRuntime.maximumAudioSamples,
                    actualSamples: actualSamples
                )
            )
        }
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyTranscribeCppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeTemporaryModelFile() throws -> URL {
        let directory = try makeTemporaryDirectory()
        let modelURL = directory.appendingPathComponent(
            "Fun-ASR-MLT-Nano-2512-Q8_0.gguf",
            isDirectory: false
        )
        try Data("fixture".utf8).write(to: modelURL)
        return modelURL
    }

    private static func loadPCMMono16K(from sourceURL: URL) throws -> TranscriptionAudioBuffer {
        let file = try AVAudioFile(forReading: sourceURL)
        let format = file.processingFormat
        guard format.sampleRate == 16_000, format.channelCount == 1,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(file.length)
              )
        else {
            throw TranscribeCppIntegrationAudioError.invalidFormat
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?.pointee else {
            throw TranscribeCppIntegrationAudioError.invalidFormat
        }
        return TranscriptionAudioBuffer(
            samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        )
    }
}

private enum TranscribeCppIntegrationAudioError: Error {
    case invalidFormat
}

private actor FakeTranscribeCppSession: TranscribeCppRuntimeSession {
    struct Call: Equatable, Sendable {
        let sampleCount: Int
        let sampleRate: Int
        let languageCode: String
    }

    let backendName: String
    private let resultText: String
    private var calls: [Call] = []
    private var unloadCalls = 0

    init(
        backendName: String = "metal",
        resultText: String = "Fast local transcription"
    ) {
        self.backendName = backendName
        self.resultText = resultText
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        languageCode: String
    ) -> TranscribeCppSessionResult {
        calls.append(
            Call(
                sampleCount: samples.count,
                sampleRate: sampleRate,
                languageCode: languageCode
            )
        )
        return TranscribeCppSessionResult(text: resultText)
    }

    func unload() {
        unloadCalls += 1
    }

    func callsSnapshot() -> [Call] {
        calls
    }

    func unloadCallCount() -> Int {
        unloadCalls
    }
}

private actor TranscribeCppLoadRecorder {
    struct Load: Sendable {
        let runtimeDirectory: URL
        let modelURL: URL
        let variant: TranscribeCppModelVariant
        let threadCount: Int
    }

    private var load: Load?

    func record(
        runtimeDirectory: URL,
        modelURL: URL,
        variant: TranscribeCppModelVariant,
        threadCount: Int
    ) {
        load = Load(
            runtimeDirectory: runtimeDirectory,
            modelURL: modelURL,
            variant: variant,
            threadCount: threadCount
        )
    }

    func snapshot() -> Load? {
        load
    }
}
