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

    func testNativeRuntimeLoadsPinnedCanaryQwenOnMetalWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TEXTIFY_RUN_CANARY_QWEN_NATIVE_TESTS"] == "1" else {
            throw XCTSkip(
                "Set TEXTIFY_RUN_CANARY_QWEN_NATIVE_TESTS=1 for the pinned Canary-Qwen Metal smoke test."
            )
        }
        guard let modelPath = environment["TEXTIFY_CANARY_Q4_MODEL_PATH"],
              !modelPath.isEmpty
        else {
            XCTFail("TEXTIFY_CANARY_Q4_MODEL_PATH must point to the pinned Q4_K_M GGUF.")
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
            modelID: "canary-qwen-2.5b-q4-k-m",
            modelPath: modelPath,
            variant: .canaryQwen2_5B,
            languageCode: "en",
            warmup: false
        )

        let state = await runtime.state
        XCTAssertEqual(state, .ready(modelID: "canary-qwen-2.5b-q4-k-m"))
        let audioURL = repositoryRoot.appendingPathComponent(
            "Benchmarks/RealtimeASR/.benchmark-data/openslr31/LibriSpeech/dev-clean-2/1272/141231/1272-141231-0000.flac"
        )
        let result = try await runtime.transcribe(Self.loadPCMMono16K(from: audioURL))
        XCTAssertEqual(result.text, "A man said to the universe, Sir, I exist")
        XCTAssertLessThan(result.timing?.inferenceDurationMs ?? .max, 700)
        await runtime.unload()
    }

    func testNativeRuntimeLoadsArticleModelsOnMetalWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TEXTIFY_RUN_ARTICLE_ASR_NATIVE_TESTS"] == "1" else {
            throw XCTSkip(
                "Set TEXTIFY_RUN_ARTICLE_ASR_NATIVE_TESTS=1 for the pinned article-model Metal smokes."
            )
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimeDirectory = repositoryRoot
            .appendingPathComponent("Vendor/transcribe.cpp/v0.1.3/lib", isDirectory: true)
        let candidates: [(String, String, TranscribeCppModelVariant)] = [
            (
                "granite-speech-4.1-2b-q5-k-m",
                "granite-speech-4.1-2b-Q5_K_M.gguf",
                .graniteSpeech4_1_2B
            ),
            (
                "granite-speech-4.1-2b-nar-q5-k-m",
                "granite-speech-4.1-2b-nar-Q5_K_M.gguf",
                .graniteSpeech4_1_2BNAR
            ),
            (
                "voxtral-mini-4b-realtime-2602-q4-k-m",
                "Voxtral-Mini-4B-Realtime-2602-Q4_K_M.gguf",
                .voxtralMini4BRealtime2602
            ),
            (
                "moss-transcribe-diarize-0.9b-q5-k-m",
                "MOSS-Transcribe-Diarize-Q5_K_M.gguf",
                .mossTranscribeDiarize0_9B
            ),
        ]
        let audioURL = repositoryRoot.appendingPathComponent(
            "Benchmarks/RealtimeASR/.benchmark-data/openslr31/LibriSpeech/dev-clean-2/1272/141231/1272-141231-0000.flac"
        )
        let audio = try Self.loadPCMMono16K(from: audioURL)

        for (modelID, filename, variant) in candidates {
            let modelURL = repositoryRoot
                .appendingPathComponent(".build/model-artifact-audit", isDirectory: true)
                .appendingPathComponent(modelID, isDirectory: true)
                .appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: modelURL.path) else {
                XCTFail("The pinned article-model audit artifact is missing: \(modelURL.path)")
                return
            }
            let runtime = TranscribeCppRuntime(runtimeDirectory: runtimeDirectory.path)
            try await runtime.load(
                modelID: modelID,
                modelPath: modelURL.path,
                variant: variant,
                languageCode: "auto",
                warmup: false
            )

            let result = try await runtime.transcribe(audio)
            XCTAssertTrue(
                result.text.unicodeScalars.contains {
                    CharacterSet.alphanumerics.contains($0)
                },
                "\(modelID) returned no linguistic content."
            )
            XCTAssertLessThan(result.timing?.inferenceDurationMs ?? .max, 10_000, modelID)
            await runtime.unload()
        }
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
        XCTAssertEqual(warmupCalls.map(\.sampleCount), [6400])
        XCTAssertEqual(warmupCalls.map(\.sampleRate), [16000])
        XCTAssertEqual(warmupCalls.map(\.languageCode), ["en"])

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 16000))
        )

        XCTAssertEqual(result.text, "Fast local transcription")
        XCTAssertEqual(result.noSpeechProbability, 0)
        XCTAssertEqual(result.averageLogProbability, 0)
        XCTAssertEqual(result.timing?.audioDurationMs, 1000)
        XCTAssertNotNil(result.timing?.inferenceDurationMs)
        let calls = await session.callsSnapshot()
        XCTAssertEqual(calls.map(\.sampleCount), [6400, 16000])
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

    func testLoadRejectsAutomaticAndUnpromotedLanguages() throws {
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
        XCTAssertEqual(
            try TranscribeCppRuntime.requireSupportedLanguage(
                "EN-US",
                variant: .canaryQwen2_5B
            ),
            "en"
        )
        XCTAssertThrowsError(
            try TranscribeCppRuntime.requireSupportedLanguage(
                "vi",
                variant: .canaryQwen2_5B
            )
        ) { error in
            XCTAssertEqual(error as? TranscribeCppRuntimeError, .unsupportedLanguage("vi"))
        }
        XCTAssertEqual(
            try TranscribeCppRuntime.requireSupportedLanguage(
                "auto",
                variant: .qwen3ASR0_6B
            ),
            "auto"
        )
        XCTAssertEqual(
            try TranscribeCppRuntime.requireSupportedLanguage(
                "auto",
                variant: .qwen3ASR1_7B
            ),
            "auto"
        )
        XCTAssertEqual(
            try TranscribeCppRuntime.requireSupportedLanguage(
                "en",
                variant: .qwen3ASR0_6B
            ),
            "en"
        )
        XCTAssertEqual(
            try TranscribeCppRuntime.requireSupportedLanguage(
                "EN-US",
                variant: .parakeetTDT0_6BV2
            ),
            "en"
        )
        for variant in [
            TranscribeCppModelVariant.parakeetTDT0_6BV3,
            .nemotron3_5ASRStreaming0_6B,
            .graniteSpeech4_1_2B,
            .graniteSpeech4_1_2BNAR,
            .voxtralMini4BRealtime2602,
            .mossTranscribeDiarize0_9B,
        ] {
            XCTAssertEqual(
                try TranscribeCppRuntime.requireSupportedLanguage("auto", variant: variant),
                "auto"
            )
        }
    }

    func testQwen3ASRUsesConfiguredLanguageForWarmupAndInference() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelURL = try Self.makeTemporaryModelFile()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelURL.deletingLastPathComponent())
        }

        for variant in [
            TranscribeCppModelVariant.qwen3ASR0_6B,
            TranscribeCppModelVariant.qwen3ASR1_7B,
        ] {
            for languageCode in ["auto", "en"] {
                let session = FakeTranscribeCppSession()
                let runtime = TranscribeCppRuntime(
                    runtimeDirectory: runtimeDirectory.path,
                    backend: TranscribeCppRuntimeBackend { _, _, _, _ in session }
                )
                try await runtime.load(
                    modelID: variant.rawValue,
                    modelPath: modelURL.path,
                    variant: variant,
                    languageCode: languageCode
                )
                _ = try await runtime.transcribe(
                    TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 16000))
                )

                let calls = await session.callsSnapshot()
                XCTAssertEqual(calls.map(\.languageCode), [languageCode, languageCode])
            }
        }
    }

    func testArticleModelsUseAutomaticLanguageForWarmupAndInference() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelURL = try Self.makeTemporaryModelFile()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelURL.deletingLastPathComponent())
        }

        for variant in [
            TranscribeCppModelVariant.graniteSpeech4_1_2B,
            .graniteSpeech4_1_2BNAR,
            .voxtralMini4BRealtime2602,
            .mossTranscribeDiarize0_9B,
        ] {
            let session = FakeTranscribeCppSession()
            let runtime = TranscribeCppRuntime(
                runtimeDirectory: runtimeDirectory.path,
                backend: TranscribeCppRuntimeBackend { _, _, _, _ in session }
            )
            try await runtime.load(
                modelID: variant.rawValue,
                modelPath: modelURL.path,
                variant: variant,
                languageCode: "auto"
            )
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 16_000))
            )

            let calls = await session.callsSnapshot()
            XCTAssertEqual(calls.map(\.languageCode), ["auto", "auto"])
        }
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
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 16000))
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

    func testCanaryRejectsAudioLongerThanFortySeconds() async throws {
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
            modelID: "canary-qwen-2.5b-q4-k-m",
            modelPath: modelURL.path,
            variant: .canaryQwen2_5B,
            languageCode: "en",
            warmup: false
        )
        let maximumSamples = 40 * 16000
        let actualSamples = maximumSamples + 1

        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: actualSamples))
            )
            XCTFail("Expected overlong Canary audio to fail")
        } catch let error as TranscribeCppRuntimeError {
            XCTAssertEqual(
                error,
                .audioTooLong(maximumSamples: maximumSamples, actualSamples: actualSamples)
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
        guard format.sampleRate == 16000, format.channelCount == 1,
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
    struct Call: Equatable {
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
    struct Load {
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
