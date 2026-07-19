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
            )
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

        let whisperRecord = try await installer.install(
            modelID: "whisper-large-v3-turbo-q5_0",
            from: manifest
        )
        XCTAssertEqual(whisperRecord.model.files.count, 1)
        let whisperModelURL = try layout.installedFileURL(
            modelID: whisperRecord.model.id,
            filename: "ggml-large-v3-turbo-q5_0.bin"
        )
        let whisper = WhisperRuntime()
        try await whisper.load(
            modelID: whisperRecord.model.id,
            modelPath: whisperModelURL.path,
            useGPU: true
        )
        for fixture in [("en", englishAudio), ("hi", hindiAudio)] {
            let result = try await whisper.transcribe(
                TranscriptionAudioBuffer(samples: fixture.1.samples),
                options: WhisperTranscriptionOptions(
                    language: fixture.0,
                    translate: false,
                    temperature: 0,
                    temperatureFallback: [],
                    usePreviousContext: false,
                    initialPrompt: nil
                )
            )
            XCTAssertFalse(
                result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Expected Whisper Turbo to transcribe the \(fixture.0) fixture."
            )
        }
        await whisper.unload()

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
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 5 * 16_000))
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
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 5 * 16_000))
        )
        XCTAssertEqual(senseVoiceSilenceResult.noSpeechProbability, 1)
        await senseVoice.unload()
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
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceFormat, to: canonicalFormat) else {
            throw IntegrationAudioError.converterUnavailable
        }
        let ratio = canonicalFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + 1_024
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
              let channel = converted.floatChannelData?.pointee else {
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
