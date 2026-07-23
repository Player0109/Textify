@testable import Textify
import Foundation
import TextifyModels
import TextifyTranscription
import XCTest

final class BenchmarkModelCatalogTests: XCTestCase {
    func testSignedCatalogPublishesDirectScoreRatingsForModelPage() throws {
        let manifest = try verifiedManifest()
        let ratedModels = manifest.models.filter { $0.benchmark != nil }
        let unratedModelIDs = Set(
            manifest.models.filter { $0.benchmark == nil }.map(\.id)
        )

        XCTAssertEqual(manifest.manifestVersion, 2)
        XCTAssertEqual(ratedModels.count, 31)
        XCTAssertEqual(
            unratedModelIDs,
            [
                "canary-qwen-2.5b-q4-k-m",
                "parakeet-ja",
                "paraformer-large-zh-int8",
                "reazonspeech-k2-v2-int8",
                "mossformer2-se-fp32",
                "mossformer2-se-fp16",
                "mossformer2-se-int8",
                "granite-speech-4.1-2b-q5-k-m",
                "granite-speech-4.1-2b-nar-q5-k-m",
                "voxtral-mini-4b-realtime-2602-q4-k-m",
                "moss-transcribe-diarize-0.9b-q5-k-m",
                "omnilingual-asr-300m-ctc-int8",
            ]
        )

        for model in manifest.models {
            let presentation = ProductionModelPresentation(model: model)
            guard let benchmark = model.benchmark else {
                XCTAssertNil(presentation.qualityScore)
                XCTAssertNil(presentation.speedScore)
                XCTAssertEqual(presentation.qualityLabel, "Unrated")
                XCTAssertEqual(presentation.speedLabel, "Unrated")
                continue
            }

            let expectedQualityLevel = switch benchmark.quality.score {
            case 90...: 5
            case 75...: 4
            case 60...: 3
            case 40...: 2
            default: 1
            }
            XCTAssertEqual(benchmark.quality.level, expectedQualityLevel, model.id)
            XCTAssertEqual(presentation.qualityScore, benchmark.quality.score, model.id)
            XCTAssertEqual(presentation.qualitySignalLevel, expectedQualityLevel, model.id)
            XCTAssertEqual(presentation.speedScore, benchmark.speed?.score, model.id)
            XCTAssertEqual(presentation.speedSignalLevel, benchmark.speed?.level ?? 0, model.id)
        }

        let parakeet = try XCTUnwrap(
            manifest.models.first { $0.id == "parakeet-tdt-0.6b-v3-mlx" }
        )
        let presentation = ProductionModelPresentation(model: parakeet)
        XCTAssertEqual(presentation.qualityScore, 93)
        XCTAssertEqual(presentation.qualityLabel, "Highest")
        XCTAssertEqual(presentation.qualitySignalLevel, 5)
        XCTAssertEqual(presentation.speedScore, 100)
        XCTAssertEqual(presentation.speedLabel, "Fastest")
        XCTAssertEqual(presentation.speedSignalLevel, 5)
    }

    func testRequestedWhisperLargeModelsUsePinnedLocalMetalArtifacts() throws {
        let manifest = try verifiedManifest()

        let expected: [String: (filename: String, sizeBytes: Int64, sha256: String)] = [
            "whisper-large-v2-q5_0": (
                "ggml-large-v2-q5_0.bin",
                1_080_732_091,
                "3a214837221e4530dbc1fe8d734f302af393eb30bd0ed046042ebf4baf70f6f2"
            ),
            "whisper-large-v3-q5_0": (
                "ggml-large-v3-q5_0.bin",
                1_081_140_203,
                "d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1"
            ),
        ]

        for (modelID, artifact) in expected {
            let model = try XCTUnwrap(manifest.models.first { $0.id == modelID })
            let file = try XCTUnwrap(model.files.first)
            let presentation = try XCTUnwrap(model.presentation)
            XCTAssertEqual(model.runtime.engine, .whisperCpp)
            XCTAssertEqual(model.runtime.accelerator, .metalGPU)
            XCTAssertEqual(model.runtime.artifactLayout, .singleFile)
            XCTAssertEqual(model.capabilities.languages, ["en"])
            XCTAssertEqual(model.sizeBytes, artifact.sizeBytes)
            XCTAssertEqual(file.filename, artifact.filename)
            XCTAssertEqual(file.sizeBytes, artifact.sizeBytes)
            XCTAssertEqual(file.sha256, artifact.sha256)
            XCTAssertTrue(file.url.contains("/resolve/c521a4b02f422512d734391fdf08bb08c0862f68/"))
            XCTAssertTrue(presentation.expectedFinalization.contains("ms median"))
            XCTAssertFalse(presentation.expectedFinalization.contains("pending"))
        }
    }

