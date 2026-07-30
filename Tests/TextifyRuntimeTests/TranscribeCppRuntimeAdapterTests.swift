import TextifyModels
@testable import TextifyRuntime
import TextifyTranscription
import XCTest

final class TranscribeCppRuntimeAdapterTests: XCTestCase {
    func testAdapterPreparesExplicitPromotedLanguageOnMetalAndCapsThreads() async throws {
        let runtime = FakeTranscribeCppRuntime()
        let adapter = TranscribeCppRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(model: Self.activeModel(language: "vi-VN", threadCount: 12))

        let load = await runtime.loadSnapshot()
        XCTAssertEqual(load?.modelID, "funasr-mlt-nano-2512-q8")
        XCTAssertEqual(load?.modelPath, "/tmp/Fun-ASR-MLT-Nano-2512-Q8_0.gguf")
        XCTAssertEqual(load?.variant, .funASRMLTNanoQ8)
        XCTAssertEqual(load?.languageCode, "vi")
        XCTAssertEqual(load?.threadCount, 4)
        XCTAssertEqual(load?.warmup, true)
        let readiness = await adapter.readiness
        XCTAssertEqual(readiness, .ready(modelID: "funasr-mlt-nano-2512-q8"))
    }

    func testAdapterRejectsAutomaticLanguageDetectionForExplicitLanguageVariant() async {
        let runtime = FakeTranscribeCppRuntime()
        let adapter = TranscribeCppRuntimeTranscribingAdapter(runtime: runtime)
        let model = Self.activeModel(detectLanguage: true)

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected automatic language detection to fail")
        } catch let error as TranscribeCppRuntimeError {
            XCTAssertEqual(error, .automaticLanguageDetectionUnsupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let load = await runtime.loadSnapshot()
        XCTAssertNil(load)
    }

    func testAdapterPreparesQwen3ASRVariantsWithAutomaticLanguageDetection() async throws {
        for (id, filename, variant) in [
            (
                "qwen3-asr-0.6b-q8-0",
                "Qwen3-ASR-0.6B-Q8_0.gguf",
                TranscribeCppModelVariant.qwen3ASR0_6B
            ),
            (
                "qwen3-asr-1.7b-q8-0",
                "Qwen3-ASR-1.7B-Q8_0.gguf",
                TranscribeCppModelVariant.qwen3ASR1_7B
            ),
        ] {
            let runtime = FakeTranscribeCppRuntime()
            let adapter = TranscribeCppRuntimeTranscribingAdapter(runtime: runtime)

            try await adapter.prepare(
                model: Self.activeModel(
                    id: id,
                    modelPath: "/tmp/\(filename)",
                    variant: variant,
                    language: "auto",
                    detectLanguage: true
                )
            )

            let load = await runtime.loadSnapshot()
            XCTAssertEqual(load?.modelID, id)
            XCTAssertEqual(load?.modelPath, "/tmp/\(filename)")
            XCTAssertEqual(load?.variant, variant)
            XCTAssertEqual(load?.languageCode, "auto")
        }
    }

    func testAdapterPreparesExplicitLanguageForMultilingualQwen() async throws {
        let runtime = FakeTranscribeCppRuntime()
        let adapter = TranscribeCppRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(
            model: Self.activeModel(
                id: "qwen3-asr-1.7b-q8-0",
                modelPath: "/tmp/Qwen3-ASR-1.7B-Q8_0.gguf",
                variant: .qwen3ASR1_7B,
                language: "en",
                detectLanguage: false
            )
        )

        let load = await runtime.loadSnapshot()
        XCTAssertEqual(load?.languageCode, "en")
    }

    func testAdapterPreparesParakeetTDTAndNemotronVariants() async throws {
        let candidates: [(String, TranscribeCppModelVariant, String, Bool)] = [
            ("parakeet-tdt-0.6b-v2-q8-0", .parakeetTDT0_6BV2, "en", false),
            ("parakeet-tdt-0.6b-v3-q8-0", .parakeetTDT0_6BV3, "auto", true),
            ("nemotron-3.5-asr-streaming-0.6b-q8-0", .nemotron3_5ASRStreaming0_6B, "auto", true),
        ]
        for (id, variant, language, detectLanguage) in candidates {
            let runtime = FakeTranscribeCppRuntime()
            let adapter = TranscribeCppRuntimeTranscribingAdapter(runtime: runtime)
            try await adapter.prepare(
                model: Self.activeModel(
                    id: id,
                    modelPath: "/tmp/\(id).gguf",
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

    func testAdapterPreparesArticleModelVariantsWithAutomaticLanguageDetection() async throws {
        let candidates: [(String, TranscribeCppModelVariant)] = [
            ("granite-speech-4.1-2b-q5-k-m", .graniteSpeech4_1_2B),
            ("granite-speech-4.1-2b-nar-q5-k-m", .graniteSpeech4_1_2BNAR),
            ("voxtral-mini-4b-realtime-2602-q4-k-m", .voxtralMini4BRealtime2602),
            ("moss-transcribe-diarize-0.9b-q5-k-m", .mossTranscribeDiarize0_9B),
        ]
        for (id, variant) in candidates {
            let runtime = FakeTranscribeCppRuntime()
            let adapter = TranscribeCppRuntimeTranscribingAdapter(runtime: runtime)

            try await adapter.prepare(
                model: Self.activeModel(
                    id: id,
                    modelPath: "/tmp/\(id).gguf",
                    variant: variant,
                    language: "auto",
                    detectLanguage: true
                )
            )

            let load = await runtime.loadSnapshot()
            XCTAssertEqual(load?.modelID, id)
            XCTAssertEqual(load?.variant, variant)
            XCTAssertEqual(load?.languageCode, "auto")
        }
    }

    func testAdapterPreparesExactCanaryEnglishVariant() async throws {
        let runtime = FakeTranscribeCppRuntime()
        let adapter = TranscribeCppRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(
            model: Self.activeModel(
                id: "canary-qwen-2.5b-q4-k-m",
                modelPath: "/tmp/canary-qwen-2.5b-Q4_K_M.gguf",
                variant: .canaryQwen2_5B,
                maxAudioSeconds: 40
            )
        )

        let load = await runtime.loadSnapshot()
        XCTAssertEqual(load?.modelID, "canary-qwen-2.5b-q4-k-m")
        XCTAssertEqual(load?.modelPath, "/tmp/canary-qwen-2.5b-Q4_K_M.gguf")
        XCTAssertEqual(load?.variant, .canaryQwen2_5B)
        XCTAssertEqual(load?.languageCode, "en")
    }

    func testAdapterRejectsUnpromotedLanguage() async {
        let runtime = FakeTranscribeCppRuntime()
        let adapter = TranscribeCppRuntimeTranscribingAdapter(runtime: runtime)

        do {
            try await adapter.prepare(model: Self.activeModel(language: "hi"))
            XCTFail("Expected unpromoted language to fail")
        } catch let error as TranscribeCppRuntimeError {
            XCTAssertEqual(error, .unsupportedLanguage("hi"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAdapterRejectsCPUCatalogRoute() async {
        let runtime = FakeTranscribeCppRuntime()
        let adapter = TranscribeCppRuntimeTranscribingAdapter(runtime: runtime)
        let model = Self.activeModel(accelerator: .cpu)

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected CPU route to fail")
        } catch let error as RuntimeTranscriptionEngineError {
            XCTAssertEqual(
                error,
                .incompatibleAccelerator(engine: .transcribeCpp, accelerator: .cpu)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func activeModel(
        id: String = "funasr-mlt-nano-2512-q8",
        modelPath: String = "/tmp/Fun-ASR-MLT-Nano-2512-Q8_0.gguf",
        variant: TranscribeCppModelVariant = .funASRMLTNanoQ8,
        language: String = "en",
        detectLanguage: Bool = false,
        threadCount: Int? = 4,
        accelerator: ModelAccelerator = .metalGPU,
        maxAudioSeconds: Int = 60
    ) -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: id,
            displayName: "Specialist - Fun-ASR Multilingual",
            tier: "specialist",
            localModelPath: modelPath,
            useGPU: true,
            threadCount: threadCount,
            engine: .transcribeCpp,
            variant: variant.rawValue,
            accelerator: accelerator,
            artifactLayout: .singleFile,
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

private actor FakeTranscribeCppRuntime: TranscribeCppRuntimeLoading {
    struct Load {
        let modelID: String
        let modelPath: String
        let variant: TranscribeCppModelVariant
        let languageCode: String
        let threadCount: Int
        let warmup: Bool
    }

    private var mutableState: TranscribeCppRuntimeState = .noModel
    private var load: Load?

    var state: TranscribeCppRuntimeState {
        mutableState
    }

    func load(
        modelID: String,
        modelPath: String,
        variant: TranscribeCppModelVariant,
        languageCode: String,
        threadCount: Int,
        warmup: Bool
    ) {
        load = Load(
            modelID: modelID,
            modelPath: modelPath,
            variant: variant,
            languageCode: languageCode,
            threadCount: threadCount,
            warmup: warmup
        )
        mutableState = .ready(modelID: modelID)
    }

    func transcribe(_: TranscriptionAudioBuffer) -> TranscriptionResult {
        TranscriptionResult(
            text: "Fast local transcription",
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
}
