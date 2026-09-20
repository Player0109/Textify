import Foundation
import TextifyAudio
import TextifyCore
import TextifyTranscription

public typealias RuntimeDictationSessionProgressHandler =
    @Sendable (_ completedWindows: Int, _ totalWindows: Int) async -> Void

public typealias RuntimeDictationSessionContinuationHandler =
    @Sendable () async -> Bool

public enum RuntimeDictationSessionInterruption: Error, Equatable, Sendable {
    case cancelled
}

public struct RuntimeDictationSessionProcessor: Sendable {
    private let transcriber: any RuntimeTranscribing
    private let voiceCleaner: any RuntimeVoiceCleaning
    private let clock: any RuntimeClock

    public init(
        transcriber: any RuntimeTranscribing,
        voiceCleaner: any RuntimeVoiceCleaning,
        clock: any RuntimeClock
    ) {
        self.transcriber = transcriber
        self.voiceCleaner = voiceCleaner
        self.clock = clock
    }

    public func process(
        audio: CanonicalAudioBuffer,
        transcriptionModel: RuntimeActiveModel,
        voiceCleaningModel: RuntimeActiveModel?,
        progress: RuntimeDictationSessionProgressHandler? = nil,
        shouldContinue: RuntimeDictationSessionContinuationHandler? = nil
    ) async throws -> RuntimeDictationSessionOutcome {
        let windows = RuntimeASRWindowPlanner.plan(
            audio: audio,
            maximumAudioSeconds: transcriptionModel.runtimeParameters.maxAudioSeconds
        )
        try await ensureContinuation(shouldContinue)
        if let progress {
            await progress(0, windows.count)
        }
        try await ensureContinuation(shouldContinue)

        do {
            try await transcriber.prepare(model: transcriptionModel)
        } catch {
            try await ensureContinuation(shouldContinue)
            throw RuntimeDictationSessionError(
                stage: .transcriberPreparation,
                underlyingError: error
            )
        }
        try await ensureContinuation(shouldContinue)

        var cleaning = await prepareVoiceCleaning(
            model: voiceCleaningModel
        )
        try await ensureContinuation(shouldContinue)

        var inferenceDurationMs = 0
        var transcript = ""
        let hallucinationFilter = HallucinationFilter()

        for (index, window) in windows.enumerated() {
            try await ensureContinuation(shouldContinue)
            let windowNumber = index + 1
            let rawAudio = TranscriptionAudioBuffer(
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount,
                samples: Array(audio.samples[window.range])
            )
            let preparedAudio = await clean(
                rawAudio,
                using: voiceCleaningModel,
                summary: &cleaning
            )
            try await ensureContinuation(shouldContinue)

            let startedAt = clock.nowMilliseconds()
            let result: TranscriptionResult
            do {
                result = try await transcriber.transcribe(preparedAudio)
            } catch {
                try await ensureContinuation(shouldContinue)
                throw RuntimeDictationSessionError(
                    stage: .transcription(windowNumber: windowNumber),
                    underlyingError: error
                )
            }
            try await ensureContinuation(shouldContinue)
            inferenceDurationMs += max(0, clock.nowMilliseconds() - startedAt)

            if let progress {
                await progress(windowNumber, windows.count)
            }
            try await ensureContinuation(shouldContinue)

            if hallucinationFilter.shouldDiscard(
                text: result.text,
                noSpeechProbability: result.noSpeechProbability,
                averageLogProbability: result.averageLogProbability,
                compressionRatio: result.compressionRatio
            ) {
                return .discarded(
                    RuntimeDictationSessionDiscard(
                        rejectedWindow: RuntimeDictationSessionRejectedWindow(
                            windowNumber: windowNumber,
                            noSpeechProbability: result.noSpeechProbability,
                            averageLogProbability: result.averageLogProbability,
                            compressionRatio: result.compressionRatio
                        ),
                        inferenceDurationMs: inferenceDurationMs,
                        windowCount: windows.count,
                        voiceCleaning: cleaning
                    )
                )
            }

            transcript = RuntimeTranscriptStitcher.append(
                result.text,
                to: transcript,
                deduplicateLeadingOverlap: window.hasLeadingForcedOverlap
            )
        }

        try await ensureContinuation(shouldContinue)

        return .completed(
            RuntimeDictationSessionCompletion(
                text: transcript,
                inferenceDurationMs: inferenceDurationMs,
                windowCount: windows.count,
                voiceCleaning: cleaning
            )
        )
    }

