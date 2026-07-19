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

    func testAdapterRejectsAutomaticLanguageDetection() async {
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
        language: String = "en",
        detectLanguage: Bool = false,
        threadCount: Int? = 4,
        accelerator: ModelAccelerator = .metalGPU
    ) -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "funasr-mlt-nano-2512-q8",
            displayName: "Specialist - Fun-ASR Multilingual",
            tier: "specialist",
            localModelPath: "/tmp/Fun-ASR-MLT-Nano-2512-Q8_0.gguf",
            useGPU: true,
            threadCount: threadCount,
            engine: .transcribeCpp,
            variant: TranscribeCppModelVariant.funASRMLTNanoQ8.rawValue,
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
                maxAudioSeconds: 60
            )
        )
    }
}

private actor FakeTranscribeCppRuntime: TranscribeCppRuntimeLoading {
    struct Load: Sendable {
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

    func transcribe(_ audio: TranscriptionAudioBuffer) -> TranscriptionResult {
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
