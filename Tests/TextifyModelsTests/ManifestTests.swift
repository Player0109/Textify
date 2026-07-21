import Foundation
import TextifyModels
import XCTest

final class ManifestTests: XCTestCase {
    private static func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }

    private static var validManifestData: Data {
        get throws {
            try fixtureData("manifest.json")
        }
    }

    private static var validManifestJSONWithUnknownField: String {
        get throws {
            String(decoding: try fixtureData("manifest_unknown_field.json"), as: UTF8.self)
        }
    }

    func testManifestParsesInitialCuratedModelShape() throws {
        let manifest = try ModelManifest.decode(try Self.validManifestData)
        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.models.first?.id, ProductionModelPolicy.requiredModelID)
        XCTAssertEqual(manifest.models.first?.runtimeParameters.language, "en")
        XCTAssertEqual(manifest.models.first?.runtimeParameters.temperatureFallback, [])
        XCTAssertEqual(manifest.models.first?.runtime, .legacyWhisper)
        XCTAssertEqual(manifest.models.first?.capabilities, .legacyEnglishWhisper)
        XCTAssertEqual(manifest.models.first?.purpose, .transcription)
    }

    func testManifestParsesVoiceCleaningPurpose() throws {
        let manifest = try voiceCleaningManifest(
            engine: "mlx_audio",
            accelerator: "metal_gpu",
            artifactLayout: "model_directory"
        )

        XCTAssertEqual(manifest.models.first?.purpose, .voiceCleaning)
        XCTAssertNoThrow(try ProductionModelPolicy.validateProductionManifest(manifest))
    }

    func testProductionPolicyRejectsVoiceCleanerOnTranscriptionRuntime() throws {
        let manifest = try voiceCleaningManifest(
            engine: "whisper_cpp",
            accelerator: "metal_gpu",
            artifactLayout: "single_file"
        )

        XCTAssertThrowsError(try ProductionModelPolicy.validateProductionManifest(manifest)) { error in
            XCTAssertEqual(
                error as? ProductionModelPolicyError,
                .incompatibleRuntime(modelID: ProductionModelPolicy.requiredModelID)
            )
        }
    }

    func testManifestParsesExplicitEngineAndCapabilities() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Self.validManifestData) as? [String: Any]
        )
        var models = try XCTUnwrap(json["models"] as? [[String: Any]])
        models[0]["runtime"] = [
            "engine": "fluid_audio_parakeet",
            "variant": "parakeet-tdt-0.6b-v3",
            "accelerator": "coreml_neural_engine",
            "artifactLayout": "model_directory"
        ]
        models[0]["capabilities"] = [
            "languages": ["en", "es", "de", "fr"],
            "supportsTranslation": false,
            "supportsCustomVocabulary": false
        ]
        models[0]["presentation"] = [
            "expectedFinalization": "Usually under 100 ms after release",
            "accuracyTradeoff": "Strong multilingual accuracy with a larger download",
            "requirements": "Apple Silicon with Core ML Neural Engine support"
        ]
        json["models"] = models

        let manifest = try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
        let model = try XCTUnwrap(manifest.models.first)

        XCTAssertEqual(model.runtime.engine, .fluidAudioParakeet)
        XCTAssertEqual(model.runtime.variant, "parakeet-tdt-0.6b-v3")
        XCTAssertEqual(model.runtime.accelerator, .coreMLNeuralEngine)
        XCTAssertEqual(model.runtime.artifactLayout, .modelDirectory)
        XCTAssertEqual(model.capabilities.languages, ["en", "es", "de", "fr"])
        XCTAssertEqual(
            model.presentation?.expectedFinalization,
            "Usually under 100 ms after release"
        )
    }

    func testManifestParsesParaformerEngine() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Self.validManifestData) as? [String: Any]
        )
        var models = try XCTUnwrap(json["models"] as? [[String: Any]])
        models[0]["runtime"] = [
            "engine": "fluid_audio_paraformer",
            "variant": "paraformer-large-zh-int8",
            "accelerator": "coreml_neural_engine",
            "artifactLayout": "model_directory"
        ]
        models[0]["capabilities"] = [
            "languages": ["zh"],
            "supportsTranslation": false,
            "supportsCustomVocabulary": false
        ]
        json["models"] = models

        let manifest = try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
        let model = try XCTUnwrap(manifest.models.first)

        XCTAssertEqual(model.runtime.engine, .fluidAudioParaformer)
        XCTAssertEqual(model.runtime.variant, "paraformer-large-zh-int8")
        XCTAssertEqual(model.capabilities.languages, ["zh"])
    }

    func testManifestParsesSherpaOnnxCPUDescriptor() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Self.validManifestData) as? [String: Any]
        )
        var models = try XCTUnwrap(json["models"] as? [[String: Any]])
        models[0]["runtime"] = [
            "engine": "sherpa_onnx",
            "variant": "reazonspeech-k2-v2",
            "accelerator": "cpu",
            "artifactLayout": "model_directory"
        ]
        models[0]["capabilities"] = [
            "languages": ["ja"],
            "supportsTranslation": false,
            "supportsCustomVocabulary": false
        ]
        json["models"] = models

        let manifest = try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
        let model = try XCTUnwrap(manifest.models.first)

        XCTAssertEqual(model.runtime.engine, .sherpaOnnx)
        XCTAssertEqual(model.runtime.variant, "reazonspeech-k2-v2")
        XCTAssertEqual(model.runtime.accelerator, .cpu)
        XCTAssertEqual(model.capabilities.languages, ["ja"])
    }

    func testProductionPolicyRejectsNonPositiveMaximumAudioDuration() throws {
        let manifest = try manifestWithRuntime(
            engine: "whisper_cpp",
            variant: "whisper-small-en-q5_1",
            accelerator: "metal_gpu",
            artifactLayout: "single_file",
            maximumAudioSeconds: 0
        )

        XCTAssertThrowsError(try ProductionModelPolicy.validateProductionManifest(manifest)) { error in
            XCTAssertEqual(
                error as? ProductionModelPolicyError,
                .invalidRuntimeParameters(modelID: ProductionModelPolicy.requiredModelID)
            )
        }
    }

    func testProductionPolicyRejectsParaformerCaptureWindowThatCanTruncate() throws {
        let manifest = try manifestWithRuntime(
            engine: "fluid_audio_paraformer",
            variant: "paraformer-large-zh-int8",
            accelerator: "coreml_neural_engine",
            artifactLayout: "model_directory",
            maximumAudioSeconds: 30
        )

        XCTAssertThrowsError(try ProductionModelPolicy.validateProductionManifest(manifest)) { error in
            XCTAssertEqual(
                error as? ProductionModelPolicyError,
                .invalidRuntimeParameters(modelID: ProductionModelPolicy.requiredModelID)
            )
        }
    }

    func testProductionPolicyAcceptsCommitPinnedHuggingFaceModelFile() throws {
        let url = "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/aed02740059203c4a87495924f685de3722ae9ce/parakeet_vocab.json"
        let manifest = try manifestReplacingModelFileURL(url)

        XCTAssertNoThrow(try ProductionModelPolicy.validateProductionManifest(manifest))
    }

    func testProductionPolicyRejectsMutableHuggingFaceModelFile() throws {
        let url = "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/main/parakeet_vocab.json"
        let manifest = try manifestReplacingModelFileURL(url)

        XCTAssertThrowsError(try ProductionModelPolicy.validateProductionManifest(manifest)) { error in
            XCTAssertEqual(
                error as? ProductionModelPolicyError,
                .invalidModelFileURL(
                    modelID: ProductionModelPolicy.requiredModelID,
                    url: url
                )
            )
        }
    }

    func testProductionPolicyRejectsInvalidGeneratedAt() throws {
        let manifest = try manifestReplacingGeneratedAt("not-a-timestamp")

        XCTAssertThrowsError(try ProductionModelPolicy.validateProductionManifest(manifest)) { error in
            XCTAssertEqual(
                error as? ProductionModelPolicyError,
                .invalidGeneratedAt("not-a-timestamp")
            )
        }
    }

    func testUnknownFieldsAreRejected() throws {
        let data = Data((try Self.validManifestJSONWithUnknownField).utf8)
        XCTAssertThrowsError(try ModelManifest.decode(data))
    }

    func testMinimumAppVersionComparisonUsesSemanticComponents() {
        XCTAssertTrue(ProductionModelPolicy.appVersion("1.2.0", satisfiesMinimum: "1.1.9"))
        XCTAssertTrue(ProductionModelPolicy.appVersion("1.1.0", satisfiesMinimum: "1.1.0"))
        XCTAssertFalse(ProductionModelPolicy.appVersion("1.1.9", satisfiesMinimum: "1.2.0"))
        XCTAssertFalse(ProductionModelPolicy.appVersion("1.2", satisfiesMinimum: "1.1.0"))
    }

    private func manifestWithRuntime(
        engine: String,
        variant: String,
        accelerator: String,
        artifactLayout: String,
        maximumAudioSeconds: Int
    ) throws -> ModelManifest {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Self.validManifestData) as? [String: Any]
        )
        var models = try XCTUnwrap(json["models"] as? [[String: Any]])
        models[0]["runtime"] = [
            "engine": engine,
            "variant": variant,
            "accelerator": accelerator,
            "artifactLayout": artifactLayout
        ]
        var runtimeParameters = try XCTUnwrap(models[0]["runtimeParameters"] as? [String: Any])
        runtimeParameters["maxAudioSeconds"] = maximumAudioSeconds
        models[0]["runtimeParameters"] = runtimeParameters
        json["models"] = models
        return try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
    }

    private func manifestReplacingModelFileURL(_ url: String) throws -> ModelManifest {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Self.validManifestData) as? [String: Any]
        )
        var models = try XCTUnwrap(json["models"] as? [[String: Any]])
        var files = try XCTUnwrap(models[0]["files"] as? [[String: Any]])
        files[0]["url"] = url
        models[0]["files"] = files
        json["models"] = models
        return try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
    }

    private func manifestReplacingGeneratedAt(_ generatedAt: String) throws -> ModelManifest {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Self.validManifestData) as? [String: Any]
        )
        json["generatedAt"] = generatedAt
        return try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
    }

    private func voiceCleaningManifest(
        engine: String,
        accelerator: String,
        artifactLayout: String
    ) throws -> ModelManifest {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Self.validManifestData) as? [String: Any]
        )
        var models = try XCTUnwrap(json["models"] as? [[String: Any]])
        models[0]["purpose"] = "voice_cleaning"
        models[0]["runtime"] = [
            "engine": engine,
            "variant": "mossformer2-se-fp16",
            "accelerator": accelerator,
            "artifactLayout": artifactLayout
        ]
        models[0]["capabilities"] = [
            "languages": ["*"],
            "supportsTranslation": false,
            "supportsCustomVocabulary": false
        ]
        if artifactLayout == "model_directory" {
            var files = try XCTUnwrap(models[0]["files"] as? [[String: Any]])
            files[0]["relativePath"] = files[0]["filename"]
            models[0]["files"] = files
        }
        json["models"] = models
        return try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
    }
}