    private func ensureContinuation(
        _ shouldContinue: RuntimeDictationSessionContinuationHandler?
    ) async throws {
        guard !Task.isCancelled else {
            throw RuntimeDictationSessionInterruption.cancelled
        }
        if let shouldContinue,
           !(await shouldContinue()) {
            throw RuntimeDictationSessionInterruption.cancelled
        }
    }

    private func prepareVoiceCleaning(
        model: RuntimeActiveModel?
    ) async -> RuntimeDictationSessionVoiceCleaningSummary {
        guard let model else {
            return .disabled
        }

        let startedAt = clock.nowMilliseconds()
        do {
            try await voiceCleaner.prepare(model: model)
            return RuntimeDictationSessionVoiceCleaningSummary(
                modelID: model.id,
                prepared: true,
                cleanedWindowCount: 0,
                rawFallbackWindowCount: 0,
                durationMs: max(0, clock.nowMilliseconds() - startedAt)
            )
        } catch {
            return RuntimeDictationSessionVoiceCleaningSummary(
                modelID: model.id,
                prepared: false,
                cleanedWindowCount: 0,
                rawFallbackWindowCount: 0,
                durationMs: max(0, clock.nowMilliseconds() - startedAt)
            )
        }
    }

    private func clean(
        _ audio: TranscriptionAudioBuffer,
        using model: RuntimeActiveModel?,
        summary: inout RuntimeDictationSessionVoiceCleaningSummary
    ) async -> TranscriptionAudioBuffer {
        guard model != nil else {
            return audio
        }
        guard summary.prepared else {
            summary = summary.recordingRawFallbackWindow(durationMs: 0)
            return audio
        }

        let startedAt = clock.nowMilliseconds()
        do {
            let cleaned = try await voiceCleaner.clean(audio)
            summary = summary.recordingCleanedWindow(
                durationMs: max(0, clock.nowMilliseconds() - startedAt)
            )
            return cleaned
        } catch {
            summary = summary.recordingRawFallbackWindow(
                durationMs: max(0, clock.nowMilliseconds() - startedAt)
            )
            return audio
        }
    }
}

public enum RuntimeDictationSessionOutcome: Equatable, Sendable {
    case completed(RuntimeDictationSessionCompletion)
    case discarded(RuntimeDictationSessionDiscard)
}

public struct RuntimeDictationSessionCompletion: Equatable, Sendable {
    public let text: String
    public let inferenceDurationMs: Int
    public let windowCount: Int
    public let voiceCleaning: RuntimeDictationSessionVoiceCleaningSummary

    public init(
        text: String,
        inferenceDurationMs: Int,
        windowCount: Int,
        voiceCleaning: RuntimeDictationSessionVoiceCleaningSummary
    ) {
        self.text = text
        self.inferenceDurationMs = inferenceDurationMs
        self.windowCount = windowCount
        self.voiceCleaning = voiceCleaning
    }
}

public struct RuntimeDictationSessionDiscard: Equatable, Sendable {
    public let rejectedWindow: RuntimeDictationSessionRejectedWindow
    public let inferenceDurationMs: Int
    public let windowCount: Int
    public let voiceCleaning: RuntimeDictationSessionVoiceCleaningSummary

