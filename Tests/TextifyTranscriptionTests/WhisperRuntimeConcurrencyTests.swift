import Foundation
@testable import TextifyTranscription
import XCTest

final class WhisperRuntimeConcurrencyTests: XCTestCase {
    func testWarmupDoesNotSetLastUserInferenceMetric() async throws {
        let modelURL = try makeTemporaryModelFile()
        defer { try? FileManager.default.removeItem(at: modelURL) }

        let runtime = WhisperRuntime(backend: ImmediateWhisperBackend().backend)

        try await runtime.load(modelID: "test-model", modelPath: modelURL.path, warmup: true)
        let snapshot = await runtime.snapshot()

        XCTAssertNotNil(snapshot.metrics.lastWarmupDurationMs)
        XCTAssertNil(snapshot.metrics.lastInferenceDurationMs)
    }

    func testRejectsUnsupportedTemperatureFallbackBeforeModelLoad() async {
        let runtime = WhisperRuntime()
        let options = WhisperTranscriptionOptions(
            language: "en",
            translate: false,
            temperature: 0,
            temperatureFallback: [0.2],
            usePreviousContext: false,
            initialPrompt: nil
        )

        do {
            _ = try await runtime.transcribe(.emptyForTests, options: options)
            XCTFail("Expected non-empty temperature fallback to be rejected")
        } catch let error as WhisperRuntimeError {
            XCTAssertEqual(error, .unsupportedTemperatureFallback)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnloadWaitsForSecondConcurrentTranscription() async throws {
        let modelURL = try makeTemporaryModelFile()
        defer { try? FileManager.default.removeItem(at: modelURL) }

        let backend = BlockingWhisperBackend()
        defer {
            backend.allowFirstTranscriptionToFinish()
            backend.allowSecondTranscriptionToFinish()
        }

        let runtime = WhisperRuntime(backend: backend.backend)
        try await runtime.load(modelID: "test-model", modelPath: modelURL.path, warmup: false)

        let audio = TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 1_600))
        let first = Task { try await runtime.transcribe(audio) }
        XCTAssertEqual(backend.waitForFirstTranscriptionToStart(), .success)

        let second = Task { try await runtime.transcribe(audio) }
        try await Task.sleep(nanoseconds: 50_000_000)

        backend.allowFirstTranscriptionToFinish()
        _ = try await first.value
        XCTAssertEqual(backend.waitForSecondTranscriptionToStart(), .success)

        let unload = Task { await runtime.unload() }
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(backend.freeCallCount, 0)

        backend.allowSecondTranscriptionToFinish()
        _ = try await second.value
        await unload.value

        XCTAssertEqual(backend.freeCallCount, 1)
    }

    func testTranscriptionReturnsNativeConfidenceMetadata() async throws {
        let modelURL = try makeTemporaryModelFile()
        defer { try? FileManager.default.removeItem(at: modelURL) }
        let backend = ImmediateWhisperBackend(
            text: "hello",
            noSpeechProbability: 0.12,
            averageLogProbability: -0.34,
            compressionRatio: 1.56
        )
        let runtime = WhisperRuntime(backend: backend.backend)
        try await runtime.load(modelID: "test-model", modelPath: modelURL.path, warmup: false)

        let result = try await runtime.transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0.1, count: 1_600))
        )

        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.noSpeechProbability, 0.12)
        XCTAssertEqual(result.averageLogProbability, -0.34)
        XCTAssertEqual(result.compressionRatio, 1.56)
    }

    func testRequestedGPUFailsClosedWhenNativeContextHasNoGPUBackend() async throws {
        let modelURL = try makeTemporaryModelFile()
        defer { try? FileManager.default.removeItem(at: modelURL) }
        let runtime = WhisperRuntime(
            backend: ImmediateWhisperBackend(usesGPU: false).backend
        )

        do {
            try await runtime.load(
                modelID: "test-model",
                modelPath: modelURL.path,
                useGPU: true,
                warmup: false
            )
            XCTFail("Expected a requested GPU backend to fail closed")
        } catch let error as WhisperRuntimeError {
            XCTAssertEqual(
                error,
                .loadFailed("The requested Metal GPU backend is unavailable.")
            )
        }

        let state = await runtime.state
        XCTAssertEqual(state, .failed(modelID: "test-model", reason: .loadFailed))
    }

    private func makeTemporaryModelFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("textify-test-model-\(UUID().uuidString)")
        try Data().write(to: url)
        return url
    }
}

