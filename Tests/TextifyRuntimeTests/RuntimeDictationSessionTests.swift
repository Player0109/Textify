import Foundation
import TextifyAudio
import TextifyModels
import TextifyTranscription
@testable import TextifyRuntime
import XCTest

final class RuntimeDictationSessionTests: XCTestCase {
    func testSingleWindowPreparesOnceAndReportsProgress() async throws {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [.result(Self.result("hello"), durationMs: 17)]
        )
        let progress = SessionProgressLog()
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        )
        let audio = Self.audio(seconds: 10)

        let outcome = try await processor.process(
            audio: audio,
            transcriptionModel: Self.model(maxAudioSeconds: 30),
            voiceCleaningModel: nil,
            progress: { completed, total in
                await progress.append(completed: completed, total: total)
            }
        )

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        XCTAssertEqual(completion.text, "hello")
        XCTAssertEqual(completion.windowCount, 1)
        XCTAssertEqual(completion.inferenceDurationMs, 17)
        XCTAssertEqual(completion.voiceCleaning, .disabled)
        let prepareCount = await transcriber.prepareCount()
        let transcribedAudio = await transcriber.transcribedAudio()
        let progressValues = await progress.values()
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(transcribedAudio, [Self.transcriptionAudio(audio)])
        XCTAssertEqual(
            progressValues,
            [
                .init(completed: 0, total: 1),
                .init(completed: 1, total: 1),
            ]
        )
    }

    func testAudioWithinModelSafeLimitKeepsSingleWindowAbovePreferredTarget() async throws {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [
                .result(Self.result("complete clip"), durationMs: 1),
                .result(Self.result("unexpected extra window"), durationMs: 1),
            ]
        )
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        )
        let audio = Self.audio(seconds: 30)

        let outcome = try await processor.process(
            audio: audio,
            transcriptionModel: Self.model(maxAudioSeconds: 60),
            voiceCleaningModel: nil
        )

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        let transcribedAudio = await transcriber.transcribedAudio()
        XCTAssertEqual(completion.text, "complete clip")
        XCTAssertEqual(completion.windowCount, 1)
        XCTAssertEqual(transcribedAudio, [Self.transcriptionAudio(audio)])
    }

    func testSilenceAwareBoundaryDoesNotOverlapSamples() async throws {
        let sampleRate = 1_000
        var samples = Array(repeating: Float(0.25), count: 35 * sampleRate)
        samples.replaceSubrange(
            (22 * sampleRate)..<(22 * sampleRate + 300),
            with: repeatElement(0, count: 300)
        )
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [
                .result(Self.result("first"), durationMs: 1),
                .result(Self.result("second"), durationMs: 1),
            ]
        )
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        )

        let outcome = try await processor.process(
            audio: CanonicalAudioBuffer(sampleRate: sampleRate, samples: samples),
            transcriptionModel: Self.model(maxAudioSeconds: 30),
            voiceCleaningModel: nil
        )

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        let windows = await transcriber.transcribedAudio()
        XCTAssertEqual(completion.text, "first second")
        XCTAssertEqual(windows.count, 2)
        XCTAssertTrue((22_000...22_300).contains(windows[0].samples.count))
        XCTAssertEqual(windows.reduce(0) { $0 + $1.samples.count }, samples.count)
    }

    func testForcedBoundariesOverlapAndStayBelowModelLimit() async throws {
        let sampleRate = 100
        let audio = Self.audio(seconds: 55, sampleRate: sampleRate)
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [
                .result(Self.result("one"), durationMs: 1),
                .result(Self.result("two"), durationMs: 1),
                .result(Self.result("three"), durationMs: 1),
            ]
        )
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        )

        _ = try await processor.process(
            audio: audio,
            transcriptionModel: Self.model(maxAudioSeconds: 20),
            voiceCleaningModel: nil
        )

        let windows = await transcriber.transcribedAudio()
        let maximumSafeSamples = 19_500 / 10
        let overlapSamples = 400 / 10
        XCTAssertEqual(windows.count, 3)
        XCTAssertTrue(windows.allSatisfy { $0.samples.count <= maximumSafeSamples })
        XCTAssertEqual(
            windows.reduce(0) { $0 + $1.samples.count },
            audio.samples.count + overlapSamples * 2
        )
        XCTAssertEqual(
            Array(windows[0].samples.suffix(overlapSamples)),
            Array(windows[1].samples.prefix(overlapSamples))
        )
        XCTAssertEqual(
            Array(windows[1].samples.suffix(overlapSamples)),
            Array(windows[2].samples.prefix(overlapSamples))
        )
    }

    func testMultiWindowTranscriptionIsSequentialAndProgressIsOrdered() async throws {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [
                .result(Self.result("one"), durationMs: 4),
                .result(Self.result("two"), durationMs: 5),
                .result(Self.result("three"), durationMs: 6),
            ]
        )
        let progress = SessionProgressLog()
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        )

        let outcome = try await processor.process(
            audio: Self.audio(seconds: 55),
            transcriptionModel: Self.model(maxAudioSeconds: 30),
            voiceCleaningModel: nil,
            progress: { completed, total in
                await progress.append(completed: completed, total: total)
            }
        )

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        XCTAssertEqual(completion.text, "one two three")
        XCTAssertEqual(completion.inferenceDurationMs, 15)
        let prepareCount = await transcriber.prepareCount()
        let maximumConcurrency = await transcriber.maximumConcurrentTranscriptions()
        let progressValues = await progress.values()
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(maximumConcurrency, 1)
        XCTAssertEqual(
            progressValues,
            [
                .init(completed: 0, total: 3),
                .init(completed: 1, total: 3),
                .init(completed: 2, total: 3),
                .init(completed: 3, total: 3),
            ]
        )
    }

    func testSessionTokenStopsBeforeAnotherWindowAfterCancellation() async throws {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [
                .result(Self.result("first"), durationMs: 1),
                .result(Self.result("must not run"), durationMs: 1),
                .result(Self.result("must not run either"), durationMs: 1),
            ]
        )
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        )

        do {
            _ = try await processor.process(
                audio: Self.audio(seconds: 55),
                transcriptionModel: Self.model(maxAudioSeconds: 30),
                voiceCleaningModel: nil,
                shouldContinue: {
                    await transcriber.transcribeCount() < 1
                }
            )
            XCTFail("Expected cancelled session")
        } catch let error as RuntimeDictationSessionInterruption {
            XCTAssertEqual(error, .cancelled)
        }

        let transcribeCount = await transcriber.transcribeCount()
        XCTAssertEqual(transcribeCount, 1)
    }

    func testForcedOverlapDeduplicatesTwoEnglishWords() async throws {
        let outcome = try await Self.process(
            seconds: 30,
            texts: ["alpha beta gamma", "beta gamma delta"]
        )

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        XCTAssertEqual(completion.text, "alpha beta gamma delta")
    }

    func testForcedOverlapDeduplicatesFourCJKCharactersWithoutAddingSpace() async throws {
        let outcome = try await Self.process(
            seconds: 30,
            texts: ["今天我们一起学习", "一起学习如何测试"]
        )

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        XCTAssertEqual(completion.text, "今天我们一起学习如何测试")
    }

    func testKoreanWindowBoundaryPreservesWordSeparatorWithoutOverlap() async throws {
        let outcome = try await Self.process(
            seconds: 30,
            texts: ["안녕하세요 세계", "오늘 날씨입니다"]
        )

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        XCTAssertEqual(completion.text, "안녕하세요 세계 오늘 날씨입니다")
    }

    func testForcedOverlapPreservesDeliberateSingleWordRepeat() async throws {
        let outcome = try await Self.process(seconds: 30, texts: ["go", "go now"])

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        XCTAssertEqual(completion.text, "go go now")
    }

    func testCleanerFailureFallsBackOnlyFailedWindowAndReturnsAggregateSummary() async throws {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [
                .result(Self.result("first"), durationMs: 1),
                .result(Self.result("second"), durationMs: 1),
            ]
        )
        let cleaner = SessionVoiceCleaner(
            clock: clock,
            prepareDurationMs: 2,
            cleanDurationMsByCall: [3, 5],
            failingCleanCalls: [2]
        )
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: cleaner,
            clock: clock
        )

        let outcome = try await processor.process(
            audio: Self.audio(seconds: 30),
            transcriptionModel: Self.model(maxAudioSeconds: 30),
            voiceCleaningModel: Self.cleanerModel()
        )

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        let windows = await transcriber.transcribedAudio()
        let cleanerPrepareCount = await cleaner.prepareCount()
        let cleanerCleanCount = await cleaner.cleanCount()
        XCTAssertEqual(cleanerPrepareCount, 1)
        XCTAssertEqual(cleanerCleanCount, 2)
        XCTAssertEqual(windows[0].samples.first, 0.5)
        XCTAssertEqual(windows[1].samples.first, 0.25)
        XCTAssertEqual(
            completion.voiceCleaning,
            .init(
                modelID: Self.cleanerModel().id,
                prepared: true,
                cleanedWindowCount: 1,
                rawFallbackWindowCount: 1,
                durationMs: 10
            )
        )
    }

    func testCleanerPrepareFailureUsesRawAudioForEveryProcessedWindow() async throws {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [
                .result(Self.result("first"), durationMs: 1),
                .result(Self.result("second"), durationMs: 1),
            ]
        )
        let cleaner = SessionVoiceCleaner(
            clock: clock,
            prepareDurationMs: 2,
            prepareError: .cleaning
        )
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: cleaner,
            clock: clock
        )

        let outcome = try await processor.process(
            audio: Self.audio(seconds: 30),
            transcriptionModel: Self.model(maxAudioSeconds: 30),
            voiceCleaningModel: Self.cleanerModel()
        )

        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected completed session")
        }
        let windows = await transcriber.transcribedAudio()
        let cleanCount = await cleaner.cleanCount()
        XCTAssertEqual(cleanCount, 0)
        XCTAssertTrue(windows.allSatisfy { $0.samples.first == 0.25 })
        XCTAssertEqual(
            completion.voiceCleaning,
            .init(
                modelID: Self.cleanerModel().id,
                prepared: false,
                cleanedWindowCount: 0,
                rawFallbackWindowCount: 2,
                durationMs: 2
            )
        )
    }

    func testMidWindowTranscriptionErrorFailsAtomicallyWithStageAndUnderlyingError() async throws {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [
                .result(Self.result("must not escape"), durationMs: 2),
                .failure(.inference, durationMs: 3),
                .result(Self.result("unreachable"), durationMs: 4),
            ]
        )
        let progress = SessionProgressLog()
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        )

        do {
            _ = try await processor.process(
                audio: Self.audio(seconds: 55),
                transcriptionModel: Self.model(maxAudioSeconds: 30),
                voiceCleaningModel: nil,
                progress: { completed, total in
                    await progress.append(completed: completed, total: total)
                }
            )
            XCTFail("Expected atomic session failure")
        } catch let error as RuntimeDictationSessionError {
            XCTAssertEqual(error.stage, .transcription(windowNumber: 2))
            XCTAssertEqual(error.underlyingError as? SessionFixtureError, .inference)
        }

        let transcribeCount = await transcriber.transcribeCount()
        let progressValues = await progress.values()
        XCTAssertEqual(transcribeCount, 2)
        XCTAssertEqual(
            progressValues,
            [
                .init(completed: 0, total: 3),
                .init(completed: 1, total: 3),
            ]
        )
    }

    func testPrepareErrorPreservesPreparationStageAndUnderlyingError() async throws {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [],
            prepareError: .preparation
        )
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        )

        do {
            _ = try await processor.process(
                audio: Self.audio(seconds: 10),
                transcriptionModel: Self.model(maxAudioSeconds: 30),
                voiceCleaningModel: nil
            )
            XCTFail("Expected preparation failure")
        } catch let error as RuntimeDictationSessionError {
            XCTAssertEqual(error.stage, .transcriberPreparation)
            XCTAssertEqual(error.underlyingError as? SessionFixtureError, .preparation)
        }

        let transcribeCount = await transcriber.transcribeCount()
        XCTAssertEqual(transcribeCount, 0)
    }

    func testHallucinationInMiddleWindowDiscardsWholeSession() async throws {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: [
                .result(Self.result("must not escape"), durationMs: 2),
                .result(Self.result("Thanks for watching!"), durationMs: 3),
                .result(Self.result("unreachable"), durationMs: 4),
            ]
        )
        let progress = SessionProgressLog()
        let processor = RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        )

        let outcome = try await processor.process(
            audio: Self.audio(seconds: 55),
            transcriptionModel: Self.model(maxAudioSeconds: 30),
            voiceCleaningModel: nil,
            progress: { completed, total in
                await progress.append(completed: completed, total: total)
            }
        )

        guard case let .discarded(discard) = outcome else {
            return XCTFail("Expected atomic session discard")
        }
        XCTAssertEqual(discard.windowCount, 3)
        XCTAssertEqual(discard.inferenceDurationMs, 5)
        XCTAssertEqual(discard.rejectedWindow.windowNumber, 2)
        XCTAssertEqual(discard.rejectedWindow.noSpeechProbability, 0.01)
        let transcribeCount = await transcriber.transcribeCount()
        let progressValues = await progress.values()
        XCTAssertEqual(transcribeCount, 2)
        XCTAssertEqual(
            progressValues,
            [
                .init(completed: 0, total: 3),
                .init(completed: 1, total: 3),
                .init(completed: 2, total: 3),
            ]
        )
    }
}

