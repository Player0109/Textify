@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import TextifyModels
import TextifyTranscription
import XCTest

final class HuggingFaceCatalogIntegrationTests: XCTestCase {
    func testSignedCatalogDownloadsAndTranscribesWithPromotedHuggingFaceModels() async throws {
        guard ProcessInfo.processInfo.environment["TEXTIFY_RUN_HUGGINGFACE_CATALOG_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip(
                "Set TEXTIFY_RUN_HUGGINGFACE_CATALOG_INTEGRATION_TESTS=1 to download and exercise the promoted Hugging Face models."
            )
        }

        let repository = Self.repositoryRoot
        let manifestData = try Data(contentsOf: repository.appendingPathComponent("models/manifest.json"))
        let signatureData = try Data(contentsOf: repository.appendingPathComponent("models/manifest.json.sig"))
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "textify-model-manifest-2026-huggingface",
                publicKeyBase64: "eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="
            ),
        ])
        let manifest = try verifier.verify(
            manifestData: manifestData,
            signatureData: signatureData
        )
        try ProductionModelPolicy.validateProductionManifest(manifest)

        let installationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyHuggingFaceCatalogIntegration-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: installationRoot) }
        let layout = ModelStorageLayout(rootDirectory: installationRoot)
        let installer = ModelInstaller(
            layout: layout,
            transport: URLSessionDownloadTransport(),
            currentAppVersion: "1.1.0"
        )

        let englishAudio = try CanonicalIntegrationAudio.load(
            from: repository.appendingPathComponent(
                "Benchmarks/RealtimeASR/.benchmark-data/openslr31/LibriSpeech/dev-clean-2/1272/141231/1272-141231-0000.flac"
            )
        )
        let japaneseAudio = try CanonicalIntegrationAudio.load(
            from: repository.appendingPathComponent(
                "Benchmarks/RealtimeASR/.benchmark-data/jsut-basic5000-sample/basic5000/wav/BASIC5000_4501.wav"
            )
        )
        let hindiAudio = try CanonicalIntegrationAudio.load(
            from: repository.appendingPathComponent(
                "Benchmarks/RealtimeASR/.benchmark-data/fleurs-hi-in-sample/0.wav"
            )
        )

        let whisperCandidates: [(
            id: String,
            filename: String,
            fixtures: [(language: String, audio: CanonicalIntegrationAudio)]
        )] = [
            (
                "whisper-large-v2-q5_0",
                "ggml-large-v2-q5_0.bin",
                [("en", englishAudio)]
            ),
            (
                "whisper-large-v3-q5_0",
                "ggml-large-v3-q5_0.bin",
                [("en", englishAudio)]
            ),
            (
                "whisper-large-v3-turbo-q5_0",
                "ggml-large-v3-turbo-q5_0.bin",
                [("en", englishAudio), ("hi", hindiAudio)]
            ),
        ]
        for candidate in whisperCandidates {
            let record = try await installer.install(modelID: candidate.id, from: manifest)
            XCTAssertEqual(record.model.files.count, 1)
            let modelURL = try layout.installedFileURL(
                modelID: record.model.id,
                filename: candidate.filename
            )
            let whisper = WhisperRuntime()
            try await whisper.load(
                modelID: record.model.id,
                modelPath: modelURL.path,
                useGPU: true
            )
            for fixture in candidate.fixtures {
                let result = try await whisper.transcribe(
                    TranscriptionAudioBuffer(samples: fixture.audio.samples),
                    options: WhisperTranscriptionOptions(
                        language: fixture.language,
                        translate: false,
                        temperature: 0,
                        temperatureFallback: [],
                        usePreviousContext: false,
                        initialPrompt: nil
                    )
                )
                XCTAssertFalse(
                    result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Expected \(candidate.id) to transcribe the \(fixture.language) fixture."
                )
            }
            await whisper.unload()
        }

        let parakeetCandidates: [(
            id: String,
            fileCount: Int,
            variant: ParakeetModelVariant,
            languageCode: String,
            audio: CanonicalIntegrationAudio
        )] = [
            ("parakeet-tdt-0.6b-v3", 21, .tdtV3, "en", englishAudio),
            ("parakeet-tdt-ctc-110m", 16, .tdtCtc110M, "en", englishAudio),
            ("parakeet-tdt-0.6b-v2", 21, .tdtV2, "en", englishAudio),
            ("parakeet-ja", 21, .tdtJapanese, "ja", japaneseAudio),
        ]
        for candidate in parakeetCandidates {
            let record = try await installer.install(modelID: candidate.id, from: manifest)
            XCTAssertEqual(record.model.files.count, candidate.fileCount)
            let directory = try layout.installedModelDirectory(modelID: record.model.id)
            let runtime = ParakeetRuntime()
            try await runtime.load(
                modelID: record.model.id,
                modelDirectory: directory.path,
                variant: candidate.variant,
                languageCode: candidate.languageCode
            )
            let result = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: candidate.audio.samples)
            )
            XCTAssertFalse(
                result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Expected \(candidate.id) to transcribe its canonical fixture."
            )
            await runtime.unload()
        }

        let rnntRecord = try await installer.install(
            modelID: "parakeet-rnnt-1.1b",
            from: manifest
        )
        XCTAssertEqual(rnntRecord.model.files.count, 5)
        let rnntDirectory = try layout.installedModelDirectory(
            modelID: rnntRecord.model.id
        )
        let rnnt = MLXAudioRuntime()
        try await rnnt.load(
            modelID: rnntRecord.model.id,
            modelDirectory: rnntDirectory.path,
            variant: .parakeetRNNT1_1B,
            languageCode: "en"
        )
        let rnntResult = try await rnnt.transcribe(
            TranscriptionAudioBuffer(samples: englishAudio.samples)
        )
        XCTAssertFalse(
            rnntResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        await rnnt.unload()

        let cohereRecord = try await installer.install(
            modelID: "cohere-transcribe-03-2026-mlx-8bit",
            from: manifest
        )
        XCTAssertEqual(cohereRecord.model.files.count, 4)
        let cohereDirectory = try layout.installedModelDirectory(
            modelID: cohereRecord.model.id
        )
        let cohere = MLXAudioRuntime()
        try await cohere.load(
            modelID: cohereRecord.model.id,
            modelDirectory: cohereDirectory.path,
            variant: .cohereTranscribe03_2026,
            languageCode: "en"
        )
        let cohereResult = try await cohere.transcribe(
            TranscriptionAudioBuffer(samples: englishAudio.samples)
        )
        XCTAssertFalse(
            cohereResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        XCTAssertLessThan(cohereResult.timing?.inferenceDurationMs ?? .max, 700)
        await cohere.unload()

        let mlxWhisperRecord = try await installer.install(
            modelID: "whisper-large-v3-turbo-mlx",
            from: manifest
        )
        XCTAssertEqual(mlxWhisperRecord.model.files.count, 10)
        let mlxWhisperDirectory = try layout.installedModelDirectory(
            modelID: mlxWhisperRecord.model.id
        )
        let mlxWhisper = MLXAudioRuntime()
        try await mlxWhisper.load(
            modelID: mlxWhisperRecord.model.id,
            modelDirectory: mlxWhisperDirectory.path,
            variant: .whisperLargeV3Turbo,
            languageCode: "en"
        )
        let mlxWhisperResult = try await mlxWhisper.transcribe(
            TranscriptionAudioBuffer(samples: englishAudio.samples)
        )
        XCTAssertFalse(
            mlxWhisperResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        XCTAssertLessThan(mlxWhisperResult.timing?.inferenceDurationMs ?? .max, 700)
        await mlxWhisper.unload()

        let mlxQwenCandidates: [(
            id: String,
            variant: MLXAudioModelVariant,
            fixtures: [CanonicalIntegrationAudio]
        )] = [
            (
                "qwen3-asr-0.6b-mlx-8bit",
                .qwen3ASR0_6B8Bit,
                [englishAudio, hindiAudio]
            ),
            (
                "qwen3-asr-1.7b-mlx-8bit",
                .qwen3ASR1_7B8Bit,
                [englishAudio]
            ),
        ]
        for candidate in mlxQwenCandidates {
            let record = try await installer.install(modelID: candidate.id, from: manifest)
            XCTAssertEqual(record.model.files.count, 9)
            let directory = try layout.installedModelDirectory(modelID: record.model.id)
            let runtime = MLXAudioRuntime()
            try await runtime.load(
                modelID: record.model.id,
                modelDirectory: directory.path,
                variant: candidate.variant,
                languageCode: "auto"
            )
            for fixture in candidate.fixtures {
                let result = try await runtime.transcribe(
                    TranscriptionAudioBuffer(samples: fixture.samples)
                )
                XCTAssertFalse(
                    result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Expected \(candidate.id) to transcribe with automatic language detection."
                )
            }
            await runtime.unload()
        }

        let mlxParakeetAndNemotronCandidates: [(
            id: String,
            fileCount: Int,
            variant: MLXAudioModelVariant,
            languageCode: String
        )] = [
            ("parakeet-tdt-0.6b-v2-mlx", 5, .parakeetTDT0_6BV2, "en"),
            ("parakeet-tdt-0.6b-v3-mlx", 5, .parakeetTDT0_6BV3, "auto"),
            (
                "nemotron-3.5-asr-streaming-0.6b-mlx",
                4,
                .nemotron3_5ASRStreaming0_6B,
                "auto"
            ),
        ]
        for candidate in mlxParakeetAndNemotronCandidates {
            let record = try await installer.install(modelID: candidate.id, from: manifest)
            XCTAssertEqual(record.model.files.count, candidate.fileCount)
            let directory = try layout.installedModelDirectory(modelID: record.model.id)
            let runtime = MLXAudioRuntime()
            try await runtime.load(
                modelID: record.model.id,
                modelDirectory: directory.path,
                variant: candidate.variant,
                languageCode: candidate.languageCode
            )
            let result = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: englishAudio.samples)
            )
            XCTAssertFalse(
                result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Expected \(candidate.id) to transcribe the canonical English fixture."
            )
            await runtime.unload()
        }

        let canaryRecord = try await installer.install(
            modelID: "canary-qwen-2.5b-q4-k-m",
            from: manifest
        )
        XCTAssertEqual(canaryRecord.model.files.count, 1)
        let canaryModelURL = try layout.installedFileURL(
            modelID: canaryRecord.model.id,
            filename: "canary-qwen-2.5b-Q4_K_M.gguf"
        )
        let transcribeRuntimeDirectory = repository.appendingPathComponent(
            "Vendor/transcribe.cpp/v0.1.3/lib",
            isDirectory: true
        )
        let canary = TranscribeCppRuntime(
            runtimeDirectory: transcribeRuntimeDirectory.path
        )
        try await canary.load(
            modelID: canaryRecord.model.id,
            modelPath: canaryModelURL.path,
            variant: .canaryQwen2_5B,
            languageCode: "en"
        )
        let canaryResult = try await canary.transcribe(
            TranscriptionAudioBuffer(samples: englishAudio.samples)
        )
        XCTAssertFalse(
            canaryResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        XCTAssertLessThan(canaryResult.timing?.inferenceDurationMs ?? .max, 700)
        await canary.unload()

        let ggufQwenCandidates: [(
            id: String,
            filename: String,
            variant: TranscribeCppModelVariant,
            fixtures: [CanonicalIntegrationAudio]
        )] = [
            (
                "qwen3-asr-0.6b-bf16",
                "Qwen3-ASR-0.6B-BF16.gguf",
                .qwen3ASR0_6B,
                [englishAudio]
            ),
            (
                "qwen3-asr-0.6b-q8-0",
                "Qwen3-ASR-0.6B-Q8_0.gguf",
                .qwen3ASR0_6B,
                [englishAudio]
            ),
            (
                "qwen3-asr-0.6b-q5-k-m",
                "Qwen3-ASR-0.6B-Q5_K_M.gguf",
                .qwen3ASR0_6B,
                [englishAudio, hindiAudio]
            ),
            (
                "qwen3-asr-1.7b-bf16",
                "Qwen3-ASR-1.7B-BF16.gguf",
                .qwen3ASR1_7B,
                [englishAudio]
            ),
            (
                "qwen3-asr-1.7b-q8-0",
                "Qwen3-ASR-1.7B-Q8_0.gguf",
                .qwen3ASR1_7B,
                [englishAudio]
            ),
            (
                "qwen3-asr-1.7b-q5-k-m",
                "Qwen3-ASR-1.7B-Q5_K_M.gguf",
                .qwen3ASR1_7B,
                [englishAudio]
            ),
        ]
        for candidate in ggufQwenCandidates {
            let record = try await installer.install(modelID: candidate.id, from: manifest)
            XCTAssertEqual(record.model.files.count, 1)
            let modelURL = try layout.installedFileURL(
                modelID: record.model.id,
                filename: candidate.filename
            )
            let runtime = TranscribeCppRuntime(
                runtimeDirectory: transcribeRuntimeDirectory.path
            )
            try await runtime.load(
                modelID: record.model.id,
                modelPath: modelURL.path,
                variant: candidate.variant,
                languageCode: "auto"
            )
            for fixture in candidate.fixtures {
                let result = try await runtime.transcribe(
                    TranscriptionAudioBuffer(samples: fixture.samples)
                )
                XCTAssertFalse(
                    result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Expected \(candidate.id) to transcribe with automatic language detection."
                )
            }
            await runtime.unload()
        }

        let ggufParakeetAndNemotronCandidates: [(
            id: String,
            filename: String,
            variant: TranscribeCppModelVariant,
            languageCode: String
        )] = [
            (
                "parakeet-tdt-0.6b-v2-f16",
                "parakeet-tdt-0.6b-v2-F16.gguf",
                .parakeetTDT0_6BV2,
                "en"
            ),
            (
                "parakeet-tdt-0.6b-v2-q8-0",
                "parakeet-tdt-0.6b-v2-Q8_0.gguf",
                .parakeetTDT0_6BV2,
                "en"
            ),
            (
                "parakeet-tdt-0.6b-v2-q5-k-m",
                "parakeet-tdt-0.6b-v2-Q5_K_M.gguf",
                .parakeetTDT0_6BV2,
                "en"
            ),
            (
                "parakeet-tdt-0.6b-v3-f16",
                "parakeet-tdt-0.6b-v3-F16.gguf",
                .parakeetTDT0_6BV3,
                "auto"
            ),
            (
                "parakeet-tdt-0.6b-v3-q8-0",
                "parakeet-tdt-0.6b-v3-Q8_0.gguf",
                .parakeetTDT0_6BV3,
                "auto"
            ),
            (
                "parakeet-tdt-0.6b-v3-q5-k-m",
                "parakeet-tdt-0.6b-v3-Q5_K_M.gguf",
                .parakeetTDT0_6BV3,
                "auto"
            ),
            (
                "nemotron-3.5-asr-streaming-0.6b-f16",
                "nemotron-3.5-asr-streaming-0.6b-F16.gguf",
                .nemotron3_5ASRStreaming0_6B,
                "auto"
            ),
            (
                "nemotron-3.5-asr-streaming-0.6b-q8-0",
                "nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf",
                .nemotron3_5ASRStreaming0_6B,
                "auto"
            ),
            (
                "nemotron-3.5-asr-streaming-0.6b-q5-k-m",
                "nemotron-3.5-asr-streaming-0.6b-Q5_K_M.gguf",
                .nemotron3_5ASRStreaming0_6B,
                "auto"
            ),
        ]
        for candidate in ggufParakeetAndNemotronCandidates {
            let record = try await installer.install(modelID: candidate.id, from: manifest)
            XCTAssertEqual(record.model.files.count, 1)
            let modelURL = try layout.installedFileURL(
                modelID: record.model.id,
                filename: candidate.filename
            )
            let runtime = TranscribeCppRuntime(
                runtimeDirectory: transcribeRuntimeDirectory.path
            )
            try await runtime.load(
                modelID: record.model.id,
                modelPath: modelURL.path,
                variant: candidate.variant,
                languageCode: candidate.languageCode
            )
            let result = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: englishAudio.samples)
            )
            XCTAssertFalse(
                result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Expected \(candidate.id) to transcribe the canonical English fixture."
            )
            await runtime.unload()
        }

        let paraformerRecord = try await installer.install(
            modelID: "paraformer-large-zh-int8",
            from: manifest
        )
        XCTAssertEqual(paraformerRecord.model.files.count, 17)
        let paraformerDirectory = try layout.installedModelDirectory(
            modelID: paraformerRecord.model.id
        )
        let chineseAudio = try CanonicalIntegrationAudio.load(
            from: repository.appendingPathComponent(
                "Benchmarks/RealtimeASR/.benchmark-data/aishell1-sample/0.wav"
            )
        )
        let paraformer = ParaformerRuntime()
        try await paraformer.load(
            modelID: paraformerRecord.model.id,
            modelDirectory: paraformerDirectory.path,
            variant: .largeZhInt8
        )
        let paraformerResult = try await paraformer.transcribe(
            TranscriptionAudioBuffer(samples: chineseAudio.samples)
        )
        XCTAssertFalse(paraformerResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        await paraformer.unload()

        let reazonRecord = try await installer.install(
            modelID: "reazonspeech-k2-v2-int8",
            from: manifest
        )
        XCTAssertEqual(reazonRecord.model.files.count, 4)
        let reazonDirectory = try layout.installedModelDirectory(
            modelID: reazonRecord.model.id
        )
        let sherpaRuntimeDirectory = repository.appendingPathComponent(
            "Vendor/sherpa-onnx/v1.13.2/lib",
            isDirectory: true
        )
        let reazon = SherpaOnnxRuntime(runtimeDirectory: sherpaRuntimeDirectory.path)
        try await reazon.load(
            modelID: reazonRecord.model.id,
            modelDirectory: reazonDirectory.path,
            variant: .reazonSpeechK2V2
        )
        let reazonResult = try await reazon.transcribe(
            TranscriptionAudioBuffer(samples: japaneseAudio.samples)
        )
        XCTAssertFalse(reazonResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertLessThan(reazonResult.timing?.inferenceDurationMs ?? .max, 700)
        let reazonSilenceResult = try await reazon.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 5 * 16000))
        )
        XCTAssertLessThan(
            reazonSilenceResult.averageLogProbability,
            reazonRecord.model.hallucinationThresholds.avgLogProbabilityMin,
            "The published confidence threshold must discard the measured silence hallucination."
        )
        await reazon.unload()

        let senseVoiceRecord = try await installer.install(
            modelID: "sensevoice-small-int8-2024-07-17",
            from: manifest
        )
        XCTAssertEqual(senseVoiceRecord.model.files.count, 2)
        let senseVoiceDirectory = try layout.installedModelDirectory(
            modelID: senseVoiceRecord.model.id
        )
        let koreanAudio = try await Self.downloadSenseVoiceFixture(
            filename: "ko.wav",
            expectedSize: 147_500,
            expectedSHA256: "0dc797a5c81ed30fc339d91f3da718ab02854e17ffa37cb93c4c039ac5c6bb9c",
            into: installationRoot
        )
        let cantoneseAudio = try await Self.downloadSenseVoiceFixture(
            filename: "yue.wav",
            expectedSize: 164_780,
            expectedSHA256: "0960b2db54ae202071d250e6462fbf74a3c863f0e3e7f01273e4939c996875a0",
            into: installationRoot
        )
        let senseVoice = SherpaOnnxRuntime(runtimeDirectory: sherpaRuntimeDirectory.path)
        try await senseVoice.load(
            modelID: senseVoiceRecord.model.id,
            modelDirectory: senseVoiceDirectory.path,
            variant: .senseVoiceSmall,
            languageCode: "auto"
        )
        for fixture in [
            ("en", englishAudio),
            ("zh", chineseAudio),
            ("ja", japaneseAudio),
            ("ko", koreanAudio),
            ("yue", cantoneseAudio),
        ] {
            let result = try await senseVoice.transcribe(
                TranscriptionAudioBuffer(samples: fixture.1.samples)
            )
            XCTAssertFalse(
                result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Expected SenseVoiceSmall automatic selection to transcribe the \(fixture.0) fixture."
            )
            XCTAssertLessThan(
                result.timing?.inferenceDurationMs ?? .max,
                700,
                "SenseVoiceSmall missed the interactive latency budget for \(fixture.0)."
            )
        }
        let senseVoiceSilenceResult = try await senseVoice.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 5 * 16000))
        )
        XCTAssertEqual(senseVoiceSilenceResult.noSpeechProbability, 1)
        await senseVoice.unload()
    }

    func testSignedCatalogDownloadsAndTranscribesWithCrisperWhisperModels() async throws {
        guard ProcessInfo.processInfo.environment[
            "TEXTIFY_RUN_CRISPERWHISPER_INTEGRATION_TESTS"
        ] == "1" else {
            throw XCTSkip(
                "Set TEXTIFY_RUN_CRISPERWHISPER_INTEGRATION_TESTS=1 to download and exercise the two CrisperWhisper catalog models."
            )
        }

        let repository = Self.repositoryRoot
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "textify-model-manifest-2026-huggingface",
                publicKeyBase64: "eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="
            ),
        ])
        let manifest = try verifier.verify(
            manifestData: Data(
                contentsOf: repository.appendingPathComponent("models/manifest.json")
            ),
            signatureData: Data(
                contentsOf: repository.appendingPathComponent("models/manifest.json.sig")
            )
        )
        try ProductionModelPolicy.validateProductionManifest(manifest)

        let installationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyCrisperWhisperCatalogIntegration-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: installationRoot) }
        let layout = ModelStorageLayout(rootDirectory: installationRoot)
        let installer = ModelInstaller(
            layout: layout,
            transport: URLSessionDownloadTransport(),
            currentAppVersion: "1.1.0"
        )
        let englishAudio = try CanonicalIntegrationAudio.load(
            from: repository.appendingPathComponent(
                "Benchmarks/RealtimeASR/.benchmark-data/openslr31/LibriSpeech/dev-clean-2/1272/141231/1272-141231-0000.flac"
            )
        )
        let candidates = [
            (
                id: "crisperwhisper-2-large-f16",
                filename: "ggml-crisperwhisper-large-f16.bin"
            ),
            (
                id: "crisperwhisper-2-turbo-f16",
                filename: "ggml-crisperwhisper-turbo-f16.bin"
            ),
        ]

        XCTAssertEqual(
            manifest.models.filter { model in
                candidates.contains { $0.id == model.id }
            }.map(\.id),
            candidates.map { $0.id }
        )

        for candidate in candidates {
            let record = try await installer.install(
                modelID: candidate.id,
                from: manifest
            )
            XCTAssertEqual(record.model.files.count, 1)
            XCTAssertEqual(record.model.runtime.variant, candidate.id)
            XCTAssertEqual(record.model.runtimeParameters.language, "en")
            XCTAssertEqual(record.model.runtimeParameters.maxAudioSeconds, 30)

            let modelURL = try layout.installedFileURL(
                modelID: record.model.id,
                filename: candidate.filename
            )
            let runtime = WhisperRuntime()
            try await runtime.load(
                modelID: record.model.id,
                modelPath: modelURL.path,
                useGPU: true
            )
            let result = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: englishAudio.samples),
                options: .v1_1English
            )
            XCTAssertFalse(
                result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Expected \(candidate.id) to transcribe the canonical English fixture in intended mode."
            )
            await runtime.unload()
        }
    }

    private static func downloadSenseVoiceFixture(
        filename: String,
        expectedSize: Int,
        expectedSHA256: String,
        into directory: URL
    ) async throws -> CanonicalIntegrationAudio {
        let revision = "2365baeacb507f821a0c8120fcee3d484dba7a07"
        let url = try XCTUnwrap(
            URL(
                string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/\(revision)/test_wavs/\(filename)"
            )
        )
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(data.count, expectedSize)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, expectedSHA256)
        let destination = directory.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        return try CanonicalIntegrationAudio.load(from: destination)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class IntegrationConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !supplied else {
            status.pointee = .endOfStream
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
    }
}

private struct CanonicalIntegrationAudio {
    let samples: [Float]

    static func load(from url: URL) throws -> CanonicalIntegrationAudio {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw IntegrationAudioError.allocationFailed
        }
        try file.read(into: sourceBuffer)

        guard let canonicalFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceFormat, to: canonicalFormat) else {
            throw IntegrationAudioError.converterUnavailable
        }
        let ratio = canonicalFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + 1024
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: canonicalFormat,
            frameCapacity: capacity
        ) else {
            throw IntegrationAudioError.allocationFailed
        }

        let input = IntegrationConverterInput(buffer: sourceBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            input.next(status: inputStatus)
        }
        guard status != .error, conversionError == nil,
              let channel = converted.floatChannelData?.pointee
        else {
            throw IntegrationAudioError.conversionFailed
        }
        return CanonicalIntegrationAudio(
            samples: Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        )
    }
}

private enum IntegrationAudioError: Error {
    case allocationFailed
    case converterUnavailable
    case conversionFailed
}
