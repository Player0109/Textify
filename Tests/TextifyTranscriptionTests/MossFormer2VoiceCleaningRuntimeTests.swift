import Foundation
@testable import TextifyTranscription
import XCTest

final class MossFormer2VoiceCleaningRuntimeTests: XCTestCase {
    func testLoadWarmsMetalSessionAndCleansCanonicalAudio() async throws {
        let directory = try Self.makeModelDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = FakeMossFormer2Session()
        let runtime = MossFormer2VoiceCleaningRuntime(
            backend: MossFormer2VoiceCleaningBackend { _ in session }
        )

        try await runtime.load(
            modelID: "mossformer2-se-fp16",
            modelDirectory: directory.path,
            variant: .fp16
        )
        let output = try await runtime.clean(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.25, count: 16_000))
        )

        let runtimeState = await runtime.state
        XCTAssertEqual(runtimeState, .ready(modelID: "mossformer2-se-fp16"))
        XCTAssertEqual(output.sampleRate, 16_000)
        XCTAssertEqual(output.channelCount, 1)
        XCTAssertEqual(output.samples.count, 16_000)
        XCTAssertLessThan(output.samples.map(abs).max() ?? 1, 0.2)
        let sampleCounts = await session.sampleCounts()
        XCTAssertEqual(sampleCounts.first, 12_000)
        XCTAssertEqual(sampleCounts.last, 48_000)
    }

    func testLoadRejectsNonMetalBackend() async throws {
        let directory = try Self.makeModelDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = FakeMossFormer2Session(backendName: "cpu")
        let runtime = MossFormer2VoiceCleaningRuntime(
            backend: MossFormer2VoiceCleaningBackend { _ in session }
        )

        await XCTAssertThrowsErrorAsync {
            try await runtime.load(
                modelID: "mossformer2-se-fp16",
                modelDirectory: directory.path,
                variant: .fp16,
                warmup: false
            )
        }
        let runtimeState = await runtime.state
        let unloadCallCount = await session.unloadCallCount()
        XCTAssertEqual(runtimeState, .failed(modelID: "mossformer2-se-fp16", reason: .loadFailed))
        XCTAssertEqual(unloadCallCount, 1)
    }

    func testLoadRequiresConfigAndSafetensors() async throws {
        let directory = try Self.makeModelDirectory(includeWeights: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = MossFormer2VoiceCleaningRuntime(
            backend: MossFormer2VoiceCleaningBackend { _ in FakeMossFormer2Session() }
        )

        do {
            try await runtime.load(
                modelID: "mossformer2-se-fp16",
                modelDirectory: directory.path,
                variant: .fp16
            )
            XCTFail("Expected missing model weights to fail")
        } catch let error as MossFormer2VoiceCleaningError {
            guard case let .missingModelFile(path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(path.hasSuffix("model.safetensors"))
        }
    }

    func testCleaningRejectsNonCanonicalAndOversizedAudio() async throws {
        let directory = try Self.makeModelDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = MossFormer2VoiceCleaningRuntime(
            backend: MossFormer2VoiceCleaningBackend { _ in FakeMossFormer2Session() }
        )
        try await runtime.load(
            modelID: "mossformer2-se-int8",
            modelDirectory: directory.path,
            variant: .int8,
            warmup: false
        )

        do {
            _ = try await runtime.clean(
                TranscriptionAudioBuffer(sampleRate: 48_000, channelCount: 1, samples: [0.1])
            )
            XCTFail("Expected non-canonical input to fail")
        } catch let error as MossFormer2VoiceCleaningError {
            XCTAssertEqual(error, .invalidAudioFormat(sampleRate: 48_000, channelCount: 1))
        }
        do {
            _ = try await runtime.clean(
                TranscriptionAudioBuffer(
                    samples: Array(
                        repeating: 0.1,
                        count: MossFormer2VoiceCleaningRuntime.maximumAudioSamples + 1
                    )
                )
            )
            XCTFail("Expected oversized input to fail")
        } catch let error as MossFormer2VoiceCleaningError {
            XCTAssertEqual(
                error,
                .audioTooLong(
                    maximumSamples: MossFormer2VoiceCleaningRuntime.maximumAudioSamples,
                    actualSamples: MossFormer2VoiceCleaningRuntime.maximumAudioSamples + 1
                )
            )
        }
    }

    func testNativeModelCleansAudioOnMetalWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TEXTIFY_RUN_MOSSFORMER2_NATIVE_TESTS"] == "1",
              let modelDirectory = ProcessInfo.processInfo.environment["TEXTIFY_MOSSFORMER2_MODEL_DIRECTORY"],
              let variantName = ProcessInfo.processInfo.environment["TEXTIFY_MOSSFORMER2_VARIANT"],
              let variant = MossFormer2VoiceCleaningVariant(rawValue: variantName)
        else {
            throw XCTSkip(
                "Set TEXTIFY_RUN_MOSSFORMER2_NATIVE_TESTS=1, TEXTIFY_MOSSFORMER2_MODEL_DIRECTORY, and TEXTIFY_MOSSFORMER2_VARIANT to run the native Metal smoke."
            )
        }
        let runtime = MossFormer2VoiceCleaningRuntime()
        try await runtime.load(
            modelID: variant.rawValue,
            modelDirectory: modelDirectory,
            variant: variant
        )
        let output = try await runtime.clean(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.01, count: 16_000))
        )
        XCTAssertEqual(output.samples.count, 16_000)
        XCTAssertTrue(output.samples.allSatisfy(\.isFinite))
    }

    private static func makeModelDirectory(includeWeights: Bool = true) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Textify-MossFormer2Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"sample_rate\":48000}".utf8).write(
            to: directory.appendingPathComponent("config.json")
        )
        if includeWeights {
            try Data([0]).write(to: directory.appendingPathComponent("model.safetensors"))
        }
        return directory
    }
}

private actor FakeMossFormer2Session: MossFormer2VoiceCleaningSession {
    let backendName: String
    let sampleRate: Int
    private var counts: [Int] = []
    private var unloads = 0

    init(backendName: String = "mlx-metal", sampleRate: Int = 48_000) {
        self.backendName = backendName
        self.sampleRate = sampleRate
    }

    func enhance(samples: [Float]) -> [Float] {
        counts.append(samples.count)
        return samples.map { $0 * 0.5 }
    }

    func unload() {
        unloads += 1
    }

    func sampleCounts() -> [Int] {
        counts
    }

    func unloadCallCount() -> Int {
        unloads
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