private extension RuntimeDictationSessionTests {
    static func process(
        seconds: Int,
        texts: [String]
    ) async throws -> RuntimeDictationSessionOutcome {
        let clock = SessionTestClock()
        let transcriber = SessionTranscriber(
            clock: clock,
            steps: texts.map { .result(result($0), durationMs: 1) }
        )
        return try await RuntimeDictationSessionProcessor(
            transcriber: transcriber,
            voiceCleaner: SessionVoiceCleaner(),
            clock: clock
        ).process(
            audio: audio(seconds: seconds),
            transcriptionModel: model(maxAudioSeconds: 30),
            voiceCleaningModel: nil
        )
    }

    static func audio(seconds: Int, sampleRate: Int = 100) -> CanonicalAudioBuffer {
        CanonicalAudioBuffer(
            sampleRate: sampleRate,
            samples: Array(repeating: 0.25, count: seconds * sampleRate)
        )
    }

    static func transcriptionAudio(_ audio: CanonicalAudioBuffer) -> TranscriptionAudioBuffer {
        TranscriptionAudioBuffer(
            sampleRate: audio.sampleRate,
            channelCount: audio.channelCount,
            samples: audio.samples
        )
    }

    static func result(_ text: String) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            noSpeechProbability: 0.01,
            averageLogProbability: -0.1,
            compressionRatio: 1.0
        )
    }

    static func model(maxAudioSeconds: Int) -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "transcription-fixture",
            displayName: "Transcription Fixture",
            tier: "test",
            localModelPath: "/tmp/transcription-fixture",
            useGPU: false,
            threadCount: nil,
            engine: .whisperCpp,
            variant: "fixture",
            accelerator: .cpu,
            artifactLayout: .singleFile,
            runtimeParameters: runtimeParameters(maxAudioSeconds: maxAudioSeconds)
        )
    }

    static func cleanerModel() -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: "cleaner-fixture",
            displayName: "Cleaner Fixture",
            tier: "test",
            localModelPath: "/tmp/cleaner-fixture",
            useGPU: false,
            threadCount: nil,
            engine: .mlxAudio,
            variant: "fixture",
            accelerator: .metalGPU,
            artifactLayout: .modelDirectory,
            runtimeParameters: runtimeParameters(maxAudioSeconds: 60),
            purpose: .voiceCleaning
        )
    }

    static func runtimeParameters(maxAudioSeconds: Int) -> RuntimeParameters {
        RuntimeParameters(
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
            maxAudioSeconds: maxAudioSeconds
        )
    }
}