    public init(
        rejectedWindow: RuntimeDictationSessionRejectedWindow,
        inferenceDurationMs: Int,
        windowCount: Int,
        voiceCleaning: RuntimeDictationSessionVoiceCleaningSummary
    ) {
        self.rejectedWindow = rejectedWindow
        self.inferenceDurationMs = inferenceDurationMs
        self.windowCount = windowCount
        self.voiceCleaning = voiceCleaning
    }
}

public struct RuntimeDictationSessionRejectedWindow: Equatable, Sendable {
    public let windowNumber: Int
    public let noSpeechProbability: Double
    public let averageLogProbability: Double
    public let compressionRatio: Double

    public init(
        windowNumber: Int,
        noSpeechProbability: Double,
        averageLogProbability: Double,
        compressionRatio: Double
    ) {
        self.windowNumber = windowNumber
        self.noSpeechProbability = noSpeechProbability
        self.averageLogProbability = averageLogProbability
        self.compressionRatio = compressionRatio
    }
}

public struct RuntimeDictationSessionVoiceCleaningSummary: Equatable, Sendable {
    public let modelID: String?
    public let prepared: Bool
    public let cleanedWindowCount: Int
    public let rawFallbackWindowCount: Int
    public let durationMs: Int

    public init(
        modelID: String?,
        prepared: Bool,
        cleanedWindowCount: Int,
        rawFallbackWindowCount: Int,
        durationMs: Int
    ) {
        self.modelID = modelID
        self.prepared = prepared
        self.cleanedWindowCount = cleanedWindowCount
        self.rawFallbackWindowCount = rawFallbackWindowCount
        self.durationMs = durationMs
    }

    public static let disabled = RuntimeDictationSessionVoiceCleaningSummary(
        modelID: nil,
        prepared: false,
        cleanedWindowCount: 0,
        rawFallbackWindowCount: 0,
        durationMs: 0
    )

    public var usedRawFallback: Bool {
        rawFallbackWindowCount > 0
    }

    fileprivate func recordingCleanedWindow(durationMs: Int) -> Self {
        Self(
            modelID: modelID,
            prepared: prepared,
            cleanedWindowCount: cleanedWindowCount + 1,
            rawFallbackWindowCount: rawFallbackWindowCount,
            durationMs: self.durationMs + durationMs
        )
    }

    fileprivate func recordingRawFallbackWindow(durationMs: Int) -> Self {
        Self(
            modelID: modelID,
            prepared: prepared,
            cleanedWindowCount: cleanedWindowCount,
            rawFallbackWindowCount: rawFallbackWindowCount + 1,
            durationMs: self.durationMs + durationMs
        )
    }
}

public enum RuntimeDictationSessionStage: Equatable, Sendable {
    case transcriberPreparation
    case transcription(windowNumber: Int)
}

public struct RuntimeDictationSessionError: Error, @unchecked Sendable {
    public let stage: RuntimeDictationSessionStage
    public let underlyingError: any Error

    public init(
        stage: RuntimeDictationSessionStage,
        underlyingError: any Error
    ) {
        self.stage = stage
        self.underlyingError = underlyingError
    }
}

private struct RuntimeASRWindow {
    let range: Range<Int>
    let hasLeadingForcedOverlap: Bool
}

private enum RuntimeASRWindowPlanner {
    private static let preferredWindowMilliseconds = 25_000
    private static let modelSafetyMarginMilliseconds = 500
    private static let silenceSearchMilliseconds = 5_000
    private static let minimumSilenceMilliseconds = 200
    private static let forcedOverlapMilliseconds = 400
    private static let analysisFrameMilliseconds = 20
    private static let silenceThresholdAmplitude = Float(pow(10.0, -45.0 / 20.0))

