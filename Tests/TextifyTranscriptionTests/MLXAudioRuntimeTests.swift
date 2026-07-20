import Foundation
@testable import TextifyTranscription
import XCTest

final class MLXAudioRuntimeTests: XCTestCase {
    func testLoadWarmsResidentMetalSessionAndTranscribes() async throws {
        let modelDirectory = try Self.makeModelDirectory()
        defer { try? FileManager.default.removeItem(at: modelDirectory) }

        let session = FakeMLXAudioSession()
        let loads = MLXAudioLoadRecorder()
        let runtime = MLXAudioRuntime(
            backend: MLXAudioRuntimeBackend { directory, variant in
                await loads.record(directory: directory, variant: variant)
                return session
            }
        )

        try await runtime.load(
            modelID: "parakeet-rnnt-1.1b",
            modelDirectory: modelDirectory.path,
            variant: .parakeetRNNT1_1B,
            languageCode: "en-US"
        )

        let state = await runtime.state
        XCTAssertEqual(state, .ready(modelID: "parakeet-rnnt-1.1b"))
        let load = await loads.snapshot()
        XCTAssertEqual(load?.directory.standardizedFileURL, modelDirectory.standardizedFileURL)
        XCTAssertEqual(load?.variant, .parakeetRNNT1_1B)
        let warmupSampleCounts = await session.sampleCounts()
        XCTAssertEqual(warmupSampleCounts, [16000])

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 16000))
        )

        XCTAssertEqual(result.text, "Local RNNT transcription")
        XCTAssertEqual(result.noSpeechProbability, 0)
        XCTAssertEqual(result.averageLogProbability, 0)
        XCTAssertEqual(result.timing?.audioDurationMs, 1000)
        XCTAssertNotNil(result.timing?.inferenceDurationMs)
        let sampleCounts = await session.sampleCounts()
        XCTAssertEqual(sampleCounts, [16000, 16000])
    }

    func testLoadRejectsNonMetalBackend() async throws {
        let modelDirectory = try Self.makeModelDirectory()
        defer { try? FileManager.default.removeItem(at: modelDirectory) }
        let session = FakeMLXAudioSession(backendName: "cpu")
        let runtime = MLXAudioRuntime(
            backend: MLXAudioRuntimeBackend { _, _ in session }
        )

        do {
            try await runtime.load(
                modelID: "parakeet-rnnt-1.1b",
                modelDirectory: modelDirectory.path,
                variant: .parakeetRNNT1_1B,
                languageCode: "en",
                warmup: false
            )
            XCTFail("Expected CPU fallback to fail")
        } catch let error as MLXAudioRuntimeError {
            guard case let .loadFailed(message) = error else {
                return XCTFail("Unexpected MLX Audio error: \(error)")
            }
            XCTAssertTrue(message.contains("Metal"))
        }

        let unloadCallCount = await session.unloadCallCount()
        let state = await runtime.state
        XCTAssertEqual(unloadCallCount, 1)
        XCTAssertEqual(
            state,
            .failed(modelID: "parakeet-rnnt-1.1b", reason: .loadFailed)
        )
    }

    func testLoadRequiresExactLocalArtifactFiles() async throws {
        let modelDirectory = try Self.makeModelDirectory(includeWeights: false)
        defer { try? FileManager.default.removeItem(at: modelDirectory) }
        let runtime = MLXAudioRuntime(
            backend: MLXAudioRuntimeBackend { _, _ in FakeMLXAudioSession() }
        )

        do {
            try await runtime.load(
                modelID: "parakeet-rnnt-1.1b",
                modelDirectory: modelDirectory.path,
                variant: .parakeetRNNT1_1B,
                languageCode: "en"
            )
            XCTFail("Expected the missing safetensors file to fail")
        } catch let error as MLXAudioRuntimeError {
            guard case let .missingModelFile(path) = error else {
                return XCTFail("Unexpected MLX Audio error: \(error)")
            }
            XCTAssertTrue(path.hasSuffix("model.safetensors"))
        }
    }

    func testCohereLoadRequiresLocalTokenizerFilesAndUsesThirtySecondCap() async throws {
        let modelDirectory = try Self.makeModelDirectory(includeCohereTokenizer: false)
        defer { try? FileManager.default.removeItem(at: modelDirectory) }
        let runtime = MLXAudioRuntime(
            backend: MLXAudioRuntimeBackend { _, _ in FakeMLXAudioSession() }
        )

        do {
            try await runtime.load(
                modelID: "cohere-transcribe-03-2026-mlx-8bit",
                modelDirectory: modelDirectory.path,
                variant: .cohereTranscribe03_2026,
                languageCode: "en"
            )
            XCTFail("Expected the missing tokenizer file to fail")
        } catch let error as MLXAudioRuntimeError {
            guard case let .missingModelFile(path) = error else {
                return XCTFail("Unexpected MLX Audio error: \(error)")
            }
            XCTAssertTrue(path.hasSuffix("tokenizer.model"))
        }

        try Data([0]).write(to: modelDirectory.appendingPathComponent("tokenizer.model"))
        try Data("{}".utf8).write(
            to: modelDirectory.appendingPathComponent("tokenizer_config.json")
        )
        try await runtime.load(
            modelID: "cohere-transcribe-03-2026-mlx-8bit",
            modelDirectory: modelDirectory.path,
            variant: .cohereTranscribe03_2026,
            languageCode: "en",
            warmup: false
        )

        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 30 * 16000 + 1))
            )
            XCTFail("Expected Cohere audio over 30 seconds to fail")
        } catch let error as MLXAudioRuntimeError {
            XCTAssertEqual(
                error,
                .audioTooLong(maximumSamples: 30 * 16000, actualSamples: 30 * 16000 + 1)
            )
        }
    }

    func testWhisperTurboLoadRequiresLocalTokenizerAssetsAndUsesSixtySecondCap() async throws {
        let modelDirectory = try Self.makeWhisperModelDirectory(includeTokenizerAssets: false)
        defer { try? FileManager.default.removeItem(at: modelDirectory) }
        let runtime = MLXAudioRuntime(
            backend: MLXAudioRuntimeBackend { _, _ in FakeMLXAudioSession() }
        )

        do {
            try await runtime.load(
                modelID: "whisper-large-v3-turbo-mlx",
                modelDirectory: modelDirectory.path,
                variant: .whisperLargeV3Turbo,
                languageCode: "en"
            )
            XCTFail("Expected the missing local tokenizer assets to fail")
        } catch let error as MLXAudioRuntimeError {
            guard case let .missingModelFile(path) = error else {
                return XCTFail("Unexpected MLX Audio error: \(error)")
            }
            XCTAssertTrue(path.hasSuffix("tokenizer.json"))
        }

        try Self.writeWhisperTokenizerAssets(to: modelDirectory)
        try await runtime.load(
            modelID: "whisper-large-v3-turbo-mlx",
            modelDirectory: modelDirectory.path,
            variant: .whisperLargeV3Turbo,
            languageCode: "en",
            warmup: false
        )

        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 60 * 16000 + 1))
            )
            XCTFail("Expected MLX Whisper audio over 60 seconds to fail")
        } catch let error as MLXAudioRuntimeError {
            XCTAssertEqual(
                error,
                .audioTooLong(maximumSamples: 60 * 16000, actualSamples: 60 * 16000 + 1)
            )
        }
    }

    func testQwen3ASRLoadsRequireCompleteLocalAssetsAndSupportAutomaticLanguage() async throws {
        for variant in [
            MLXAudioModelVariant.qwen3ASR0_6B8Bit,
            MLXAudioModelVariant.qwen3ASR1_7B8Bit,
        ] {
            let modelDirectory = try Self.makeQwen3ASRModelDirectory(includeMerges: false)
            defer { try? FileManager.default.removeItem(at: modelDirectory) }
            let runtime = MLXAudioRuntime(
                backend: MLXAudioRuntimeBackend { _, _ in FakeMLXAudioSession() }
            )

            do {
                try await runtime.load(
                    modelID: variant.rawValue,
                    modelDirectory: modelDirectory.path,
                    variant: variant,
                    languageCode: "auto",
                    warmup: false
                )
                XCTFail("Expected the missing Qwen tokenizer merges to fail")
            } catch let error as MLXAudioRuntimeError {
                guard case let .missingModelFile(path) = error else {
                    return XCTFail("Unexpected MLX Audio error: \(error)")
                }
                XCTAssertTrue(path.hasSuffix("merges.txt"))
            }

            try Data("#version: 0.2".utf8).write(
                to: modelDirectory.appendingPathComponent("merges.txt")
            )
            try await runtime.load(
                modelID: variant.rawValue,
                modelDirectory: modelDirectory.path,
                variant: variant,
                languageCode: "auto",
                warmup: false
            )

            do {
                _ = try await runtime.transcribe(
                    TranscriptionAudioBuffer(
                        samples: Array(repeating: 0.1, count: 60 * 16000 + 1)
                    )
                )
                XCTFail("Expected Qwen3-ASR audio over 60 seconds to fail")
            } catch let error as MLXAudioRuntimeError {
                XCTAssertEqual(
                    error,
                    .audioTooLong(
                        maximumSamples: 60 * 16000,
                        actualSamples: 60 * 16000 + 1
                    )
                )
            }
        }
    }

    func testParakeetTDTAndNemotronDeclareCompleteLocalAssetsAndLanguagePolicies() throws {
        XCTAssertEqual(
            MLXAudioModelVariant.parakeetTDT0_6BV2.requiredFilenames,
            ["config.json", "model.safetensors", "tokenizer.model", "tokenizer.vocab", "vocab.txt"]
        )
        XCTAssertEqual(
            MLXAudioModelVariant.parakeetTDT0_6BV3.requiredFilenames,
            ["config.json", "model.safetensors", "tokenizer.model", "tokenizer.vocab", "vocab.txt"]
        )
        XCTAssertEqual(
            MLXAudioModelVariant.nemotron3_5ASRStreaming0_6B.requiredFilenames,
            ["config.json", "model.safetensors", "tokenizer.model", "vocab.txt"]
        )
        XCTAssertEqual(
            try MLXAudioRuntime.requireSupportedLanguage(
                "EN-US",
                variant: .parakeetTDT0_6BV2
            ),
            "en"
        )
        for variant in [
            MLXAudioModelVariant.parakeetTDT0_6BV3,
            .nemotron3_5ASRStreaming0_6B,
        ] {
            XCTAssertEqual(
                try MLXAudioRuntime.requireSupportedLanguage("auto", variant: variant),
                "auto"
            )
        }
    }

    func testRejectsAutomaticAndNonEnglishLanguages() {
        XCTAssertThrowsError(try MLXAudioRuntime.requireSupportedLanguage("auto")) { error in
            XCTAssertEqual(
                error as? MLXAudioRuntimeError,
                .automaticLanguageDetectionUnsupported
            )
        }
        XCTAssertThrowsError(try MLXAudioRuntime.requireSupportedLanguage("hi")) { error in
            XCTAssertEqual(error as? MLXAudioRuntimeError, .unsupportedLanguage("hi"))
        }
        XCTAssertEqual(try MLXAudioRuntime.requireSupportedLanguage("EN-US"), "en")
        XCTAssertEqual(
            try MLXAudioRuntime.requireSupportedLanguage(
                "auto",
                variant: .qwen3ASR0_6B8Bit
            ),
            "auto"
        )
        XCTAssertEqual(
            try MLXAudioRuntime.requireSupportedLanguage(
                "auto",
                variant: .qwen3ASR1_7B8Bit
            ),
            "auto"
        )
    }

    func testSilenceBackstopAvoidsModelInference() async throws {
        let modelDirectory = try Self.makeModelDirectory()
        defer { try? FileManager.default.removeItem(at: modelDirectory) }
        let session = FakeMLXAudioSession()
        let runtime = MLXAudioRuntime(
            backend: MLXAudioRuntimeBackend { _, _ in session }
        )
        try await runtime.load(
            modelID: "parakeet-rnnt-1.1b",
            modelDirectory: modelDirectory.path,
            variant: .parakeetRNNT1_1B,
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
        let sampleCounts = await session.sampleCounts()
        XCTAssertEqual(sampleCounts, [])
    }

    private static func makeModelDirectory(
        includeWeights: Bool = true,
        includeCohereTokenizer: Bool = false
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Textify-MLXAudioRuntimeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
        if includeWeights {
            try Data([0]).write(to: directory.appendingPathComponent("model.safetensors"))
        }
        if includeCohereTokenizer {
            try Data([0]).write(to: directory.appendingPathComponent("tokenizer.model"))
            try Data("{}".utf8).write(
                to: directory.appendingPathComponent("tokenizer_config.json")
            )
        }
        return directory
    }

    private static func makeWhisperModelDirectory(
        includeTokenizerAssets: Bool
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Textify-MLXWhisperRuntimeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
        try Data([0]).write(to: directory.appendingPathComponent("weights.safetensors"))
        if includeTokenizerAssets {
            try writeWhisperTokenizerAssets(to: directory)
        }
        return directory
    }

    private static func writeWhisperTokenizerAssets(to directory: URL) throws {
        for filename in [
            "tokenizer.json",
            "tokenizer_config.json",
            "special_tokens_map.json",
            "added_tokens.json",
            "vocab.json",
            "merges.txt",
            "normalizer.json",
            "generation_config.json",
        ] {
            try Data("{}".utf8).write(to: directory.appendingPathComponent(filename))
        }
    }

    private static func makeQwen3ASRModelDirectory(includeMerges: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Textify-MLXQwen3ASRRuntimeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for filename in [
            "chat_template.json",
            "config.json",
            "generation_config.json",
            "model.safetensors.index.json",
            "preprocessor_config.json",
            "tokenizer_config.json",
            "vocab.json",
        ] {
            try Data("{}".utf8).write(to: directory.appendingPathComponent(filename))
        }
        try Data([0]).write(to: directory.appendingPathComponent("model.safetensors"))
        if includeMerges {
            try Data("#version: 0.2".utf8).write(
                to: directory.appendingPathComponent("merges.txt")
            )
        }
        return directory
    }
}

private actor FakeMLXAudioSession: MLXAudioRuntimeSession {
    let backendName: String
    private let resultText: String
    private var recordedSampleCounts: [Int] = []
    private var unloads = 0

    init(
        backendName: String = "mlx-metal",
        resultText: String = "Local RNNT transcription"
    ) {
        self.backendName = backendName
        self.resultText = resultText
    }

    func transcribe(samples: [Float]) -> MLXAudioSessionResult {
        recordedSampleCounts.append(samples.count)
        return MLXAudioSessionResult(text: resultText)
    }

    func unload() {
        unloads += 1
    }

    func sampleCounts() -> [Int] {
        recordedSampleCounts
    }

    func unloadCallCount() -> Int {
        unloads
    }
}

private actor MLXAudioLoadRecorder {
    private var load: (directory: URL, variant: MLXAudioModelVariant)?

    func record(directory: URL, variant: MLXAudioModelVariant) {
        load = (directory, variant)
    }

    func snapshot() -> (directory: URL, variant: MLXAudioModelVariant)? {
        load
    }
}
