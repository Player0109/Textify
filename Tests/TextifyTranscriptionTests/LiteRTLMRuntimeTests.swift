import Foundation
@testable import TextifyTranscription
import XCTest

final class LiteRTLMRuntimeTests: XCTestCase {
    func testLoadAndTranscribeUseTemporaryPCM16WAVThenRemoveIt() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelURL = root.appendingPathComponent("gemma-4-12B-it.litertlm")
        try Data("model".utf8).write(to: modelURL)
        let session = FakeLiteRTLMSession()
        let runtime = LiteRTLMRuntime(
            cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
            backend: LiteRTLMRuntimeBackend { _, _, _ in session }
        )

        try await runtime.load(
            modelID: "gemma-4-12b-litertlm",
            modelPath: modelURL.path,
            variant: .gemma4_12B,
            languageCode: "en-US",
            warmup: false
        )
        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.25, count: 16_000))
        )

        XCTAssertEqual(result.text, "Exact local Gemma transcript")
        XCTAssertEqual(result.timing?.audioDurationMs, 1_000)
        let recordedSnapshot = await session.snapshot()
        let snapshot = try XCTUnwrap(recordedSnapshot)
        XCTAssertEqual(snapshot.data.count, 32_044)
        XCTAssertEqual(String(decoding: snapshot.data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: snapshot.data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.url.path))
    }

    func testLoadRejectsMissingOrWrongArtifact() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = LiteRTLMRuntime(
            cacheDirectory: root,
            backend: LiteRTLMRuntimeBackend { _, _, _ in FakeLiteRTLMSession() }
        )

        do {
            try await runtime.load(
                modelID: "gemma-4-12b-litertlm",
                modelPath: root.appendingPathComponent("model.bin").path,
                variant: .gemma4_12B,
                languageCode: "en"
            )
            XCTFail("Expected a missing non-LiteRT artifact to fail")
        } catch let error as LiteRTLMRuntimeError {
            guard case .missingModelFile = error else {
                return XCTFail("Unexpected LiteRT-LM error: \(error)")
            }
        }
    }

    func testLoadRejectsNonMetalBackend() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelURL = root.appendingPathComponent("model.litertlm")
        try Data("model".utf8).write(to: modelURL)
        let session = FakeLiteRTLMSession(backendName: "litert-cpu")
        let runtime = LiteRTLMRuntime(
            cacheDirectory: root,
            backend: LiteRTLMRuntimeBackend { _, _, _ in session }
        )

        do {
            try await runtime.load(
                modelID: "gemma-4-12b-litertlm",
                modelPath: modelURL.path,
                variant: .gemma4_12B,
                languageCode: "en",
                warmup: false
            )
            XCTFail("Expected CPU fallback to fail")
        } catch let error as LiteRTLMRuntimeError {
            guard case let .loadFailed(message) = error else {
                return XCTFail("Unexpected LiteRT-LM error: \(error)")
            }
            XCTAssertTrue(message.contains("Metal"))
        }
        let unloadCallCount = await session.unloadCallCount()
        XCTAssertEqual(unloadCallCount, 1)
    }

    func testThirtySecondCapLanguageAndSilenceBackstop() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelURL = root.appendingPathComponent("model.litertlm")
        try Data("model".utf8).write(to: modelURL)
        let session = FakeLiteRTLMSession()
        let runtime = LiteRTLMRuntime(
            cacheDirectory: root,
            backend: LiteRTLMRuntimeBackend { _, _, _ in session }
        )
        try await runtime.load(
            modelID: "gemma-4-12b-litertlm",
            modelPath: modelURL.path,
            variant: .gemma4_12B,
            languageCode: "en",
            warmup: false
        )

        let silence = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 16_000))
        )
        XCTAssertEqual(silence.text, "")
        XCTAssertEqual(silence.noSpeechProbability, 1)
        let silenceSnapshot = await session.snapshot()
        XCTAssertNil(silenceSnapshot)

        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 30 * 16_000 + 1))
            )
            XCTFail("Expected audio over 30 seconds to fail")
        } catch let error as LiteRTLMRuntimeError {
            XCTAssertEqual(
                error,
                .audioTooLong(maximumSamples: 30 * 16_000, actualSamples: 30 * 16_000 + 1)
            )
        }

        XCTAssertThrowsError(try LiteRTLMRuntime.requireSupportedLanguage("auto"))
        XCTAssertThrowsError(try LiteRTLMRuntime.requireSupportedLanguage("hi"))
    }

    private static func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Textify-LiteRTLMRuntimeTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor FakeLiteRTLMSession: LiteRTLMRuntimeSession {
    let backendName: String
    private var recording: (url: URL, data: Data)?
    private var unloads = 0

    init(backendName: String = "litert-metal-gpu") {
        self.backendName = backendName
    }

    func transcribe(audioFileURL: URL) throws -> LiteRTLMSessionResult {
        recording = (audioFileURL, try Data(contentsOf: audioFileURL))
        return LiteRTLMSessionResult(text: "Exact local Gemma transcript")
    }

    func unload() {
        unloads += 1
    }

    func snapshot() -> (url: URL, data: Data)? {
        recording
    }

    func unloadCallCount() -> Int {
        unloads
    }
}
