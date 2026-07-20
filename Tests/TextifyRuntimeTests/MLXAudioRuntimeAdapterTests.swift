import TextifyModels
@testable import TextifyRuntime
import TextifyTranscription
import XCTest

final class MLXAudioRuntimeAdapterTests: XCTestCase {
    func testAdapterPreparesExactEnglishDirectoryModelOnMetal() async throws {
        let runtime = FakeAdapterMLXAudioRuntime()
        let adapter = MLXAudioRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(model: Self.activeModel())

        let load = await runtime.loadSnapshot()
        XCTAssertEqual(load?.modelID, "parakeet-rnnt-1.1b")
        XCTAssertEqual(load?.modelDirectory, "/tmp/parakeet-rnnt-1.1b")
        XCTAssertEqual(load?.variant, .parakeetRNNT1_1B)
        XCTAssertEqual(load?.languageCode, "en")
        XCTAssertEqual(load?.warmup, true)
        let readiness = await adapter.readiness
        XCTAssertEqual(readiness, .ready(modelID: "parakeet-rnnt-1.1b"))
    }

    func testAdapterRejectsNonMetalCatalogRoute() async throws {
        let runtime = FakeAdapterMLXAudioRuntime()
        let adapter = MLXAudioRuntimeTranscribingAdapter(runtime: runtime)
        let model = Self.activeModel(accelerator: .cpu)

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected a CPU MLX catalog route to fail")
        } catch let error as RuntimeTranscriptionEngineError {
            XCTAssertEqual(
                error,
                .incompatibleAccelerator(engine: .mlxAudio, accelerator: .cpu)
            )
        }
        let load = await runtime.loadSnapshot()
        XCTAssertNil(load)
    }

    func testAdapterPreparesExactCohereDirectoryModelOnMetal() async throws {
        let runtime = FakeAdapterMLXAudioRuntime()
        let adapter = MLXAudioRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(
            model: Self.activeModel(
                id: "cohere-transcribe-03-2026-mlx-8bit",
                variant: .cohereTranscribe03_2026,
                maxAudioSeconds: 30
            )
        )

        let load = await runtime.loadSnapshot()
        XCTAssertEqual(load?.modelID, "cohere-transcribe-03-2026-mlx-8bit")
        XCTAssertEqual(
            load?.modelDirectory,
            "/tmp/cohere-transcribe-03-2026-mlx-8bit"
        )
        XCTAssertEqual(load?.variant, .cohereTranscribe03_2026)
        XCTAssertEqual(load?.languageCode, "en")
        XCTAssertEqual(load?.warmup, true)
    }

    func testAdapterPreparesExactWhisperTurboDirectoryModelOnMetal() async throws {
        let runtime = FakeAdapterMLXAudioRuntime()
        let adapter = MLXAudioRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(
            model: Self.activeModel(
                id: "whisper-large-v3-turbo-mlx",
                variant: .whisperLargeV3Turbo
            )
        )

        let load = await runtime.loadSnapshot()
        XCTAssertEqual(load?.modelID, "whisper-large-v3-turbo-mlx")
        XCTAssertEqual(load?.modelDirectory, "/tmp/whisper-large-v3-turbo-mlx")
        XCTAssertEqual(load?.variant, .whisperLargeV3Turbo)
        XCTAssertEqual(load?.languageCode, "en")
        XCTAssertEqual(load?.warmup, true)
    }

    func testAdapterRejectsAutomaticLanguageDetectionForEnglishOnlyVariant() async throws {
        let runtime = FakeAdapterMLXAudioRuntime()
        let adapter = MLXAudioRuntimeTranscribingAdapter(runtime: runtime)
        let model = Self.activeModel(detectLanguage: true)

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected automatic language detection to fail")
        } catch let error as MLXAudioRuntimeError {
            XCTAssertEqual(error, .automaticLanguageDetectionUnsupported)
        }
        let load = await runtime.loadSnapshot()
        XCTAssertNil(load)
    }

    func testAdapterPreparesQwen3ASRVariantsWithAutomaticLanguageDetection() async throws {
        for (id, variant) in [
            ("qwen3-asr-0.6b-mlx-8bit", MLXAudioModelVariant.qwen3ASR0_6B8Bit),
            ("qwen3-asr-1.7b-mlx-8bit", MLXAudioModelVariant.qwen3ASR1_7B8Bit),
        ] {
            let runtime = FakeAdapterMLXAudioRuntime()
            let adapter = MLXAudioRuntimeTranscribingAdapter(runtime: runtime)

            try await adapter.prepare(
                model: Self.activeModel(
                    id: id,
                    variant: variant,
                    language: "auto",
                    detectLanguage: true
                )
            )

            let load = await runtime.loadSnapshot()
            XCTAssertEqual(load?.modelID, id)
            XCTAssertEqual(load?.modelDirectory, "/tmp/\(id)")
            XCTAssertEqual(load?.variant, variant)
            XCTAssertEqual(load?.languageCode, "auto")
            XCTAssertEqual(load?.warmup, true)
        }
    }

    func testAdapterPreparesParakeetTDTAndNemotronVariants() async throws {
        let candidates: [(String, MLXAudioModelVariant, String, Bool)] = [
            ("parakeet-tdt-0.6b-v2-mlx", .parakeetTDT0_6BV2, "en", false),
            ("parakeet-tdt-0.6b-v3-mlx", .parakeetTDT0_6BV3, "auto", true),
            ("nemotron-3.5-asr-streaming-0.6b-mlx", .nemotron3_5ASRStreaming0_6B, "auto", true),
        ]
        for (id, variant, language, detectLanguage) in candidates {
            let runtime = FakeAdapterMLXAudioRuntime()
            let adapter = MLXAudioRuntimeTranscribingAdapter(runtime: runtime)
            try await adapter.prepare(
                model: Self.activeModel(
                    id: id,
                    variant: variant,
                    language: language,
                    detectLanguage: detectLanguage
                )
            )

            let load = await runtime.loadSnapshot()
            XCTAssertEqual(load?.modelID, id)
            XCTAssertEqual(load?.variant, variant)
            XCTAssertEqual(load?.languageCode, language)
        }
    }

    private static func activeModel(
        id: String = "parakeet-rnnt-1.1b",
        variant: MLXAudioModelVariant = .parakeetRNNT1_1B,
        accelerator: ModelAccelerator = .metalGPU,
        language: String = "en",
        detectLanguage: Bool = false,
        maxAudioSeconds: Int = 60
    ) -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: id,
            displayName: "Experimental - Parakeet RNNT 1.1B",
            tier: "experimental",
            localModelPath: "/tmp/\(id)",
            useGPU: true,
            threadCount: nil,
            engine: .mlxAudio,
            variant: variant.rawValue,
            accelerator: accelerator,
            artifactLayout: .modelDirectory,
            runtimeParameters: RuntimeParameters(
                language: language,
                detectLanguage: detectLanguage,
                translate: false,
                strategy: "greedy",
                beamSize: 1,
                bestOf: 1,
                temperature: 0,
                temperatureFallback: [],
                noContext: true,
                tokenTimestamps: false,
                maxAudioSeconds: maxAudioSeconds
            )
        )
    }
}

private actor FakeAdapterMLXAudioRuntime: MLXAudioRuntimeLoading {
    private var mutableState: MLXAudioRuntimeState = .noModel
    private var load: Load?

    var state: MLXAudioRuntimeState {
        mutableState
    }

    func load(
        modelID: String,
        modelDirectory: String,
        variant: MLXAudioModelVariant,
        languageCode: String,
        warmup: Bool
    ) {
        load = Load(
            modelID: modelID,
            modelDirectory: modelDirectory,
            variant: variant,
            languageCode: languageCode,
            warmup: warmup
        )
        mutableState = .ready(modelID: modelID)
    }

    func transcribe(_: TranscriptionAudioBuffer) -> TranscriptionResult {
        TranscriptionResult(
            text: "local RNNT",
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

    struct Load {
        let modelID: String
        let modelDirectory: String
        let variant: MLXAudioModelVariant
        let languageCode: String
        let warmup: Bool
    }
}
