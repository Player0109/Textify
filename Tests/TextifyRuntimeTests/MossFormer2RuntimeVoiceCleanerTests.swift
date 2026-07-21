import TextifyModels
@testable import TextifyRuntime
import TextifyTranscription
import XCTest

final class MossFormer2RuntimeVoiceCleanerTests: XCTestCase {
    func testRejectsTranscriptionModelPurpose() async {
        let adapter = MossFormer2RuntimeVoiceCleaner(runtime: MossFormer2VoiceCleaningRuntime())
        let model = RuntimeActiveModel(
            id: "whisper",
            displayName: "Whisper",
            tier: "balanced",
            localModelPath: "/tmp/whisper.bin",
            useGPU: true,
            threadCount: nil
        )

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected transcription purpose to be rejected")
        } catch let error as RuntimeVoiceCleaningAdapterError {
            XCTAssertEqual(error, .wrongPurpose(.transcription))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsUnsupportedMossFormerVariant() async {
        let adapter = MossFormer2RuntimeVoiceCleaner(runtime: MossFormer2VoiceCleaningRuntime())
        let model = RuntimeActiveModel(
            id: "cleaner",
            displayName: "Cleaner",
            tier: "experimental",
            localModelPath: "/tmp/cleaner",
            useGPU: true,
            threadCount: nil,
            engine: .mlxAudio,
            variant: "different-cleaner",
            accelerator: .metalGPU,
            artifactLayout: .modelDirectory,
            runtimeParameters: .legacyEnglishWhisper,
            purpose: .voiceCleaning
        )

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected unsupported variant to be rejected")
        } catch let error as RuntimeVoiceCleaningAdapterError {
            XCTAssertEqual(error, .unsupportedVariant("different-cleaner"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