    static func plan(
        audio: CanonicalAudioBuffer,
        maximumAudioSeconds: Int
    ) -> [RuntimeASRWindow] {
        guard !audio.samples.isEmpty, audio.sampleRate > 0 else {
            return []
        }

        let maximumWindowSamples = max(
            1,
            samples(
                milliseconds: max(
                    1,
                    maximumAudioSeconds * 1_000 - modelSafetyMarginMilliseconds
                ),
                sampleRate: audio.sampleRate
            )
        )
        if audio.samples.count <= maximumWindowSamples {
            return [
                RuntimeASRWindow(
                    range: 0..<audio.samples.count,
                    hasLeadingForcedOverlap: false
                ),
            ]
        }
        let preferredWindowSamples = min(
            maximumWindowSamples,
            samples(
                milliseconds: preferredWindowMilliseconds,
                sampleRate: audio.sampleRate
            )
        )
        let forcedOverlapSamples = samples(
            milliseconds: forcedOverlapMilliseconds,
            sampleRate: audio.sampleRate
        )

        var windows: [RuntimeASRWindow] = []
        var start = 0
        var hasLeadingForcedOverlap = false

        while start < audio.samples.count {
            let remaining = audio.samples.count - start
            if remaining <= preferredWindowSamples {
                windows.append(
                    RuntimeASRWindow(
                        range: start..<audio.samples.count,
                        hasLeadingForcedOverlap: hasLeadingForcedOverlap
                    )
                )
                break
            }

            let preferredEnd = start + preferredWindowSamples
            if let silenceSplit = silenceSplit(
                samples: audio.samples,
                start: start,
                end: preferredEnd,
                sampleRate: audio.sampleRate
            ), silenceSplit > start {
                windows.append(
                    RuntimeASRWindow(
                        range: start..<silenceSplit,
                        hasLeadingForcedOverlap: hasLeadingForcedOverlap
                    )
                )
                start = silenceSplit
                hasLeadingForcedOverlap = false
                continue
            }

            windows.append(
                RuntimeASRWindow(
                    range: start..<preferredEnd,
                    hasLeadingForcedOverlap: hasLeadingForcedOverlap
                )
            )
            let boundedOverlap = min(
                forcedOverlapSamples,
                max(0, preferredWindowSamples - 1)
            )
            start = preferredEnd - boundedOverlap
            hasLeadingForcedOverlap = boundedOverlap > 0
        }

        return windows
    }

    private static func silenceSplit(
        samples: [Float],
        start: Int,
        end: Int,
        sampleRate: Int
    ) -> Int? {
        let searchSamples = self.samples(
            milliseconds: silenceSearchMilliseconds,
            sampleRate: sampleRate
        )
        let minimumSilenceSamples = self.samples(
            milliseconds: minimumSilenceMilliseconds,
            sampleRate: sampleRate
        )
        let frameSamples = max(
            1,
            self.samples(
                milliseconds: analysisFrameMilliseconds,
                sampleRate: sampleRate
            )
        )
        let searchStart = max(start, end - searchSamples)
        var cursor = searchStart
        var quietRunStart: Int?
        var latestSplit: Int?

        while cursor < end {
            let frameEnd = min(end, cursor + frameSamples)
            if isQuiet(samples[cursor..<frameEnd]) {
                if quietRunStart == nil {
                    quietRunStart = cursor
                }
            } else if let runStart = quietRunStart {
                if cursor - runStart >= minimumSilenceSamples {
                    latestSplit = runStart + (cursor - runStart) / 2
                }
                quietRunStart = nil
            }
            cursor = frameEnd
        }

        if let runStart = quietRunStart,
           end - runStart >= minimumSilenceSamples {
            latestSplit = runStart + (end - runStart) / 2
        }
        return latestSplit
    }

    private static func isQuiet(_ samples: ArraySlice<Float>) -> Bool {
        guard !samples.isEmpty else {
            return true
        }
        let meanSquare = samples.reduce(Double.zero) {
            $0 + Double($1) * Double($1)
        } / Double(samples.count)
        return Float(sqrt(meanSquare)) <= silenceThresholdAmplitude
    }

    private static func samples(milliseconds: Int, sampleRate: Int) -> Int {
        max(1, Int(Double(milliseconds) * Double(sampleRate) / 1_000.0))
    }
}