private struct ImmediateWhisperBackend {
    private let context = NativeWhisperContext(rawValue: OpaquePointer(bitPattern: 1)!)
    let text: String
    let noSpeechProbability: Double
    let averageLogProbability: Double
    let compressionRatio: Double
    let usesGPU: Bool

    init(
        text: String = "",
        noSpeechProbability: Double = 0,
        averageLogProbability: Double = 0,
        compressionRatio: Double = 0,
        usesGPU: Bool = true
    ) {
        self.text = text
        self.noSpeechProbability = noSpeechProbability
        self.averageLogProbability = averageLogProbability
        self.compressionRatio = compressionRatio
        self.usesGPU = usesGPU
    }

    var backend: WhisperRuntimeBackend {
        WhisperRuntimeBackend(
            load: { _, _, _ in context },
            free: { _ in },
            usesGPU: { _ in usesGPU },
            transcribe: { _, _, _ in 0 },
            lastText: { _ in text },
            lastError: { _ in "" },
            lastNoSpeechProbability: { _ in noSpeechProbability },
            lastAverageLogProbability: { _ in averageLogProbability },
            lastCompressionRatio: { _ in compressionRatio }
        )
    }
}

private final class BlockingWhisperBackend: @unchecked Sendable {
    private let context = NativeWhisperContext(rawValue: OpaquePointer(bitPattern: 2)!)
    private let lock = NSLock()
    private var calls = 0
    private var frees = 0
    private let firstStarted = DispatchSemaphore(value: 0)
    private let firstCanFinish = DispatchSemaphore(value: 0)
    private let secondStarted = DispatchSemaphore(value: 0)
    private let secondCanFinish = DispatchSemaphore(value: 0)

    var backend: WhisperRuntimeBackend {
        WhisperRuntimeBackend(
            load: { [context] _, _, _ in context },
            free: { [weak self] _ in self?.recordFree() },
            usesGPU: { _ in true },
            transcribe: { [weak self] _, _, _ in self?.transcribe() ?? -1 },
            lastText: { _ in "transcript" },
            lastError: { _ in "error" },
            lastNoSpeechProbability: { _ in 0 },
            lastAverageLogProbability: { _ in 0 },
            lastCompressionRatio: { _ in 0 }
        )
    }

    var freeCallCount: Int {
        lock.withLock { frees }
    }

    func waitForFirstTranscriptionToStart() -> DispatchTimeoutResult {
        firstStarted.wait(timeout: .now() + 2)
    }

    func waitForSecondTranscriptionToStart() -> DispatchTimeoutResult {
        secondStarted.wait(timeout: .now() + 2)
    }

    func allowFirstTranscriptionToFinish() {
        firstCanFinish.signal()
    }

    func allowSecondTranscriptionToFinish() {
        secondCanFinish.signal()
    }

    private func recordFree() {
        lock.withLock {
            frees += 1
        }
    }

    private func transcribe() -> Int32 {
        let callNumber = lock.withLock {
            calls += 1
            return calls
        }

        if callNumber == 1 {
            firstStarted.signal()
            firstCanFinish.wait()
        } else if callNumber == 2 {
            secondStarted.signal()
            secondCanFinish.wait()
        }

        return 0
    }
}

private extension NSLock {
    func withLock<T>(_ work: () -> T) -> T {
        lock()
        defer { unlock() }
        return work()
    }
}