    func testParakeetRNNTUsesPinnedLocalMLXMetalArtifacts() throws {
        let manifest = try verifiedManifest()
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "parakeet-rnnt-1.1b" }
        )

        XCTAssertEqual(model.runtime.engine, .mlxAudio)
        XCTAssertEqual(model.runtime.variant, MLXAudioModelVariant.parakeetRNNT1_1B.rawValue)
        XCTAssertEqual(model.runtime.accelerator, .metalGPU)
        XCTAssertEqual(model.runtime.artifactLayout, .modelDirectory)
        XCTAssertEqual(model.capabilities.languages, ["en"])
        XCTAssertEqual(model.files.count, 5)
        XCTAssertEqual(model.sizeBytes, 4_282_559_760)
        XCTAssertTrue(
            model.files.allSatisfy {
                $0.url.contains("/resolve/7f399a0d3442123deae9194e71f5c984b2879efa/")
            }
        )
        let weights = try XCTUnwrap(model.files.first { $0.filename == "model.safetensors" })
        XCTAssertEqual(weights.sizeBytes, 4_282_246_596)
        XCTAssertEqual(
            weights.sha256,
            "d2c370b3728c4c3b318d814574e87da144a9484ce6b3c4457a6ed5889bb007e1"
        )
        let presentation = try XCTUnwrap(model.presentation)
        XCTAssertTrue(presentation.expectedFinalization.contains("ms median"))
        XCTAssertFalse(presentation.expectedFinalization.contains("pending"))
    }

    func testCanaryQwenUsesPinnedLocalTranscribeCppMetalArtifact() throws {
        let manifest = try verifiedManifest()
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "canary-qwen-2.5b-q4-k-m" }
        )

        XCTAssertEqual(model.runtime.engine, .transcribeCpp)
        XCTAssertEqual(model.runtime.variant, TranscribeCppModelVariant.canaryQwen2_5B.rawValue)
        XCTAssertEqual(model.runtime.accelerator, .metalGPU)
        XCTAssertEqual(model.runtime.artifactLayout, .singleFile)
        XCTAssertEqual(model.capabilities.languages, ["en"])
        XCTAssertEqual(model.runtimeParameters.maxAudioSeconds, 40)
        XCTAssertEqual(model.sizeBytes, 1_737_575_808)
        let file = try XCTUnwrap(model.files.first)
        XCTAssertEqual(file.filename, "canary-qwen-2.5b-Q4_K_M.gguf")
        XCTAssertEqual(file.sizeBytes, 1_737_575_808)
        XCTAssertEqual(
            file.sha256,
            "db5162229d6fa22597d06a613bd9b543eddb3ee02e6afc5e759120fde02bebf7"
        )
        XCTAssertTrue(
            file.url.contains("/resolve/3370d4e2f28cc70eea79dfc9f2f43fb91eef3163/")
        )
        let presentation = try XCTUnwrap(model.presentation)
        XCTAssertTrue(presentation.expectedFinalization.contains("ms median"))
        XCTAssertFalse(presentation.expectedFinalization.contains("pending"))
    }

    func testArticleModelsUsePinnedNativeArtifacts() throws {
        let manifest = try verifiedManifest()
        let transcribeModels: [String: (
            variant: TranscribeCppModelVariant,
            revision: String,
            filename: String,
            sizeBytes: Int64,
            sha256: String
        )] = [
            "granite-speech-4.1-2b-q5-k-m": (
                .graniteSpeech4_1_2B,
                "58e7710fd7039ded5a185668eef5f71ca5d9d919",
                "granite-speech-4.1-2b-Q5_K_M.gguf",
                1_829_704_544,
                "63e0d3a82fa6f0f4688af0b7d7ee784864d271b7be820f4ea43c8298c59b0ac5"
            ),
            "granite-speech-4.1-2b-nar-q5-k-m": (
                .graniteSpeech4_1_2BNAR,
                "ca53e8273416eb7e888f19bcebbcb9b6ab3edc17",
                "granite-speech-4.1-2b-nar-Q5_K_M.gguf",
                1_782_089_344,
                "88d7c7b5b8b59c95bb6580a1e7d5d81cae63943cef71405ff477527b0bb69fca"
            ),
            "voxtral-mini-4b-realtime-2602-q4-k-m": (
                .voxtralMini4BRealtime2602,
                "b3e1c979e3775cbd0a49a65878a0ec7f06789ed7",
                "Voxtral-Mini-4B-Realtime-2602-Q4_K_M.gguf",
                2_830_493_984,
                "39dc1f65539373a406edea7490505822d77c12edff521744678717eef4da4723"
            ),
            "moss-transcribe-diarize-0.9b-q5-k-m": (
                .mossTranscribeDiarize0_9B,
                "6fdfa33aed776bbb0ac11a1a9835634fe6d75dd7",
                "MOSS-Transcribe-Diarize-Q5_K_M.gguf",
                700_313_760,
                "52deaeff931272f3d49eb437f0f4916e42fce9f42e68db250047408241cf473c"
            ),
        ]

        for (modelID, artifact) in transcribeModels {
            let model = try XCTUnwrap(manifest.models.first { $0.id == modelID })
            let file = try XCTUnwrap(model.files.first)
            XCTAssertEqual(model.runtime.engine, .transcribeCpp)
            XCTAssertEqual(model.runtime.variant, artifact.variant.rawValue)
            XCTAssertEqual(model.runtime.accelerator, .metalGPU)
            XCTAssertEqual(model.runtime.artifactLayout, .singleFile)
            XCTAssertEqual(model.runtimeParameters.language, "auto")
            XCTAssertTrue(model.runtimeParameters.detectLanguage)
            XCTAssertEqual(model.runtimeParameters.maxAudioSeconds, 60)
            XCTAssertEqual(model.sizeBytes, artifact.sizeBytes)
            XCTAssertEqual(file.filename, artifact.filename)
            XCTAssertEqual(file.sizeBytes, artifact.sizeBytes)
            XCTAssertEqual(file.sha256, artifact.sha256)
            XCTAssertTrue(file.url.contains("/resolve/\(artifact.revision)/"))
            XCTAssertNil(model.benchmark)
        }

        let omnilingual = try XCTUnwrap(
            manifest.models.first { $0.id == "omnilingual-asr-300m-ctc-int8" }
        )
        XCTAssertEqual(omnilingual.runtime.engine, .sherpaOnnx)
        XCTAssertEqual(
            omnilingual.runtime.variant,
            SherpaOnnxModelVariant.omnilingualASR300M.rawValue
        )
        XCTAssertEqual(omnilingual.runtime.accelerator, .cpu)
        XCTAssertEqual(omnilingual.runtime.artifactLayout, .modelDirectory)
        XCTAssertEqual(omnilingual.runtimeParameters.language, "auto")
        XCTAssertTrue(omnilingual.runtimeParameters.detectLanguage)
        XCTAssertEqual(omnilingual.runtimeParameters.maxAudioSeconds, 40)
        XCTAssertEqual(omnilingual.files.count, 2)
        XCTAssertEqual(omnilingual.sizeBytes, 365_438_543)
        let weights = try XCTUnwrap(
            omnilingual.files.first { $0.filename == "model.int8.onnx" }
        )
        XCTAssertEqual(weights.sizeBytes, 365_352_120)
        XCTAssertEqual(
            weights.sha256,
            "e7c4e54ee4c4c47829cc6667d5d00ed8ea7bef1dcfeef0fce766f77752a2726c"
        )
        XCTAssertTrue(
            omnilingual.files.allSatisfy {
                $0.url.contains("/resolve/6abf1ece20cd2308bdb7d13cd78ec1c44fa4c094/")
            }
        )
        XCTAssertNil(omnilingual.benchmark)
    }

    func testCohereTranscribeUsesPinnedLocalMLXMetalArtifacts() throws {
        let manifest = try verifiedManifest()
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "cohere-transcribe-03-2026-mlx-8bit" }
        )

        XCTAssertEqual(model.runtime.engine, .mlxAudio)
        XCTAssertEqual(model.runtime.variant, MLXAudioModelVariant.cohereTranscribe03_2026.rawValue)
        XCTAssertEqual(model.runtime.accelerator, .metalGPU)
        XCTAssertEqual(model.runtime.artifactLayout, .modelDirectory)
        XCTAssertEqual(model.capabilities.languages, ["en"])
        XCTAssertEqual(model.runtimeParameters.maxAudioSeconds, 30)
        XCTAssertEqual(model.files.count, 4)
        XCTAssertEqual(model.sizeBytes, 2_418_577_135)
        XCTAssertTrue(
            model.files.allSatisfy {
                $0.url.contains("/resolve/d1f843476f84846e6fe7aa58a6033f17882f0ec9/")
            }
        )
        let weights = try XCTUnwrap(model.files.first { $0.filename == "model.safetensors" })
        XCTAssertEqual(weights.sizeBytes, 2_418_031_831)
        XCTAssertEqual(
            weights.sha256,
            "bd1edbe982f47d22e64ba5723a4204b43ca93ea703b18946160d44ec26c83ab9"
        )
        let presentation = try XCTUnwrap(model.presentation)
        XCTAssertTrue(presentation.expectedFinalization.contains("ms median"))
        XCTAssertFalse(presentation.expectedFinalization.contains("pending"))
    }

    func testWhisperTurboUsesPinnedLocalMLXMetalArtifactsAndTokenizer() throws {
        let manifest = try verifiedManifest()
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-large-v3-turbo-mlx" }
        )

        XCTAssertEqual(model.runtime.engine, .mlxAudio)
        XCTAssertEqual(model.runtime.variant, MLXAudioModelVariant.whisperLargeV3Turbo.rawValue)
        XCTAssertEqual(model.runtime.accelerator, .metalGPU)
        XCTAssertEqual(model.runtime.artifactLayout, .modelDirectory)
        XCTAssertEqual(model.capabilities.languages, ["en"])
        XCTAssertEqual(model.runtimeParameters.maxAudioSeconds, 60)
        XCTAssertEqual(model.files.count, 10)
        XCTAssertEqual(model.sizeBytes, 1_618_594_759)
        XCTAssertEqual(
            model.files.filter {
                $0.url.contains("/resolve/a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb/")
            }.count,
            2
        )
        XCTAssertEqual(
            model.files.filter {
                $0.url.contains("/resolve/41f01f3fe87f28c78e2fbf8b568835947dd65ed9/")
            }.count,
            8
        )
        let weights = try XCTUnwrap(model.files.first { $0.filename == "weights.safetensors" })
        XCTAssertEqual(weights.sizeBytes, 1_613_977_612)
        XCTAssertEqual(
            weights.sha256,
            "951ed3fc1203e6a62467abb2144a96ce7eafca8fa77e3704fdb8635ff3e7f8a6"
        )
        XCTAssertNotNil(model.files.first { $0.relativePath == "tokenizer.json" })
        let presentation = try XCTUnwrap(model.presentation)
        XCTAssertTrue(presentation.expectedFinalization.contains("321.5 ms median"))
        XCTAssertFalse(presentation.expectedFinalization.contains("pending"))
    }

    func testQwen3ASRMLXModelsUsePinnedCompleteLocalDirectories() throws {
        let manifest = try verifiedManifest()
        let expected: [String: (
            variant: MLXAudioModelVariant,
            revision: String,
            sizeBytes: Int64,
            weightsSize: Int64,
            weightsSHA256: String
        )] = [
            "qwen3-asr-0.6b-mlx-8bit": (
                .qwen3ASR0_6B8Bit,
                "89e96d92ba34aca20b3e29fb10cc284097d1219f",
                1_010_771_234,
                1_006_229_426,
                "b5bfe4abc1b4c6e58b633096682ec2b6297298add1527119936107d211adf0e8"
            ),
            "qwen3-asr-1.7b-mlx-8bit": (
                .qwen3ASR1_7B8Bit,
                "a8379a2e2f9e313c9292cdf1af4055ab56d50d55",
                2_467_856_503,
                2_463_307_541,
                "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c"
            ),
        ]

        for (modelID, artifact) in expected {
            let model = try XCTUnwrap(manifest.models.first { $0.id == modelID })
            XCTAssertEqual(model.runtime.engine, .mlxAudio)
            XCTAssertEqual(model.runtime.variant, artifact.variant.rawValue)
            XCTAssertEqual(model.runtime.accelerator, .metalGPU)
            XCTAssertEqual(model.runtime.artifactLayout, .modelDirectory)
            XCTAssertEqual(model.runtimeParameters.language, "auto")
            XCTAssertTrue(model.runtimeParameters.detectLanguage)
            XCTAssertEqual(model.runtimeParameters.maxAudioSeconds, 60)
            XCTAssertEqual(model.files.count, 9)
            XCTAssertEqual(model.sizeBytes, artifact.sizeBytes)
            XCTAssertTrue(
                model.files.allSatisfy {
                    $0.url.contains("/resolve/\(artifact.revision)/")
                        && $0.relativePath == $0.filename
                }
            )
            let weights = try XCTUnwrap(
                model.files.first { $0.filename == "model.safetensors" }
            )
            XCTAssertEqual(weights.sizeBytes, artifact.weightsSize)
            XCTAssertEqual(weights.sha256, artifact.weightsSHA256)
            XCTAssertNotNil(model.files.first { $0.filename == "merges.txt" })
            XCTAssertNotNil(model.files.first { $0.filename == "vocab.json" })
            let presentation = try XCTUnwrap(model.presentation)
            XCTAssertTrue(presentation.expectedFinalization.contains("ms median"))
            XCTAssertFalse(presentation.expectedFinalization.contains("pending"))
        }
    }

    func testQwen3ASRGGUFQuantizationsUsePinnedTranscribeCppMetalArtifacts() throws {
        let manifest = try verifiedManifest()
        let expected: [String: (
            variant: TranscribeCppModelVariant,
            revision: String,
            filename: String,
            sizeBytes: Int64,
            sha256: String
        )] = [
            "qwen3-asr-0.6b-bf16": (
                .qwen3ASR0_6B,
                "e4e16599b900eb0cb36e524514756bb92eb092b7",
                "Qwen3-ASR-0.6B-BF16.gguf",
                1_571_490_016,
                "dadb8196937aa6b998a94124a043fce694e0ab6c3c6eb0ae1669fa49d04aab84"
            ),
            "qwen3-asr-0.6b-q8-0": (
                .qwen3ASR0_6B,
                "e4e16599b900eb0cb36e524514756bb92eb092b7",
                "Qwen3-ASR-0.6B-Q8_0.gguf",
                850_423_456,
                "f081b2d5e23bd669d92cc331d722a8a0681943b8e6f34b48996fd5c319b5acd8"
            ),
            "qwen3-asr-0.6b-q5-k-m": (
                .qwen3ASR0_6B,
                "e4e16599b900eb0cb36e524514756bb92eb092b7",
                "Qwen3-ASR-0.6B-Q5_K_M.gguf",
                645_356_192,
                "062a7bcb18675c2fe5ffd0e8b354eac6a1ceada9b2af9ef7168746ae16b54358"
            ),
            "qwen3-asr-1.7b-bf16": (
                .qwen3ASR1_7B,
                "92282af1610a2db19d66f2bef1e260f5deca782d",
                "Qwen3-ASR-1.7B-BF16.gguf",
                4_083_087_904,
                "57db745f8ec3ad2ea391b0205661e7d74f76158877a33f151e4d4624ed2b7cc9"
            ),
            "qwen3-asr-1.7b-q8-0": (
                .qwen3ASR1_7B,
                "92282af1610a2db19d66f2bef1e260f5deca782d",
                "Qwen3-ASR-1.7B-Q8_0.gguf",
                2_185_030_624,
                "9a0d81792dfea2d5f278b8a63deb3ea6e02139ce42c2301f32ea19c4f77526b7"
            ),
            "qwen3-asr-1.7b-q5-k-m": (
                .qwen3ASR1_7B,
                "92282af1610a2db19d66f2bef1e260f5deca782d",
                "Qwen3-ASR-1.7B-Q5_K_M.gguf",
                1_517_290_464,
                "034c557fe92ff8fcd9a9c041cbdaad347be0a86a58d3a348f63cf3f0180879d0"
            ),
        ]

        for (modelID, artifact) in expected {
            let model = try XCTUnwrap(manifest.models.first { $0.id == modelID })
            let file = try XCTUnwrap(model.files.first)
            XCTAssertEqual(model.runtime.engine, .transcribeCpp)
            XCTAssertEqual(model.runtime.variant, artifact.variant.rawValue)
            XCTAssertEqual(model.runtime.accelerator, .metalGPU)
            XCTAssertEqual(model.runtime.artifactLayout, .singleFile)
            XCTAssertEqual(model.runtimeParameters.language, "auto")
            XCTAssertTrue(model.runtimeParameters.detectLanguage)
            XCTAssertEqual(model.runtimeParameters.maxAudioSeconds, 60)
            XCTAssertEqual(model.sizeBytes, artifact.sizeBytes)
            XCTAssertEqual(file.filename, artifact.filename)
            XCTAssertEqual(file.sizeBytes, artifact.sizeBytes)
            XCTAssertEqual(file.sha256, artifact.sha256)
            XCTAssertTrue(file.url.contains("/resolve/\(artifact.revision)/"))
            let presentation = try XCTUnwrap(model.presentation)
            XCTAssertTrue(presentation.expectedFinalization.contains("ms median"))
            XCTAssertFalse(presentation.expectedFinalization.contains("pending"))
        }
    }

    func testParakeetTDTAndNemotronMLXModelsUsePinnedCompleteLocalDirectories() throws {
        let manifest = try verifiedManifest()
        let expected: [String: (
            variant: MLXAudioModelVariant,
            revision: String,
            fileCount: Int,
            sizeBytes: Int64,
            weightsSize: Int64,
            weightsSHA256: String,
            language: String,
            detectsLanguage: Bool
        )] = [
            "parakeet-tdt-0.6b-v2-mlx": (
                .parakeetTDT0_6BV2,
                "8ae155301e23d820d82aa60d24817c900e69e487",
                5,
                2_471_862_935,
                2_471_559_904,
                "b958c37a6baa6874a279108755c8f2818e27bf647d72d54800a234a421341dfe",
                "en",
                false
            ),
            "parakeet-tdt-0.6b-v3-mlx": (
                .parakeetTDT0_6BV3,
                "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15",
                5,
                2_509_041_541,
                2_508_288_736,
                "05e01c7f396c298cf7d23f61da7b504adeab698f0aaeafd9c82d198625464592",
                "auto",
                true
            ),
            "nemotron-3.5-asr-streaming-0.6b-mlx": (
                .nemotron3_5ASRStreaming0_6B,
                "e550040c0478027ed679b2b6b0d055502c103663",
                4,
                1_276_703_116,
                1_276_058_836,
                "1b78e4551371b1438daba0e8c9e1673bb18606994c1bcc493d85c5454d428ee5",
                "auto",
                true
            ),
        ]

        for (modelID, artifact) in expected {
            let model = try XCTUnwrap(manifest.models.first { $0.id == modelID })
            XCTAssertEqual(model.runtime.engine, .mlxAudio)
            XCTAssertEqual(model.runtime.variant, artifact.variant.rawValue)
            XCTAssertEqual(model.runtime.accelerator, .metalGPU)
            XCTAssertEqual(model.runtime.artifactLayout, .modelDirectory)
            XCTAssertEqual(model.runtimeParameters.language, artifact.language)
            XCTAssertEqual(model.runtimeParameters.detectLanguage, artifact.detectsLanguage)
            XCTAssertEqual(model.runtimeParameters.maxAudioSeconds, 60)
            XCTAssertEqual(model.files.count, artifact.fileCount)
            XCTAssertEqual(model.sizeBytes, artifact.sizeBytes)
            XCTAssertTrue(
                model.files.allSatisfy {
                    $0.url.contains("/resolve/\(artifact.revision)/")
                        && $0.relativePath == $0.filename
                }
            )
            let weights = try XCTUnwrap(
                model.files.first { $0.filename == "model.safetensors" }
            )
            XCTAssertEqual(weights.sizeBytes, artifact.weightsSize)
            XCTAssertEqual(weights.sha256, artifact.weightsSHA256)
            XCTAssertFalse(model.displayName.contains("Streaming"))
        }
    }

    func testParakeetTDTAndNemotronGGUFQuantizationsUsePinnedTranscribeCppMetalArtifacts() throws {
        let manifest = try verifiedManifest()
        let expected: [String: (
            variant: TranscribeCppModelVariant,
            revision: String,
            filename: String,
            sizeBytes: Int64,
            sha256: String,
            language: String,
            detectsLanguage: Bool
        )] = [
            "parakeet-tdt-0.6b-v2-f16": (
                .parakeetTDT0_6BV2,
                "07cee0616125a08ef619729bb47f40ef747e4bc4",
                "parakeet-tdt-0.6b-v2-F16.gguf",
                1_237_334_592,
                "8440125213cb92625e3993ec751c3919dd329da9ae9149951cd6f95dd8bafe81",
                "en",
                false
            ),
            "parakeet-tdt-0.6b-v2-q8-0": (
                .parakeetTDT0_6BV2,
                "07cee0616125a08ef619729bb47f40ef747e4bc4",
                "parakeet-tdt-0.6b-v2-Q8_0.gguf",
                729_574_912,
                "f0d0e99cebb6d3b83f1f7069b82b5d3c2e39a54545b0da039cb4bafd9c4e5caa",
                "en",
                false
            ),
            "parakeet-tdt-0.6b-v2-q5-k-m": (
                .parakeetTDT0_6BV2,
                "07cee0616125a08ef619729bb47f40ef747e4bc4",
                "parakeet-tdt-0.6b-v2-Q5_K_M.gguf",
                539_012_608,
                "dfa904520b95451599683613fea47766c378c5fdf5d8cddf48151226b6eaec85",
                "en",
                false
            ),
            "parakeet-tdt-0.6b-v3-f16": (
                .parakeetTDT0_6BV3,
                "85ac09ea12fc4b1112fa76810059364bc6adc9de",
                "parakeet-tdt-0.6b-v3-F16.gguf",
                1_255_869_856,
                "d9ec7e2c39da7b4fec3e01e71e82c7f7bbe97741e08c0c054091bf3d520a41d3",
                "auto",
                true
            ),
            "parakeet-tdt-0.6b-v3-q8-0": (
                .parakeetTDT0_6BV3,
                "85ac09ea12fc4b1112fa76810059364bc6adc9de",
                "parakeet-tdt-0.6b-v3-Q8_0.gguf",
                739_508_576,
                "5859f77944efcd8eafa23a6350731960b2b55b2203df51f319665c807d802cc7",
                "auto",
                true
            ),
            "parakeet-tdt-0.6b-v3-q5-k-m": (
                .parakeetTDT0_6BV3,
                "85ac09ea12fc4b1112fa76810059364bc6adc9de",
                "parakeet-tdt-0.6b-v3-Q5_K_M.gguf",
                548_946_272,
                "cc722e76adc1a629fc0b2535de879d99b8160d07ad4c0215e2ca7d7ea0ae4b8f",
                "auto",
                true
            ),
            "nemotron-3.5-asr-streaming-0.6b-f16": (
                .nemotron3_5ASRStreaming0_6B,
                "6d44e540bc31b0de1dbe174a3cea87f53a7f22fb",
                "nemotron-3.5-asr-streaming-0.6b-F16.gguf",
                1_277_750_240,
                "f21a0cea64d232981def7f8f2b7ab322459703a2e89359962c042c57159755b1",
                "auto",
                true
            ),
            "nemotron-3.5-asr-streaming-0.6b-q8-0": (
                .nemotron3_5ASRStreaming0_6B,
                "6d44e540bc31b0de1dbe174a3cea87f53a7f22fb",
                "nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf",
                751_094_240,
                "b94545b313b3223fda7b2857a52681da813935c2127643d1e9ff0c23d988089c",
                "auto",
                true
            ),
            "nemotron-3.5-asr-streaming-0.6b-q5-k-m": (
                .nemotron3_5ASRStreaming0_6B,
                "6d44e540bc31b0de1dbe174a3cea87f53a7f22fb",
                "nemotron-3.5-asr-streaming-0.6b-Q5_K_M.gguf",
                559_647_200,
                "86429e8c4f7fdcf9b3312269ad1ca6669478ba7805331c4aea7a2e33e9910d65",
                "auto",
                true
            ),
        ]

        for (modelID, artifact) in expected {
            let model = try XCTUnwrap(manifest.models.first { $0.id == modelID })
            let file = try XCTUnwrap(model.files.first)
            XCTAssertEqual(model.runtime.engine, .transcribeCpp)
            XCTAssertEqual(model.runtime.variant, artifact.variant.rawValue)
            XCTAssertEqual(model.runtime.accelerator, .metalGPU)
            XCTAssertEqual(model.runtime.artifactLayout, .singleFile)
            XCTAssertEqual(model.runtimeParameters.language, artifact.language)
            XCTAssertEqual(model.runtimeParameters.detectLanguage, artifact.detectsLanguage)
            XCTAssertEqual(model.runtimeParameters.maxAudioSeconds, 60)
            XCTAssertEqual(model.sizeBytes, artifact.sizeBytes)
            XCTAssertEqual(file.filename, artifact.filename)
            XCTAssertEqual(file.sizeBytes, artifact.sizeBytes)
            XCTAssertEqual(file.sha256, artifact.sha256)
            XCTAssertTrue(file.url.contains("/resolve/\(artifact.revision)/"))
            XCTAssertFalse(model.displayName.contains("Streaming"))
        }
    }

    func testMossFormer2VoiceCleanersUsePinnedLocalMLXMetalArtifacts() throws {
        let manifest = try verifiedManifest()
        let expected: [String: (
            variant: String,
            revision: String,
            sizeBytes: Int64,
            weightsSize: Int64,
            weightsSHA256: String
        )] = [
            "mossformer2-se-fp32": (
                "mossformer2-se-fp32",
                "8744c59f925154f4ba2e9f15ae7eeaa870f80118",
                221_178_344,
                221_178_088,
                "8e47b75ca25dc402db5420c45c868544da8d2ac43b21a919197da113d4d81313"
            ),
            "mossformer2-se-fp16": (
                "mossformer2-se-fp16",
                "dd04b1b736b9f49951433b7f051cd8d32eb024b6",
                110_652_884,
                110_652_628,
                "61e63484df9c2be7e1111ca0346d431422a98b263331021a67c2d7ddb2f67a85"
            ),
            "mossformer2-se-int8": (
                "mossformer2-se-int8",
                "694e69b58f2457e02d96f4ba7fa151a28b07805a",
                90_089_718,
                90_089_394,
                "89a0a7fef6de4a7b25bac7365ea60e9b490e978d2ad2fc95c381092f06a5315f"
            ),
        ]

        for (modelID, artifact) in expected {
            let model = try XCTUnwrap(manifest.models.first { $0.id == modelID })
            XCTAssertEqual(model.purpose, .voiceCleaning)
            XCTAssertEqual(model.runtime.engine, .mlxAudio)
            XCTAssertEqual(model.runtime.variant, artifact.variant)
            XCTAssertEqual(model.runtime.accelerator, .metalGPU)
            XCTAssertEqual(model.runtime.artifactLayout, .modelDirectory)
            XCTAssertEqual(model.capabilities.languages, ["*"])
            XCTAssertEqual(model.runtimeParameters.maxAudioSeconds, 60)
            XCTAssertEqual(model.files.count, 2)
            XCTAssertEqual(model.sizeBytes, artifact.sizeBytes)
            XCTAssertTrue(
                model.files.allSatisfy {
                    $0.url.contains("/resolve/\(artifact.revision)/")
                        && $0.relativePath == $0.filename
                }
            )
            XCTAssertNotNil(model.files.first { $0.filename == "config.json" })
            let weights = try XCTUnwrap(
                model.files.first { $0.filename == "model.safetensors" }
            )
            XCTAssertEqual(weights.sizeBytes, artifact.weightsSize)
            XCTAssertEqual(weights.sha256, artifact.weightsSHA256)
        }
    }

    private func verifiedManifest() throws -> ModelManifest {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "textify-model-manifest-2026-huggingface",
                publicKeyBase64: "eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="
            ),
        ])
        return try verifier.verify(
            manifestData: Data(contentsOf: repository.appendingPathComponent("models/manifest.json")),
            signatureData: Data(contentsOf: repository.appendingPathComponent("models/manifest.json.sig"))
        )
    }
}