private enum RuntimeTranscriptStitcher {
    static func append(
        _ rawText: String,
        to previousText: String,
        deduplicateLeadingOverlap: Bool
    ) -> String {
        let previous = previousText.trimmingCharacters(in: .whitespacesAndNewlines)
        var current = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previous.isEmpty else {
            return current
        }
        guard !current.isEmpty else {
            return previous
        }

        if deduplicateLeadingOverlap {
            if let remainder = remainderAfterWordOverlap(
                previous: previous,
                current: current
            ) {
                current = remainder
            } else if containsCJK(previous) || containsCJK(current),
                      let remainder = remainderAfterCharacterOverlap(
                          previous: previous,
                          current: current
                      ) {
                current = remainder
            }
        }

        guard !current.isEmpty else {
            return previous
        }
        return previous + separator(between: previous, and: current) + current
    }

    private static func remainderAfterWordOverlap(
        previous: String,
        current: String
    ) -> String? {
        let previousTokens = whitespaceTokens(in: previous)
        let currentTokens = whitespaceTokens(in: current)
        let maximumOverlap = min(previousTokens.count, currentTokens.count)
        guard maximumOverlap >= 2 else {
            return nil
        }

        for count in stride(from: maximumOverlap, through: 2, by: -1) {
            let previousSuffix = previousTokens.suffix(count).map(\.comparison)
            let currentPrefix = currentTokens.prefix(count).map(\.comparison)
            guard !previousSuffix.contains(where: \.isEmpty),
                  previousSuffix == currentPrefix else {
                continue
            }
            let consumedEnd = currentTokens[count - 1].range.upperBound
            return String(current[consumedEnd...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func remainderAfterCharacterOverlap(
        previous: String,
        current: String
    ) -> String? {
        let previousCharacters = Array(previous)
        let currentCharacters = Array(current)
        let maximumOverlap = min(previousCharacters.count, currentCharacters.count)
        guard maximumOverlap >= 4 else {
            return nil
        }

        for count in stride(from: maximumOverlap, through: 4, by: -1) {
            if previousCharacters.suffix(count).elementsEqual(
                currentCharacters.prefix(count)
            ) {
                let end = current.index(current.startIndex, offsetBy: count)
                return String(current[end...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func separator(between previous: String, and current: String) -> String {
        guard let previousCharacter = previous.last,
              let currentCharacter = current.first else {
            return ""
        }
        if usesUnspacedScript(previousCharacter)
            || usesUnspacedScript(currentCharacter) {
            return ""
        }
        if ",.;:!?)]}，。！？；：、".contains(currentCharacter) {
            return ""
        }
        if "([{\"“‘".contains(previousCharacter) {
            return ""
        }
        return " "
    }

    private static func usesUnspacedScript(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x3040...0x30FF:
                true
            default:
                false
            }
        }
    }

    private static func whitespaceTokens(in text: String) -> [RuntimeTextToken] {
        var tokens: [RuntimeTextToken] = []
        var tokenStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace {
                if let start = tokenStart {
                    tokens.append(token(in: text, range: start..<index))
                    tokenStart = nil
                }
            } else if tokenStart == nil {
                tokenStart = index
            }
            index = text.index(after: index)
        }
        if let start = tokenStart {
            tokens.append(token(in: text, range: start..<text.endIndex))
        }
        return tokens
    }

    private static func token(
        in text: String,
        range: Range<String.Index>
    ) -> RuntimeTextToken {
        RuntimeTextToken(
            comparison: String(text[range])
                .trimmingCharacters(in: .punctuationCharacters)
                .lowercased(),
            range: range
        )
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.contains(where: isCJK)
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x3040...0x30FF,
                 0xAC00...0xD7AF:
                true
            default:
                false
            }
        }
    }
}

private struct RuntimeTextToken {
    let comparison: String
    let range: Range<String.Index>
}
