@preconcurrency import AVFoundation
import Foundation
@testable import TextifyTranscription
import XCTest

final class SherpaOnnxRuntimeTests: XCTestCase {
    func testLoadWarmsAndTranscribesWithResidentSession() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelDirectory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelDirectory)
        }

        let session = FakeSherpaOnnxSession()
        let loads = SherpaOnnxLoadRecorder()
        let runtime = SherpaOnnxRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: SherpaOnnxRuntimeBackend {
                runtimeDirectory,
                modelDirectory,
                variant,
                languageCode,
                computeRoute,
                threadCount in
                await loads.record(
                    runtimeDirectory: runtimeDirectory,
                    modelDirectory: modelDirectory,
                    variant: variant,
                    languageCode: languageCode,
                    computeRoute: computeRoute,
                    threadCount: threadCount
                )
                return session
            }
        )

        try await runtime.load(
            modelID: "reazonspeech-k2-v2-int8",
            modelDirectory: modelDirectory.path,
            variant: .reazonSpeechK2V2
        )

        let state = await runtime.state
        XCTAssertEqual(state, .ready(modelID: "reazonspeech-k2-v2-int8"))
        let load = await loads.snapshot()
        XCTAssertEqual(load?.runtimeDirectory.standardizedFileURL, runtimeDirectory.standardizedFileURL)
        XCTAssertEqual(load?.modelDirectory.standardizedFileURL, modelDirectory.standardizedFileURL)
        XCTAssertEqual(load?.variant, .reazonSpeechK2V2)
        XCTAssertEqual(load?.languageCode, "auto")
        XCTAssertEqual(load?.computeRoute, .cpu)
        XCTAssertEqual(load?.threadCount, 4)
        let warmupCalls = await session.callsSnapshot()
        XCTAssertEqual(warmupCalls.map(\.sampleCount), [6_400])
        XCTAssertEqual(warmupCalls.map(\.sampleRate), [16_000])

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 16_000))
        )

        XCTAssertEqual(result.text, "日本語の音声認識")
        XCTAssertEqual(result.noSpeechProbability, 0)
        XCTAssertEqual(result.averageLogProbability, -0.25, accuracy: 0.000_001)
        XCTAssertEqual(result.timing?.audioDurationMs, 1_000)
        XCTAssertNotNil(result.timing?.inferenceDurationMs)
        let calls = await session.callsSnapshot()
        XCTAssertEqual(calls.map(\.sampleCount), [6_400, 16_000])
    }

    func testLoadRejectsMissingRuntimeDirectoryBeforeBackendCall() async throws {
        let modelDirectory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: modelDirectory) }
        let loads = SherpaOnnxLoadRecorder()
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyMissingSherpaRuntime-\(UUID().uuidString)")
            .path
        let runtime = SherpaOnnxRuntime(
            runtimeDirectory: missingPath,
            backend: SherpaOnnxRuntimeBackend { runtimeDirectory, modelDirectory, variant, languageCode, computeRoute, threadCount in
                await loads.record(
                    runtimeDirectory: runtimeDirectory,
                    modelDirectory: modelDirectory,
                    variant: variant,
                    languageCode: languageCode,
                    computeRoute: computeRoute,
                    threadCount: threadCount
                )
                return FakeSherpaOnnxSession()
            }
        )

        do {
            try await runtime.load(
                modelID: "reazonspeech-k2-v2-int8",
                modelDirectory: modelDirectory.path,
                variant: .reazonSpeechK2V2
            )
            XCTFail("Expected missing runtime directory to fail")
        } catch let error as SherpaOnnxRuntimeError {
            XCTAssertEqual(error, .missingRuntimeDirectory(missingPath))
        }

        let invocation = await loads.snapshot()
        let state = await runtime.state
        XCTAssertNil(invocation)
        XCTAssertEqual(
            state,
            .failed(modelID: "reazonspeech-k2-v2-int8", reason: .missingRuntimeDirectory)
        )
    }

    func testWarmupFailureUnloadsSession() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelDirectory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelDirectory)
        }
        let session = FakeSherpaOnnxSession(errorOnCall: 1)
        let runtime = SherpaOnnxRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: SherpaOnnxRuntimeBackend { _, _, _, _, _, _ in session }
        )

        do {
            try await runtime.load(
                modelID: "reazonspeech-k2-v2-int8",
                modelDirectory: modelDirectory.path,
                variant: .reazonSpeechK2V2
            )
            XCTFail("Expected warmup failure")
        } catch let error as SherpaOnnxRuntimeError {
            guard case .warmupFailed = error else {
                return XCTFail("Unexpected sherpa-onnx error: \(error)")
            }
        }

        let unloadCount = await session.unloadCountSnapshot()
        let state = await runtime.state
        XCTAssertEqual(unloadCount, 1)
        XCTAssertEqual(
            state,
            .failed(modelID: "reazonspeech-k2-v2-int8", reason: .warmupFailed)
        )
    }

    func testTranscriptionRejectsNonCanonicalEmptyAndOversizedAudio() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelDirectory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelDirectory)
        }
        let session = FakeSherpaOnnxSession()
        let runtime = SherpaOnnxRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: SherpaOnnxRuntimeBackend { _, _, _, _, _, _ in session }
        )
        try await runtime.load(
            modelID: "reazonspeech-k2-v2-int8",
            modelDirectory: modelDirectory.path,
            variant: .reazonSpeechK2V2,
            warmup: false
        )

        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(sampleRate: 44_100, channelCount: 2, samples: [0])
            )
            XCTFail("Expected invalid audio format")
        } catch let error as SherpaOnnxRuntimeError {
            XCTAssertEqual(error, .invalidAudioFormat(sampleRate: 44_100, channelCount: 2))
        }

        do {
            _ = try await runtime.transcribe(.emptyForTests)
            XCTFail("Expected empty audio to fail")
        } catch let error as SherpaOnnxRuntimeError {
            XCTAssertEqual(error, .emptyAudio)
        }

        let actualSamples = SherpaOnnxRuntime.maximumAudioSamples + 1
        do {
            _ = try await runtime.transcribe(
                TranscriptionAudioBuffer(samples: Array(repeating: 0, count: actualSamples))
            )
            XCTFail("Expected oversized audio to fail")
        } catch let error as SherpaOnnxRuntimeError {
            XCTAssertEqual(
                error,
                .audioTooLong(
                    maximumSamples: SherpaOnnxRuntime.maximumAudioSamples,
                    actualSamples: actualSamples
                )
            )
        }

        let calls = await session.callsSnapshot()
        XCTAssertEqual(calls, [])
    }

    func testPunctuationOnlyTranscriptIsClassifiedAsNoSpeech() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelDirectory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelDirectory)
        }
        let session = FakeSherpaOnnxSession(resultTexts: ["。"])
        let runtime = SherpaOnnxRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: SherpaOnnxRuntimeBackend { _, _, _, _, _, _ in session }
        )
        try await runtime.load(
            modelID: "sensevoice-small-int8-2024-07-17",
            modelDirectory: modelDirectory.path,
            variant: .senseVoiceSmall,
            languageCode: "auto",
            warmup: false
        )

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 16_000))
        )

        XCTAssertEqual(result.text, "。")
        XCTAssertEqual(result.noSpeechProbability, 1)
    }

    func testLowEnergySilenceHallucinationIsClassifiedAsNoSpeech() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelDirectory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelDirectory)
        }
        let session = FakeSherpaOnnxSession(resultTexts: ["我."])
        let runtime = SherpaOnnxRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: SherpaOnnxRuntimeBackend { _, _, _, _, _, _ in session }
        )
        try await runtime.load(
            modelID: "sensevoice-small-int8-2024-07-17",
            modelDirectory: modelDirectory.path,
            variant: .senseVoiceSmall,
            languageCode: "auto",
            warmup: false
        )

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.000_5, count: 16_000))
        )

        XCTAssertEqual(result.text, "我.")
        XCTAssertEqual(result.noSpeechProbability, 1)
    }

    func testLoadReloadsSameModelWhenLanguageChanges() async throws {
        let runtimeDirectory = try Self.makeTemporaryDirectory()
        let modelDirectory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: modelDirectory)
        }
        let session = FakeSherpaOnnxSession()
        let loads = SherpaOnnxLoadRecorder()
        let runtime = SherpaOnnxRuntime(
            runtimeDirectory: runtimeDirectory.path,
            backend: SherpaOnnxRuntimeBackend {
                runtimeDirectory,
                modelDirectory,
                variant,
                languageCode,
                computeRoute,
                threadCount in
                await loads.record(
                    runtimeDirectory: runtimeDirectory,
                    modelDirectory: modelDirectory,
                    variant: variant,
                    languageCode: languageCode,
                    computeRoute: computeRoute,
                    threadCount: threadCount
                )
                return session
            }
        )

        try await runtime.load(
            modelID: "sensevoice-small-int8-2024-07-17",
            modelDirectory: modelDirectory.path,
            variant: .senseVoiceSmall,
            languageCode: "en",
            warmup: false
        )
        try await runtime.load(
            modelID: "sensevoice-small-int8-2024-07-17",
            modelDirectory: modelDirectory.path,
            variant: .senseVoiceSmall,
            languageCode: "ja",
            warmup: false
        )

        let invocations = await loads.snapshots()
        let unloadCount = await session.unloadCountSnapshot()
        XCTAssertEqual(invocations.map(\.languageCode), ["en", "ja"])
        XCTAssertEqual(unloadCount, 1)
    }

    func testNativeBackendTranscribesPinnedReazonModelWhenIntegrationTestsAreEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TEXTIFY_RUN_SHERPA_ONNX_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set TEXTIFY_RUN_SHERPA_ONNX_INTEGRATION_TESTS=1 to run the local ReazonSpeech smoke test.")
        }
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runtimeDirectory = workspace
            .appendingPathComponent("Vendor/sherpa-onnx/v1.13.2/lib", isDirectory: true)
        let modelDirectory = workspace
            .appendingPathComponent(".build/model-artifact-audit/reazonspeech-k2-v2-int8", isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw XCTSkip("The pinned ReazonSpeech audit model is not present.")
        }
        let runtime = SherpaOnnxRuntime(runtimeDirectory: runtimeDirectory.path)
        try await runtime.load(
            modelID: "reazonspeech-k2-v2-int8",
            modelDirectory: modelDirectory.path,
            variant: .reazonSpeechK2V2
        )

        let audioURL = workspace
            .appendingPathComponent(".build/dataset-audit/jsut-basic5000/basic5000/wav/BASIC5000_4503.wav")
        let audio = try Self.loadPCMMono16K(from: audioURL)
        let result = try await runtime.transcribe(audio)

        XCTAssertEqual(result.text, "羨ましいほどの落ち着きぶりであった")
        XCTAssertLessThan(result.averageLogProbability, 0)
        XCTAssertLessThan(result.timing?.inferenceDurationMs ?? .max, 700)
        await runtime.unload()
    }

    func testNativeBackendTranscribesAndRejectsSenseVoiceSilenceWhenIntegrationTestsAreEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TEXTIFY_RUN_SHERPA_ONNX_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set TEXTIFY_RUN_SHERPA_ONNX_INTEGRATION_TESTS=1 to run the local SenseVoiceSmall smoke test.")
        }
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runtimeDirectory = workspace
            .appendingPathComponent("Vendor/sherpa-onnx/v1.13.2/lib", isDirectory: true)
        let modelDirectory = workspace
            .appendingPathComponent(".build/model-artifact-audit/sensevoice-small-int8-2024-07-17", isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw XCTSkip("The pinned SenseVoiceSmall audit model is not present.")
        }
        let runtime = SherpaOnnxRuntime(runtimeDirectory: runtimeDirectory.path)
        try await runtime.load(
            modelID: "sensevoice-small-int8-2024-07-17",
            modelDirectory: modelDirectory.path,
            variant: .senseVoiceSmall,
            languageCode: "auto"
        )

        let audioURL = workspace
            .appendingPathComponent(".build/dataset-audit/jsut-basic5000/basic5000/wav/BASIC5000_4503.wav")
        let audio = try Self.loadPCMMono16K(from: audioURL)
        let result = try await runtime.transcribe(audio)
        XCTAssertEqual(
            result.text.replacingOccurrences(of: " ", with: ""),
            "羨ましいほどの落ち着きぶりであった。"
        )
        XCTAssertLessThan(result.timing?.inferenceDurationMs ?? .max, 700)

        let silence = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 5 * 16_000))
        )
        XCTAssertEqual(silence.noSpeechProbability, 1)
        await runtime.unload()
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifySherpaOnnxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func loadPCMMono16K(from sourceURL: URL) throws -> TranscriptionAudioBuffer {
        let file = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = file.processingFormat
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw SherpaIntegrationAudioError.allocationFailed
        }
        try file.read(into: sourceBuffer)

        guard let canonicalFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceFormat, to: canonicalFormat) else {
            throw SherpaIntegrationAudioError.converterUnavailable
        }
        let ratio = canonicalFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + 1_024
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: canonicalFormat,
            frameCapacity: capacity
        ) else {
            throw SherpaIntegrationAudioError.allocationFailed
        }

        let input = SherpaIntegrationConverterInput(buffer: sourceBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            input.next(status: inputStatus)
        }
        guard status != .error, conversionError == nil,
              let channel = converted.floatChannelData?.pointee else {
            throw SherpaIntegrationAudioError.conversionFailed
        }
        return TranscriptionAudioBuffer(
            samples: Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        )
    }
}