private enum SessionFixtureError: Error, Equatable {
    case preparation
    case inference
    case cleaning
}

private final class SessionTestClock: RuntimeClock, @unchecked Sendable {
    private let lock = NSLock()
    private var milliseconds = 0

    func nowMilliseconds() -> Int {
        lock.withLock { milliseconds }
    }

    func sleep(milliseconds: Int) async {}

    func advance(milliseconds: Int) {
        lock.withLock {
            self.milliseconds += milliseconds
        }
    }
}

private actor SessionTranscriber: RuntimeTranscribing {
    enum Step {
        case result(TranscriptionResult, durationMs: Int)
        case failure(SessionFixtureError, durationMs: Int)
    }

    private let clock: SessionTestClock
    private var steps: [Step]
    private let prepareError: SessionFixtureError?
    private var prepareCountValue = 0
    private var transcribeCountValue = 0
    private var activeTranscriptions = 0
    private var maximumConcurrentTranscriptionsValue = 0
    private var transcribedAudioValue: [TranscriptionAudioBuffer] = []

    init(
        clock: SessionTestClock,
        steps: [Step],
        prepareError: SessionFixtureError? = nil
    ) {
        self.clock = clock
        self.steps = steps
        self.prepareError = prepareError
    }

    var readiness: RuntimeModelReadiness {
        get async { .ready(modelID: "transcription-fixture") }
    }

    func prepare(model: RuntimeActiveModel) async throws {
        prepareCountValue += 1
        if let prepareError {
            throw prepareError
        }
    }

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        transcribeCountValue += 1
        activeTranscriptions += 1
        maximumConcurrentTranscriptionsValue = max(
            maximumConcurrentTranscriptionsValue,
            activeTranscriptions
        )
        defer { activeTranscriptions -= 1 }
        transcribedAudioValue.append(audio)
        let step = steps.removeFirst()
        switch step {
        case let .result(result, durationMs):
            clock.advance(milliseconds: durationMs)
            return result
        case let .failure(error, durationMs):
            clock.advance(milliseconds: durationMs)
            throw error
        }
    }

    func unload() async {}

    func prepareCount() -> Int { prepareCountValue }
    func transcribeCount() -> Int { transcribeCountValue }
    func transcribedAudio() -> [TranscriptionAudioBuffer] { transcribedAudioValue }
    func maximumConcurrentTranscriptions() -> Int { maximumConcurrentTranscriptionsValue }
}

