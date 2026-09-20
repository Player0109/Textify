import Foundation
import TextifyModels
@testable import TextifyRuntime
import TextifyTranscription
import XCTest

final class ConfuciusRuntimeAdapterTests: XCTestCase {
    func testBothSignedVariantsPrepareStreamAndSwitchOnMetal() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let f16Path = environment["TEXTIFY_CONFUCIUS_SMOKE_F16_MODEL"],
              let q8Path = environment["TEXTIFY_CONFUCIUS_SMOKE_MODEL"],
              let library = environment["TEXTIFY_CONFUCIUS_SMOKE_LIBRARY"],
              let audioPath = environment["TEXTIFY_CONFUCIUS_SMOKE_AUDIO"] else {
            throw XCTSkip("Set the Confucius smoke paths, including F16, for native variant switching")
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try ModelManifest.decode(Data(contentsOf: root.appendingPathComponent("models/manifest.json")))
        let data = try Data(contentsOf: URL(fileURLWithPath: audioPath))
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let audio = TranscriptionAudioBuffer(samples: samples)
        let adapter = ConfuciusRuntimeTranscribingAdapter(runtime: ConfuciusRuntime(libraryPath: library))

        for (index, selection) in [
            ("confucius4-r2t2-f16", f16Path),
            ("confucius4-r2t2-q8_0", q8Path),
            ("confucius4-r2t2-f16", f16Path),
        ].enumerated() {
            let entry = try XCTUnwrap(manifest.models.first { $0.id == selection.0 })
            try await adapter.prepare(model: RuntimeActiveModel(
                id: entry.id, displayName: entry.displayName, tier: entry.tier,
                localModelPath: selection.1, useGPU: true, threadCount: nil,
                engine: entry.runtime.engine, variant: entry.runtime.variant,
                accelerator: entry.runtime.accelerator, artifactLayout: entry.runtime.artifactLayout,
                runtimeParameters: entry.runtimeParameters
            ))
            let readiness = await adapter.readiness
            let supportsPreview = await adapter.supportsLivePreview
            XCTAssertEqual(readiness, .ready(modelID: entry.id))
            XCTAssertTrue(supportsPreview)

            if index == 0 {
                let collector = ConfuciusPreviewCollector()
                let (stream, continuation) = AsyncStream<TranscriptionAudioBuffer>.makeStream()
                for offset in stride(from: 0, to: samples.count, by: 5_120) {
                    continuation.yield(TranscriptionAudioBuffer(
                        samples: Array(samples[offset..<min(offset + 5_120, samples.count)])
                    ))
                }
                continuation.finish()
                try await adapter.preview(chunks: stream) { await collector.receive($0) }
                let preview = await collector.text
                XCTAssertTrue(preview.lowercased().contains("mother nature"), preview)
            }

            let final = try await adapter.transcribe(audio)
            XCTAssertTrue(final.text.lowercased().contains("mother nature"), final.text)
            XCTAssertTrue(final.text.lowercased().contains("longer than you"), final.text)
        }
        await adapter.unload()
        let readiness = await adapter.readiness
        let supportsPreview = await adapter.supportsLivePreview
        XCTAssertEqual(readiness, .noActiveModel)
        XCTAssertFalse(supportsPreview)
    }
}

private actor ConfuciusPreviewCollector {
    var text = ""
    func receive(_ text: String) { self.text = text }
}
