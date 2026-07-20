import CryptoKit
import Foundation
import TextifyAudio
import TextifyCore
import TextifyDiagnostics
import TextifyHotkeys
import TextifyInsertion
import TextifyModels
import TextifySettings
import TextifyTranscription
@testable import TextifyRuntime
import XCTest

final class RuntimeAdaptersTests: XCTestCase {
    func testSettingsAdapterLoadsAndSavesPreferences() async {
        let store = SettingsStore(storage: .memory)
        let adapter = RuntimeSettingsStoreAdapter(store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = "ggml-small.en-q5_1"

        await adapter.savePreferences(preferences)
        let loaded = await adapter.loadPreferences()

        XCTAssertEqual(loaded.activeModelID, "ggml-small.en-q5_1")
    }

    func testDiagnosticsAdapterWritesEvents() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = DiagnosticsLogger(directory: directory)
        let adapter = RuntimeDiagnosticsLoggerAdapter(logger: logger)

        await adapter.log(.appStarted(appVersion: "1.0.0", macOSVersion: "14.0"))

        let data = try Data(contentsOf: logger.logFileURL)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""event":"app_started""#))
    }

    func testAudioAdapterRejectsExplicitMicrophoneSelection() async throws {
        let adapter = RuntimeAudioRecorderAdapter(recorder: LiveAudioRecorder())

        do {
            try await adapter.startRecording(
                microphone: .device(deviceUID: "missing", lastSeenDisplayName: "Missing"),
                maximumDurationSeconds: 60,
                onSpeechDetected: {},
                onMaximumDurationReached: {}
            )
            XCTFail("Expected explicit microphone selection to be rejected")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .unsupportedInput)
        }
    }

    func testWhisperAdapterReportsMissingModelAfterFailedPrepare() async throws {
        let runtime = WhisperRuntime()
        let adapter = WhisperRuntimeTranscribingAdapter(runtime: runtime)
        let model = RuntimeActiveModel(
            id: "ggml-small.en-q5_1",
            displayName: "Balanced - Whisper small.en",
            tier: "balanced",
            localModelPath: "/tmp/textify-missing-model.bin",
            useGPU: true,
            threadCount: 1
        )

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected missing model prepare to fail")
        } catch {
            let readiness = await adapter.readiness
            XCTAssertEqual(readiness, .failed(modelID: model.id, reason: .missingFile))
        }
    }

    func testWhisperAdapterCoalescesConcurrentSameModelPrepare() async throws {
        let runtime = FakeWhisperRuntime(suspendLoad: true)
        let adapter = WhisperRuntimeTranscribingAdapter(runtime: runtime)
        let model = Self.activeModel()

        let firstPrepare = Task {
            try await adapter.prepare(model: model)
        }
        while await runtime.loadCallCount() == 0 {
            await Task.yield()
        }

        let secondPrepare = Task {
            try await adapter.prepare(model: model)
        }
        await Task.yield()

        let loadCallCountWhilePreparing = await runtime.loadCallCount()
        XCTAssertEqual(loadCallCountWhilePreparing, 1)
        await runtime.releaseLoads()

        try await firstPrepare.value
        try await secondPrepare.value
        let finalLoadCallCount = await runtime.loadCallCount()
        XCTAssertEqual(finalLoadCallCount, 1)
    }

    func testWhisperAdapterStartsNewPrepareAfterFailedPrepare() async throws {
        let runtime = FakeWhisperRuntime(loadError: FakeWhisperRuntimeError.loadFailed)
        let adapter = WhisperRuntimeTranscribingAdapter(runtime: runtime)
        let model = Self.activeModel()

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected first prepare to fail")
        } catch FakeWhisperRuntimeError.loadFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await runtime.setLoadError(nil)
        try await adapter.prepare(model: model)

        let loadCallCount = await runtime.loadCallCount()
        XCTAssertEqual(loadCallCount, 2)
    }

    func testWhisperAdapterSkipsLoadWhenSameModelIsAlreadyReady() async throws {
        let model = Self.activeModel()
        let runtime = FakeWhisperRuntime(initialState: .ready(modelID: model.id))
        let adapter = WhisperRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(model: model)

        let loadCallCount = await runtime.loadCallCount()
        XCTAssertEqual(loadCallCount, 0)
    }

    func testWhisperAdapterUsesActiveModelDecodingParameters() async throws {
        let runtime = FakeWhisperRuntime()
        let adapter = WhisperRuntimeTranscribingAdapter(runtime: runtime)
        let model = RuntimeActiveModel(
            id: Self.fixtureModelID,
            displayName: "Multilingual Whisper",
            tier: "balanced",
            localModelPath: "/tmp/textify-model.bin",
            useGPU: true,
            threadCount: 1,
            engine: .whisperCpp,
            variant: "whisper",
            accelerator: .metalGPU,
            artifactLayout: .singleFile,
            runtimeParameters: RuntimeParameters(
                language: "de",
                detectLanguage: true,
                translate: true,
                strategy: "greedy",
                beamSize: 1,
                bestOf: 1,
                temperature: 0.2,
                temperatureFallback: [],
                noContext: false,
                tokenTimestamps: false,
                maxAudioSeconds: 60
            )
        )

        try await adapter.prepare(model: model)
        _ = try await adapter.transcribe(.emptyForTests)
        let options = await runtime.transcriptionOptions()

        XCTAssertEqual(options?.language, "auto")
        XCTAssertEqual(options?.translate, true)
        XCTAssertEqual(options?.temperature, 0.2)
        XCTAssertEqual(options?.usePreviousContext, true)
    }

    func testMultiEngineAdapterUnloadsWhisperBeforePreparingParakeet() async throws {
        let whisper = FakeEngineTranscriber(resultText: "whisper")
        let parakeet = FakeEngineTranscriber(resultText: "parakeet")
        let adapter = MultiEngineRuntimeTranscribingAdapter(
            whisper: whisper,
            parakeet: parakeet,
            paraformer: FakeEngineTranscriber(resultText: "paraformer"),
            sherpaOnnx: FakeEngineTranscriber(resultText: "sherpa-onnx"),
            transcribeCpp: FakeEngineTranscriber(resultText: "transcribe.cpp"),
            mlxAudio: FakeEngineTranscriber(resultText: "mlx-audio"),
            liteRTLM: FakeEngineTranscriber(resultText: "litert-lm")
        )

        try await adapter.prepare(model: Self.activeModel())
        let whisperResult = try await adapter.transcribe(.emptyForTests)
        try await adapter.prepare(model: Self.parakeetActiveModel())
        let parakeetResult = try await adapter.transcribe(.emptyForTests)

        let whisperPrepareCount = await whisper.prepareCallCount()
        let whisperUnloadCount = await whisper.unloadCallCount()
        let parakeetPrepareCount = await parakeet.prepareCallCount()
        XCTAssertEqual(whisperResult.text, "whisper")
        XCTAssertEqual(parakeetResult.text, "parakeet")
        XCTAssertEqual(whisperPrepareCount, 1)
        XCTAssertEqual(whisperUnloadCount, 1)
        XCTAssertEqual(parakeetPrepareCount, 1)
    }

    func testMultiEngineAdapterRoutesToParaformer() async throws {
        let whisper = FakeEngineTranscriber(resultText: "whisper")
        let parakeet = FakeEngineTranscriber(resultText: "parakeet")
        let paraformer = FakeEngineTranscriber(resultText: "中文听写")
        let adapter = MultiEngineRuntimeTranscribingAdapter(
            whisper: whisper,
            parakeet: parakeet,
            paraformer: paraformer,
            sherpaOnnx: FakeEngineTranscriber(resultText: "sherpa-onnx"),
            transcribeCpp: FakeEngineTranscriber(resultText: "transcribe.cpp"),
            mlxAudio: FakeEngineTranscriber(resultText: "mlx-audio"),
            liteRTLM: FakeEngineTranscriber(resultText: "litert-lm")
        )

        try await adapter.prepare(model: Self.activeModel())
        try await adapter.prepare(model: Self.paraformerActiveModel())
        let result = try await adapter.transcribe(.emptyForTests)

        let whisperUnloadCount = await whisper.unloadCallCount()
        let paraformerPrepareCount = await paraformer.prepareCallCount()
        XCTAssertEqual(result.text, "中文听写")
        XCTAssertEqual(whisperUnloadCount, 1)
        XCTAssertEqual(paraformerPrepareCount, 1)
    }

    func testMultiEngineAdapterRoutesToSherpaOnnx() async throws {
        let whisper = FakeEngineTranscriber(resultText: "whisper")
        let sherpaOnnx = FakeEngineTranscriber(resultText: "高速な日本語")
        let adapter = MultiEngineRuntimeTranscribingAdapter(
            whisper: whisper,
            parakeet: FakeEngineTranscriber(resultText: "parakeet"),
            paraformer: FakeEngineTranscriber(resultText: "paraformer"),
            sherpaOnnx: sherpaOnnx,
            transcribeCpp: FakeEngineTranscriber(resultText: "transcribe.cpp"),
            mlxAudio: FakeEngineTranscriber(resultText: "mlx-audio"),
            liteRTLM: FakeEngineTranscriber(resultText: "litert-lm")
        )

        try await adapter.prepare(model: Self.activeModel())
        try await adapter.prepare(model: Self.sherpaOnnxActiveModel())
        let result = try await adapter.transcribe(.emptyForTests)

        let whisperUnloadCount = await whisper.unloadCallCount()
        let sherpaPrepareCount = await sherpaOnnx.prepareCallCount()
        XCTAssertEqual(result.text, "高速な日本語")
        XCTAssertEqual(whisperUnloadCount, 1)
        XCTAssertEqual(sherpaPrepareCount, 1)
    }

    func testMultiEngineAdapterRoutesToTranscribeCpp() async throws {
        let whisper = FakeEngineTranscriber(resultText: "whisper")
        let transcribeCpp = FakeEngineTranscriber(resultText: "nhận dạng nhanh")
        let adapter = MultiEngineRuntimeTranscribingAdapter(
            whisper: whisper,
            parakeet: FakeEngineTranscriber(resultText: "parakeet"),
            paraformer: FakeEngineTranscriber(resultText: "paraformer"),
            sherpaOnnx: FakeEngineTranscriber(resultText: "sherpa-onnx"),
            transcribeCpp: transcribeCpp,
            mlxAudio: FakeEngineTranscriber(resultText: "mlx-audio"),
            liteRTLM: FakeEngineTranscriber(resultText: "litert-lm")
        )

        try await adapter.prepare(model: Self.activeModel())
        try await adapter.prepare(model: Self.transcribeCppActiveModel())
        let result = try await adapter.transcribe(.emptyForTests)

        let whisperUnloadCount = await whisper.unloadCallCount()
        let transcribeCppPrepareCount = await transcribeCpp.prepareCallCount()
        XCTAssertEqual(result.text, "nhận dạng nhanh")
        XCTAssertEqual(whisperUnloadCount, 1)
        XCTAssertEqual(transcribeCppPrepareCount, 1)
    }

    func testMultiEngineAdapterRoutesToMLXAudio() async throws {
        let whisper = FakeEngineTranscriber(resultText: "whisper")
        let mlxAudio = FakeEngineTranscriber(resultText: "local RNNT")
        let adapter = MultiEngineRuntimeTranscribingAdapter(
            whisper: whisper,
            parakeet: FakeEngineTranscriber(resultText: "parakeet"),
            paraformer: FakeEngineTranscriber(resultText: "paraformer"),
            sherpaOnnx: FakeEngineTranscriber(resultText: "sherpa-onnx"),
            transcribeCpp: FakeEngineTranscriber(resultText: "transcribe.cpp"),
            mlxAudio: mlxAudio,
            liteRTLM: FakeEngineTranscriber(resultText: "litert-lm")
        )

        try await adapter.prepare(model: Self.activeModel())
        try await adapter.prepare(model: Self.mlxAudioActiveModel())
        let result = try await adapter.transcribe(.emptyForTests)

        let whisperUnloadCount = await whisper.unloadCallCount()
        let mlxPrepareCount = await mlxAudio.prepareCallCount()
        XCTAssertEqual(result.text, "local RNNT")
        XCTAssertEqual(whisperUnloadCount, 1)
        XCTAssertEqual(mlxPrepareCount, 1)
    }

    func testMultiEngineAdapterRoutesToLiteRTLM() async throws {
        let whisper = FakeEngineTranscriber(resultText: "whisper")
        let liteRTLM = FakeEngineTranscriber(resultText: "local Gemma")
        let adapter = MultiEngineRuntimeTranscribingAdapter(
            whisper: whisper,
            parakeet: FakeEngineTranscriber(resultText: "parakeet"),
            paraformer: FakeEngineTranscriber(resultText: "paraformer"),
            sherpaOnnx: FakeEngineTranscriber(resultText: "sherpa-onnx"),
            transcribeCpp: FakeEngineTranscriber(resultText: "transcribe.cpp"),
            mlxAudio: FakeEngineTranscriber(resultText: "mlx-audio"),
            liteRTLM: liteRTLM
        )

        try await adapter.prepare(model: Self.activeModel())
        try await adapter.prepare(model: Self.liteRTLMActiveModel())
        let result = try await adapter.transcribe(.emptyForTests)

        let whisperUnloadCount = await whisper.unloadCallCount()
        let liteRTPrepareCount = await liteRTLM.prepareCallCount()
        XCTAssertEqual(result.text, "local Gemma")
        XCTAssertEqual(whisperUnloadCount, 1)
        XCTAssertEqual(liteRTPrepareCount, 1)
    }

    func testParaformerAdapterRejectsNonChineseCatalogEntry() async {
        let adapter = ParaformerRuntimeTranscribingAdapter(runtime: ParaformerRuntime())
        var model = Self.paraformerActiveModel()
        model = RuntimeActiveModel(
            id: model.id,
            displayName: model.displayName,
            tier: model.tier,
            localModelPath: model.localModelPath,
            useGPU: model.useGPU,
            threadCount: model.threadCount,
            engine: model.engine,
            variant: model.variant,
            accelerator: model.accelerator,
            artifactLayout: model.artifactLayout,
            runtimeParameters: .legacyEnglishWhisper
        )

        do {
            try await adapter.prepare(model: model)
            XCTFail("Expected a non-Chinese Paraformer entry to fail")
        } catch let error as ParaformerRuntimeError {
            XCTAssertEqual(error, .unsupportedLanguage("en"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSherpaOnnxAdapterUsesCPUAndCapsThreadCountAtFour() async throws {
        let runtime = FakeSherpaOnnxRuntime()
        let adapter = SherpaOnnxRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(model: Self.sherpaOnnxActiveModel())

        let load = await runtime.loadSnapshot()
        XCTAssertEqual(load?.modelID, "reazonspeech-k2-v2-int8")
        XCTAssertEqual(load?.variant, .reazonSpeechK2V2)
        XCTAssertEqual(load?.languageCode, "ja")
        XCTAssertEqual(load?.computeRoute, .cpu)
        XCTAssertEqual(load?.threadCount, 4)
        XCTAssertEqual(load?.warmup, true)
    }

    func testSherpaOnnxAdapterRejectsAutomaticLanguageForJapaneseVariant() async {
        let runtime = FakeSherpaOnnxRuntime()
        let adapter = SherpaOnnxRuntimeTranscribingAdapter(runtime: runtime)
        let model = Self.sherpaOnnxActiveModel()
        let automaticModel = RuntimeActiveModel(
            id: model.id,
            displayName: model.displayName,
            tier: model.tier,
            localModelPath: model.localModelPath,
            useGPU: model.useGPU,
            threadCount: model.threadCount,
            engine: model.engine,
            variant: model.variant,
            accelerator: model.accelerator,
            artifactLayout: model.artifactLayout,
            runtimeParameters: RuntimeParameters(
                language: "ja",
                detectLanguage: true,
                translate: false,
                strategy: "greedy",
                beamSize: 1,
                bestOf: 1,
                temperature: 0,
                temperatureFallback: [],
                noContext: true,
                tokenTimestamps: false,
                maxAudioSeconds: 29
            )
        )

        do {
            try await adapter.prepare(model: automaticModel)
            XCTFail("Expected automatic language to fail for Japanese-only ReazonSpeech")
        } catch let error as SherpaOnnxRuntimeError {
            guard case .unsupportedVariant = error else {
                return XCTFail("Unexpected sherpa-onnx error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let load = await runtime.loadSnapshot()
        XCTAssertNil(load)
    }

    func testSherpaOnnxAdapterAllowsAutomaticLanguageForSenseVoice() async throws {
        let runtime = FakeSherpaOnnxRuntime()
        let adapter = SherpaOnnxRuntimeTranscribingAdapter(runtime: runtime)

        try await adapter.prepare(model: Self.senseVoiceActiveModel())

        let load = await runtime.loadSnapshot()
        XCTAssertEqual(load?.variant, .senseVoiceSmall)
        XCTAssertEqual(load?.languageCode, "auto")
        XCTAssertEqual(load?.computeRoute, .cpu)
        XCTAssertEqual(load?.threadCount, 4)
    }

    func testMultiEngineAdapterRequiresPreparedEngine() async {
        let adapter = MultiEngineRuntimeTranscribingAdapter(
            whisper: FakeEngineTranscriber(resultText: "whisper"),
            parakeet: FakeEngineTranscriber(resultText: "parakeet"),
            paraformer: FakeEngineTranscriber(resultText: "paraformer"),
            sherpaOnnx: FakeEngineTranscriber(resultText: "sherpa-onnx"),
            transcribeCpp: FakeEngineTranscriber(resultText: "transcribe.cpp"),
            mlxAudio: FakeEngineTranscriber(resultText: "mlx-audio"),
            liteRTLM: FakeEngineTranscriber(resultText: "litert-lm")
        )

        do {
            _ = try await adapter.transcribe(.emptyForTests)
            XCTFail("Expected transcribe before prepare to fail")
        } catch let error as RuntimeTranscriptionEngineError {
            XCTAssertEqual(error, .noPreparedEngine)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPostProcessingAdapterUsesV1Pipeline() async {
        let adapter = RuntimePostProcessingAdapter()

        let output = await adapter.process(
            rawText: "hello comma this is textify period",
            preferences: .defaults
        )

        XCTAssertEqual(output, "Hello, this is textify.")
    }

    func testModelResolverReturnsInstalledActiveModelAndReadiness() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let modelURL = try Self.writeCanonicalModelFile(modelData, layout: layout)
        let model = Self.modelEntry(filename: modelURL.lastPathComponent, data: modelData)
        let store = Self.installedStore(model: model, localPath: modelURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertEqual(activeModel?.id, model.id)
        XCTAssertEqual(activeModel?.localModelPath, modelURL.path)
        let readiness = await resolver.readiness(for: activeModel)
        XCTAssertEqual(readiness, .ready(modelID: model.id))
    }

    func testModelResolverReturnsDirectoryEngineAndVerifiesEveryArtifact() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let firstData = Data("coreml model".utf8)
        let secondData = Data("vocabulary".utf8)
        let baseModel = Self.modelEntry(filename: Self.fixtureFilename, data: firstData)
        let files = [
            ModelFile(
                filename: "encoder.bin",
                relativePath: "Encoder.mlmodelc/coremldata.bin",
                url: "https://github.com/Player0109/Textify/releases/download/models-v2/encoder.bin",
                sha256: Self.sha256Hex(firstData),
                sizeBytes: Int64(firstData.count)
            ),
            ModelFile(
                filename: "vocabulary.json",
                relativePath: "parakeet_vocab.json",
                url: "https://github.com/Player0109/Textify/releases/download/models-v2/vocabulary.json",
                sha256: Self.sha256Hex(secondData),
                sizeBytes: Int64(secondData.count)
            )
        ]
        let model = ModelEntry(
            id: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet V3",
            tier: "fast",
            description: "Local multilingual dictation.",
            sizeBytes: Int64(firstData.count + secondData.count),
            files: files,
            licenses: baseModel.licenses,
            provenance: baseModel.provenance,
            runtimeParameters: .legacyEnglishWhisper,
            hallucinationThresholds: baseModel.hallucinationThresholds,
            minAppVersion: "0.2.0",
            runtime: ModelRuntimeDescriptor(
                engine: .fluidAudioParakeet,
                variant: ParakeetModelVariant.tdtV3.rawValue,
                accelerator: .coreMLNeuralEngine,
                artifactLayout: .modelDirectory
            ),
            capabilities: ModelCapabilities(
                languages: ["en", "es"],
                supportsTranslation: false,
                supportsCustomVocabulary: false
            )
        )
        let firstURL = try layout.installedArtifactURL(
            modelID: model.id,
            relativePath: try XCTUnwrap(files[0].relativePath)
        )
        let secondURL = try layout.installedArtifactURL(
            modelID: model.id,
            relativePath: try XCTUnwrap(files[1].relativePath)
        )
        try FileManager.default.createDirectory(
            at: firstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try firstData.write(to: firstURL)
        try secondData.write(to: secondURL)
        let store = InstalledModelsStore(records: [
            InstalledModelRecord(
                model: model,
                installedAt: "2026-07-19T00:00:00Z",
                localFilesByManifestFilename: [
                    files[0].filename: firstURL.path,
                    files[1].filename: secondURL.path
                ]
            )
        ])
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)
        let ready = await resolver.readiness(for: activeModel)

        XCTAssertEqual(activeModel?.engine, .fluidAudioParakeet)
        XCTAssertEqual(activeModel?.accelerator, .coreMLNeuralEngine)
        XCTAssertEqual(
            activeModel?.localModelPath,
            try layout.installedModelDirectory(modelID: model.id).path
        )
        XCTAssertEqual(ready, .ready(modelID: model.id))

        try FileManager.default.removeItem(at: secondURL)
        let missing = await resolver.readiness(for: activeModel)
        XCTAssertEqual(missing, .missing(modelID: model.id))
    }

    func testModelResolverCachesVerifiedFileWhileMetadataIsUnchanged() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let modelURL = try Self.writeCanonicalModelFile(modelData, layout: layout)
        let model = Self.modelEntry(filename: modelURL.lastPathComponent, data: modelData)
        let store = Self.installedStore(model: model, localPath: modelURL.path)
        let fixture = InstalledStoreFixture(store: store)
        let hashCounter = FileHashCounter(result: Self.sha256Hex(modelData))
        let resolver = RuntimeModelResolverAdapter(
            layout: layout,
            loadStore: { fixture.store },
            hashFile: { url in try hashCounter.hash(url) }
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id
        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        let first = await resolver.readiness(for: activeModel)
        let second = await resolver.readiness(for: activeModel)

        XCTAssertEqual(first, .ready(modelID: model.id))
        XCTAssertEqual(second, .ready(modelID: model.id))
        XCTAssertEqual(hashCounter.callCount, 1)
    }

    func testModelResolverIgnoresStoredPathOutsideCanonicalLayout() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let canonicalURL = try layout.installedFileURL(
            modelID: Self.fixtureModelID,
            filename: Self.fixtureFilename
        )
        let model = Self.modelEntry(filename: canonicalURL.lastPathComponent, data: modelData)
        let outsideURL = directory.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).bin")
        let store = Self.installedStore(model: model, localPath: outsideURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertNil(activeModel)
    }

    func testModelResolverReportsMissingWhenCanonicalFileIsAbsent() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let canonicalURL = try layout.installedFileURL(
            modelID: Self.fixtureModelID,
            filename: Self.fixtureFilename
        )
        let model = Self.modelEntry(filename: canonicalURL.lastPathComponent, data: modelData)
        let store = Self.installedStore(model: model, localPath: canonicalURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertEqual(activeModel?.localModelPath, canonicalURL.path)
        let readiness = await resolver.readiness(for: activeModel)
        XCTAssertEqual(readiness, .missing(modelID: model.id))
    }

    func testModelResolverFailsReadinessForSizeMismatch() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let modelURL = try Self.writeCanonicalModelFile(modelData, layout: layout)
        let model = Self.modelEntry(
            filename: modelURL.lastPathComponent,
            data: modelData,
            sizeBytes: Int64(modelData.count + 1)
        )
        let store = Self.installedStore(model: model, localPath: modelURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)
        let readiness = await resolver.readiness(for: activeModel)

        XCTAssertEqual(readiness, .failed(modelID: model.id, reason: .checksumFailed))
    }

    func testModelResolverFailsReadinessForChecksumMismatch() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let modelData = Data("model".utf8)
        let modelURL = try Self.writeCanonicalModelFile(modelData, layout: layout)
        let model = Self.modelEntry(
            filename: modelURL.lastPathComponent,
            data: modelData,
            sha256: String(repeating: "0", count: 64)
        )
        let store = Self.installedStore(model: model, localPath: modelURL.path)
        let resolver = Self.modelResolver(layout: layout, store: store)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)
        let readiness = await resolver.readiness(for: activeModel)

        XCTAssertEqual(readiness, .failed(modelID: model.id, reason: .checksumFailed))
    }

    func testModelResolverDoesNotResolveModelOutsideInstalledStore() async {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = Self.modelResolver(
            layout: ModelStorageLayout(rootDirectory: directory),
            store: InstalledModelsStore()
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = "arbitrary-local-model"

        let activeModel = await resolver.resolveActiveModel(preferences: preferences)

        XCTAssertNil(activeModel)
        let readiness = await resolver.readiness(for: activeModel)
        XCTAssertEqual(readiness, .noActiveModel)
    }

    func testPermissionAdapterIgnoresDeniedInputMonitoring() async {
        let adapter = SystemRuntimePermissionAdapter(
            microphone: MicrophonePermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            inputMonitoring: InputMonitoringPermissionClient(
                status: { .denied },
                requestAccess: { .denied }
            ),
            accessibility: AccessibilityTrustClient(status: { .notTrusted })
        )

        let snapshot = await adapter.permissionSnapshot()

        XCTAssertEqual(snapshot.microphone, .granted)
        XCTAssertEqual(snapshot.accessibility, .denied)
        XCTAssertEqual(snapshot.inputMonitoring, .granted)
    }

    func testPermissionAdapterIgnoresUnknownInputMonitoring() async {
        let adapter = SystemRuntimePermissionAdapter(
            microphone: MicrophonePermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            inputMonitoring: InputMonitoringPermissionClient(
                status: { .unknown },
                requestAccess: { .denied }
            ),
            accessibility: AccessibilityTrustClient(status: { .trusted })
        )

        let snapshot = await adapter.permissionSnapshot()

        XCTAssertEqual(snapshot.microphone, .granted)
        XCTAssertEqual(snapshot.accessibility, .granted)
        XCTAssertEqual(snapshot.inputMonitoring, .granted)
    }

    func testPermissionAdapterMapsFreshMicrophonePermissionToUnknown() async {
        let adapter = SystemRuntimePermissionAdapter(
            microphone: MicrophonePermissionClient(
                status: { .notDetermined },
                requestAccess: { .granted }
            ),
            inputMonitoring: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            accessibility: AccessibilityTrustClient(status: { .trusted })
        )

        let snapshot = await adapter.permissionSnapshot()

        XCTAssertEqual(snapshot.microphone, .unknown)
        XCTAssertEqual(snapshot.accessibility, .granted)
        XCTAssertEqual(snapshot.inputMonitoring, .granted)
    }

    func testSystemRuntimeClockReturnsMillisecondsAndSleepsForNonNegativeDurations() async {
        let clock = SystemRuntimeClock()

        XCTAssertGreaterThan(clock.nowMilliseconds(), 0)
        await clock.sleep(milliseconds: -10)
        await clock.sleep(milliseconds: 0)
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyRuntimeTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static let fixtureModelID = "ggml-small.en-q5_1"
    private static let fixtureFilename = "ggml-small.en-q5_1.bin"

    private static func activeModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: fixtureModelID,
            displayName: "Balanced - Whisper small.en",
            tier: "balanced",
            localModelPath: "/tmp/textify-model.bin",
            useGPU: true,
            threadCount: 1
        )
    }

    private static func parakeetActiveModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "parakeet-v3-int8",
            displayName: "Parakeet V3",
            tier: "fast",
            localModelPath: "/tmp/parakeet-tdt-0.6b-v3",
            useGPU: false,
            threadCount: nil,
            engine: .fluidAudioParakeet,
            variant: ParakeetModelVariant.tdtV3.rawValue,
            accelerator: .coreMLNeuralEngine,
            artifactLayout: .modelDirectory,
            runtimeParameters: RuntimeParameters(
                language: "en",
                detectLanguage: true,
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

    private static func paraformerActiveModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "paraformer-large-zh-int8",
            displayName: "Paraformer Chinese",
            tier: "specialist",
            localModelPath: "/tmp/paraformer-large-zh",
            useGPU: false,
            threadCount: nil,
            engine: .fluidAudioParaformer,
            variant: ParaformerModelVariant.largeZhInt8.rawValue,
            accelerator: .coreMLNeuralEngine,
            artifactLayout: .modelDirectory,
            runtimeParameters: RuntimeParameters(
                language: "zh",
                detectLanguage: false,
                translate: false,
                strategy: "greedy",
                beamSize: 1,
                bestOf: 1,
                temperature: 0,
                temperatureFallback: [],
                noContext: true,
                tokenTimestamps: false,
                maxAudioSeconds: 18
            )
        )
    }

    private static func sherpaOnnxActiveModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "reazonspeech-k2-v2-int8",
            displayName: "Fast - ReazonSpeech Japanese",
            tier: "fast",
            localModelPath: "/tmp/reazonspeech-k2-v2-int8",
            useGPU: false,
            threadCount: 8,
            engine: .sherpaOnnx,
            variant: SherpaOnnxModelVariant.reazonSpeechK2V2.rawValue,
            accelerator: .cpu,
            artifactLayout: .modelDirectory,
            runtimeParameters: RuntimeParameters(
                language: "ja",
                detectLanguage: false,
                translate: false,
                strategy: "greedy",
                beamSize: 1,
                bestOf: 1,
                temperature: 0,
                temperatureFallback: [],
                noContext: true,
                tokenTimestamps: false,
                maxAudioSeconds: 29
            )
        )
    }

    private static func senseVoiceActiveModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "sensevoice-small-int8-2024-07-17",
            displayName: "Accurate - SenseVoice Asian",
            tier: "accurate",
            localModelPath: "/tmp/sensevoice-small-int8-2024-07-17",
            useGPU: false,
            threadCount: 8,
            engine: .sherpaOnnx,
            variant: SherpaOnnxModelVariant.senseVoiceSmall.rawValue,
            accelerator: .cpu,
            artifactLayout: .modelDirectory,
            runtimeParameters: RuntimeParameters(
                language: "auto",
                detectLanguage: true,
                translate: false,
                strategy: "greedy",
                beamSize: 1,
                bestOf: 1,
                temperature: 0,
                temperatureFallback: [],
                noContext: true,
                tokenTimestamps: false,
                maxAudioSeconds: 29
            )
        )
    }

    private static func transcribeCppActiveModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "funasr-mlt-nano-2512-q8",
            displayName: "Specialist - Fun-ASR Multilingual",
            tier: "specialist",
            localModelPath: "/tmp/Fun-ASR-MLT-Nano-2512-Q8_0.gguf",
            useGPU: true,
            threadCount: 4,
            engine: .transcribeCpp,
            variant: TranscribeCppModelVariant.funASRMLTNanoQ8.rawValue,
            accelerator: .metalGPU,
            artifactLayout: .singleFile,
            runtimeParameters: RuntimeParameters(
                language: "vi",
                detectLanguage: false,
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

    private static func mlxAudioActiveModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "parakeet-rnnt-1.1b",
            displayName: "Experimental - Parakeet RNNT 1.1B",
            tier: "experimental",
            localModelPath: "/tmp/parakeet-rnnt-1.1b",
            useGPU: true,
            threadCount: nil,
            engine: .mlxAudio,
            variant: MLXAudioModelVariant.parakeetRNNT1_1B.rawValue,
            accelerator: .metalGPU,
            artifactLayout: .modelDirectory,
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
                maxAudioSeconds: 60
            )
        )
    }

    private static func liteRTLMActiveModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "gemma-4-12b-litertlm",
            displayName: "Experimental - Gemma 4 12B",
            tier: "experimental",
            localModelPath: "/tmp/gemma-4-12B-it.litertlm",
            useGPU: true,
            threadCount: nil,
            engine: .liteRTLM,
            variant: LiteRTLMModelVariant.gemma4_12B.rawValue,
            accelerator: .metalGPU,
            artifactLayout: .singleFile,
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

    private static func writeCanonicalModelFile(
        _ data: Data,
        layout: ModelStorageLayout,
        filename: String = fixtureFilename
    ) throws -> URL {
        let modelURL = try layout.installedFileURL(modelID: fixtureModelID, filename: filename)
        try FileManager.default.createDirectory(
            at: modelURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: modelURL)
        return modelURL
    }

    private static func installedStore(model: ModelEntry, localPath: String) -> InstalledModelsStore {
        InstalledModelsStore(records: [
            InstalledModelRecord(
                model: model,
                installedAt: "2026-07-03T00:00:00Z",
                localFilesByManifestFilename: [model.files[0].filename: localPath]
            )
        ])
    }

    private static func modelResolver(
        layout: ModelStorageLayout,
        store: InstalledModelsStore
    ) -> RuntimeModelResolverAdapter {
        let fixture = InstalledStoreFixture(store: store)
        return RuntimeModelResolverAdapter(layout: layout) {
            fixture.store
        }
    }

    private static func modelEntry(
        filename: String,
        data: Data,
        sha256: String? = nil,
        sizeBytes: Int64? = nil
    ) -> ModelEntry {
        ModelEntry(
            id: fixtureModelID,
            displayName: "Balanced - Whisper small.en",
            tier: "balanced",
            description: "Balanced local English dictation.",
            sizeBytes: sizeBytes ?? Int64(data.count),
            files: [
                ModelFile(
                    filename: filename,
                    url: "https://github.com/Player0109/Textify/releases/download/models-v1/\(filename)",
                    sha256: sha256 ?? sha256Hex(data),
                    sizeBytes: sizeBytes ?? Int64(data.count)
                )
            ],
            licenses: [],
            provenance: ModelProvenance(
                sourceName: "ggerganov/whisper.cpp",
                sourceUrl: "https://huggingface.co/ggerganov/whisper.cpp",
                sourceRevision: "fixture",
                sourceFile: filename,
                originalModelName: "OpenAI Whisper small.en",
                originalModelUrl: "https://huggingface.co/openai/whisper-small.en",
                mirroredBy: "Textify",
                mirroredAt: "2026-07-03"
            ),
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
                maxAudioSeconds: 60
            ),
            hallucinationThresholds: HallucinationThresholds(
                noSpeechProbabilityMax: 0.60,
                avgLogProbabilityMin: -1.00,
                compressionRatioMax: 2.40
            ),
            minAppVersion: "0.1.0"
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum FakeWhisperRuntimeError: Error {
    case loadFailed
}

private struct InstalledStoreFixture: @unchecked Sendable {
    let store: InstalledModelsStore
}

private final class FileHashCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let result: String
    private var calls = 0

    init(result: String) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func hash(_ url: URL) throws -> String {
        lock.lock()
        calls += 1
        lock.unlock()
        return result
    }
}

