import Foundation
import XCTest
@testable import TextifyTranscription

final class ConfuciusRuntimeTests: XCTestCase {
    func testMissingBundledRuntimeFailsClosed() async {
        let runtime = ConfuciusRuntime(libraryPath: "/missing/Confucius.dylib")
        do {
            try await runtime.load(modelPath: "/missing/model.gguf")
            XCTFail("Missing runtime must not become ready")
        } catch {
            XCTAssertEqual(error as? ConfuciusRuntimeError, .unavailable)
        }
        await runtime.unload()
    }

    func testNonCanonicalAudioIsRejectedBeforeInference() async {
        let runtime = ConfuciusRuntime(libraryPath: "/missing/Confucius.dylib")
        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(sampleRate: 48_000, samples: [0.1]),
                language: "English"
            )
            XCTFail("Wrong sample rate must not reach native inference")
        } catch {
            XCTAssertEqual(error as? ConfuciusRuntimeError, .invalidAudio)
        }
    }

    func testNativeMetalPreviewAndFinalPassOnPublicFixture() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let model = environment["TEXTIFY_CONFUCIUS_SMOKE_MODEL"],
              let library = environment["TEXTIFY_CONFUCIUS_SMOKE_LIBRARY"],
              let audio = environment["TEXTIFY_CONFUCIUS_SMOKE_AUDIO"] else {
            throw XCTSkip("Set the three TEXTIFY_CONFUCIUS_SMOKE paths for the native Metal smoke")
        }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: audio))
        let samples = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let runtime = ConfuciusRuntime(libraryPath: library)
        try await runtime.load(modelPath: model)
        let updates = PreviewTextCollector()
        let (stream, continuation) = AsyncStream<TranscriptionAudioBuffer>.makeStream()
        // Cross the 25-second preview reset and continue producing text.
        let previewSamples = samples + samples + samples
        for offset in stride(from: 0, to: previewSamples.count, by: 5_120) {
            continuation.yield(TranscriptionAudioBuffer(
                samples: Array(previewSamples[offset..<min(offset + 5_120, previewSamples.count)])
            ))
        }
        continuation.finish()
        try await runtime.preview(chunks: stream, language: "English") { text in
            await updates.receive(text)
        }
        let preview = await updates.text
        XCTAssertGreaterThanOrEqual(preview.components(separatedBy: "nature").count - 1, 3, preview)
        let final = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: samples), language: "English"
        )
        XCTAssertTrue(final.text.contains("22,500 times longer than you"), final.text)
        await runtime.unload()
        do {
            _ = try await runtime.transcribe(TranscriptionAudioBuffer(samples: samples), language: "English")
            XCTFail("Unloaded runtime must reject inference")
        } catch {
            XCTAssertEqual(error as? ConfuciusRuntimeError, .unavailable)
        }
    }
}

private actor PreviewTextCollector {
    var text = ""
    func receive(_ text: String) { self.text = text }
}