private final class SherpaIntegrationConverterInput: @unchecked Sendable {
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

private enum SherpaIntegrationAudioError: Error {
    case allocationFailed
    case converterUnavailable
    case conversionFailed
}

private enum FakeSherpaOnnxError: Error {
    case failed
}

private actor FakeSherpaOnnxSession: SherpaOnnxRuntimeSession {
    struct Call: Equatable, Sendable {
        let sampleCount: Int
        let sampleRate: Int
    }

    private let errorOnCall: Int?
    private let resultTexts: [String]?
    private var calls: [Call] = []
    private var unloadCount = 0

    init(errorOnCall: Int? = nil, resultTexts: [String]? = nil) {
        self.errorOnCall = errorOnCall
        self.resultTexts = resultTexts
    }

    func transcribe(samples: [Float], sampleRate: Int) throws -> SherpaOnnxSessionResult {
        calls.append(Call(sampleCount: samples.count, sampleRate: sampleRate))
        if calls.count == errorOnCall {
            throw FakeSherpaOnnxError.failed
        }
        let defaultText = calls.count == 1 ? "" : "日本語の音声認識"
        let text = resultTexts.flatMap { calls.count <= $0.count ? $0[calls.count - 1] : nil }
            ?? defaultText
        return SherpaOnnxSessionResult(
            text: text,
            averageLogProbability: text.unicodeScalars.contains {
                CharacterSet.alphanumerics.contains($0)
            } ? -0.25 : -10
        )
    }

    func unload() {
        unloadCount += 1
    }

    func callsSnapshot() -> [Call] {
        calls
    }

    func unloadCountSnapshot() -> Int {
        unloadCount
    }
}

private actor SherpaOnnxLoadRecorder {
    struct Invocation: Sendable {
        let runtimeDirectory: URL
        let modelDirectory: URL
        let variant: SherpaOnnxModelVariant
        let languageCode: String
        let computeRoute: SherpaOnnxComputeRoute
        let threadCount: Int
    }

    private var invocations: [Invocation] = []

    func record(
        runtimeDirectory: URL,
        modelDirectory: URL,
        variant: SherpaOnnxModelVariant,
        languageCode: String,
        computeRoute: SherpaOnnxComputeRoute,
        threadCount: Int
    ) {
        invocations.append(Invocation(
            runtimeDirectory: runtimeDirectory,
            modelDirectory: modelDirectory,
            variant: variant,
            languageCode: languageCode,
            computeRoute: computeRoute,
            threadCount: threadCount
        ))
    }

    func snapshot() -> Invocation? {
        invocations.last
    }

    func snapshots() -> [Invocation] {
        invocations
    }
}