private actor SessionVoiceCleaner: RuntimeVoiceCleaning {
    private let clock: SessionTestClock?
    private let prepareDurationMs: Int
    private let cleanDurationMsByCall: [Int]
    private let prepareError: SessionFixtureError?
    private let failingCleanCalls: Set<Int>
    private var prepareCountValue = 0
    private var cleanCountValue = 0

    init(
        clock: SessionTestClock? = nil,
        prepareDurationMs: Int = 0,
        cleanDurationMsByCall: [Int] = [],
        prepareError: SessionFixtureError? = nil,
        failingCleanCalls: Set<Int> = []
    ) {
        self.clock = clock
        self.prepareDurationMs = prepareDurationMs
        self.cleanDurationMsByCall = cleanDurationMsByCall
        self.prepareError = prepareError
        self.failingCleanCalls = failingCleanCalls
    }

    func prepare(model: RuntimeActiveModel) async throws {
        prepareCountValue += 1
        clock?.advance(milliseconds: prepareDurationMs)
        if let prepareError {
            throw prepareError
        }
    }

    func clean(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionAudioBuffer {
        cleanCountValue += 1
        if cleanDurationMsByCall.indices.contains(cleanCountValue - 1) {
            clock?.advance(milliseconds: cleanDurationMsByCall[cleanCountValue - 1])
        }
        if failingCleanCalls.contains(cleanCountValue) {
            throw SessionFixtureError.cleaning
        }
        return TranscriptionAudioBuffer(
            sampleRate: audio.sampleRate,
            channelCount: audio.channelCount,
            samples: audio.samples.map { $0 * 2 }
        )
    }

    func unload() async {}

    func prepareCount() -> Int { prepareCountValue }
    func cleanCount() -> Int { cleanCountValue }
}

private struct SessionProgressValue: Equatable {
    let completed: Int
    let total: Int
}

private actor SessionProgressLog {
    private var storedValues: [SessionProgressValue] = []

    func append(completed: Int, total: Int) {
        storedValues.append(.init(completed: completed, total: total))
    }

    func values() -> [SessionProgressValue] {
        storedValues
    }
}
