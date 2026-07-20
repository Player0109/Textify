@testable import TextifyRuntime
import TextifyModels
import TextifyTranscription
import XCTest

final class LiteRTLMRuntimeAdapterTests: XCTestCase {
    func testAdapterPreparesExactEnglishSingleFileOnMetal() async throws {
        let runtime = FakeAdapterLiteRTLMRuntime()
        let adapter = LiteRTLMRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(model: Self.activeModel())

        let load = await runtime.loadSnapshot()
        XCTAssertEqual(load?.modelID, "gemma-4-12b-litertlm")
        XCTAssertEqual(load?.modelPath, "/tmp/gemma-4-12B-it.litertlm")
        XCTAssertEqual(load?.variant, .gemma4_12B)
        XCTAssertEqual(load?.languageCode, "en")
        XCTAssertEqual(load?.warmup, true)
        let readiness = await adapter.readiness
        XCTAssertEqual(readiness, .ready(modelID: "gemma-4-12b-litertlm"))
    }

    func testAdapterRejectsWrongAcceleratorAndLayout() async throws {
        let runtime = FakeAdapterLiteRTLMRuntime()
        let adapter = LiteRTLMRuntimeTranscribingAdapter(runtime: runtime)

        do {
            try await adapter.prepare(model: Self.activeModel(accelerator: .cpu))
            XCTFail("Expected CPU route to fail")
        } catch let error as RuntimeTranscriptionEngineError {
            XCTAssertEqual(
                error,
                .incompatibleAccelerator(engine: .liteRTLM, accelerator: .cpu)
            )
        }

        do {
            try await adapter.prepare(model: Self.activeModel(layout: .modelDirectory))
            XCTFail("Expected directory artifact to fail")
        } catch let error as RuntimeTranscriptionEngineError {
            XCTAssertEqual(
                error,
                .incompatibleArtifactLayout(
                    engine: .liteRTLM,
                    artifactLayout: .modelDirectory
                )
            )
        }
        let load = await runtime.loadSnapshot()
        XCTAssertNil(load)
    }

    private static func activeModel(
        accelerator: ModelAccelerator = .metalGPU,
        layout: ModelArtifactLayout = .singleFile
    ) -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "gemma-4-12b-litertlm",
            displayName: "Experimental - Gemma 4 12B",
            tier: "experimental",
            localModelPath: "/tmp/gemma-4-12B-it.litertlm",
            useGPU: true,
            threadCount: nil,
            engine: .liteRTLM,
            variant: LiteRTLMModelVariant.gemma4_12B.rawValue,
            accelerator: accelerator,
            artifactLayout: layout,
            runtimeParameters: RuntimeParameters(
                language: "en",
                detectLanguage: false,
                translate: false,
                strategy: "greedy",
                beamSize: 1,
                bestOf: 1,
                temperature: 0,
                temperatureFallback: [],
                noContext: true,
                tokenTimestamps: false,
                maxAudioSeconds: 30
            )
        )
    }
}

private actor FakeAdapterLiteRTLMRuntime: LiteRTLMRuntimeLoading {
    private var mutableState: LiteRTLMRuntimeState = .noModel
    private var load: Load?

    var state: LiteRTLMRuntimeState {
        mutableState
    }

    func load(
        modelID: String,
        modelPath: String,
        variant: LiteRTLMModelVariant,
        languageCode: String,
        warmup: Bool
    ) {
        load = Load(
            modelID: modelID,
            modelPath: modelPath,
            variant: variant,
            languageCode: languageCode,
            warmup: warmup
        )
        mutableState = .ready(modelID: modelID)
    }

    func transcribe(_ audio: TranscriptionAudioBuffer) -> TranscriptionResult {
        TranscriptionResult(
            text: "local Gemma",
            noSpeechProbability: 0,
            averageLogProbability: 0,
            compressionRatio: 1
        )
    }

    func unload() {
        mutableState = .noModel
    }

    func loadSnapshot() -> Load? {
        load
    }

    struct Load: Sendable {
        let modelID: String
        let modelPath: String
        let variant: LiteRTLMModelVariant
        let languageCode: String
        let warmup: Bool
    }
}