private actor FakeWhisperRuntime: WhisperRuntimeLoading {
    private var mutableState: WhisperRuntimeState
    private var mutableLoadError: Error?
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private let suspendLoad: Bool
    private var loadCalls = 0
    private var options: WhisperTranscriptionOptions?

    init(
        initialState: WhisperRuntimeState = .noModel,
        suspendLoad: Bool = false,
        loadError: Error? = nil
    ) {
        self.mutableState = initialState
        self.suspendLoad = suspendLoad
        self.mutableLoadError = loadError
    }

    var state: WhisperRuntimeState {
        mutableState
    }

    func load(
        modelID: String,
        modelPath: String,
        useGPU: Bool,
        threadCount: Int,
        warmup: Bool
    ) async throws {
        loadCalls += 1
        if let mutableLoadError {
            throw mutableLoadError
        }

        mutableState = .loading(modelID: modelID)
        if suspendLoad {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        mutableState = .ready(modelID: modelID)
    }

    func transcribe(_ audio: TranscriptionAudioBuffer, options: WhisperTranscriptionOptions) async throws -> TranscriptionResult {
        self.options = options
        return TranscriptionResult(
            text: "hello",
            noSpeechProbability: 0,
            averageLogProbability: 0,
            compressionRatio: 0
        )
    }

    func unload() {
        mutableState = .noModel
    }

    func transcriptionOptions() -> WhisperTranscriptionOptions? {
        options
    }

    func loadCallCount() -> Int {
        loadCalls
    }

    func setLoadError(_ error: Error?) {
        mutableLoadError = error
    }

    func releaseLoads() {
        let pendingContinuations = continuations
        continuations.removeAll()
        for continuation in pendingContinuations {
            continuation.resume()
        }
    }
}

private actor FakeEngineTranscriber: RuntimeEngineTranscribing {
    private let resultText: String
    private var mutableReadiness: RuntimeModelReadiness = .noActiveModel
    private var prepareCalls = 0
    private var unloadCalls = 0

    init(resultText: String) {
        self.resultText = resultText
    }

    var readiness: RuntimeModelReadiness {
        mutableReadiness
    }

    func prepare(model: RuntimeActiveModel) {
        prepareCalls += 1
        mutableReadiness = .ready(modelID: model.id)
    }

    func transcribe(_ audio: TranscriptionAudioBuffer) -> TranscriptionResult {
        TranscriptionResult(
            text: resultText,
            noSpeechProbability: 0,
            averageLogProbability: 0,
            compressionRatio: 1
        )
    }

    func unload() {
        unloadCalls += 1
        mutableReadiness = .noActiveModel
    }

    func prepareCallCount() -> Int {
        prepareCalls
    }

    func unloadCallCount() -> Int {
        unloadCalls
    }
}

private actor FakeSherpaOnnxRuntime: SherpaOnnxRuntimeLoading {
    struct Load: Sendable {
        let modelID: String
        let modelDirectory: String
        let variant: SherpaOnnxModelVariant
        let languageCode: String
        let computeRoute: SherpaOnnxComputeRoute
        let threadCount: Int
        let warmup: Bool
    }

    private var mutableState: SherpaOnnxRuntimeState = .noModel
    private var load: Load?

    var state: SherpaOnnxRuntimeState {
        mutableState
    }

    func load(
        modelID: String,
        modelDirectory: String,
        variant: SherpaOnnxModelVariant,
        languageCode: String,
        computeRoute: SherpaOnnxComputeRoute,
        threadCount: Int,
        warmup: Bool
    ) {
        load = Load(
            modelID: modelID,
            modelDirectory: modelDirectory,
            variant: variant,
            languageCode: languageCode,
            computeRoute: computeRoute,
            threadCount: threadCount,
            warmup: warmup
        )
        mutableState = .ready(modelID: modelID)
    }

    func transcribe(_ audio: TranscriptionAudioBuffer) -> TranscriptionResult {
        TranscriptionResult(
            text: "高速な日本語",
            noSpeechProbability: 0,
            averageLogProbability: -0.2,
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
