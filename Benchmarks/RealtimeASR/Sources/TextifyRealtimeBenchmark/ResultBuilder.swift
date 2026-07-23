import BenchmarkMetrics
import Foundation
import TextifyCore
import TextifyTranscription

func makeResult(
    engine: BenchmarkEngine,
    engineVersion: String,
    model: String,
    modelLicense: String,
    computeBackend: String,
    feedMode: FeedMode,
    audio: CanonicalBenchmarkAudio,
    modelLoadMs: Int,
    warmupMs: Int,
    firstPartialMs: Int?,
    partialIntervalsMs: [Int],
    releaseToFinalMs: Int,
    inferenceWorkMs: Int,
    maximumFeedLagMs: Int,
    transcript: String,
    reference: String?,
    resources: ResourceSnapshot,
    productionMetadata: TranscriptionResult? = nil
) -> BenchmarkResult {
    let median = medianValue(partialIntervalsMs)
    let accuracy = reference.map { reference in
        let score = WordErrorRate.score(reference: reference, hypothesis: transcript)
        let characterScore = CharacterErrorRate.score(
            reference: reference,
            hypothesis: transcript
        )
        return AccuracySnapshot(
            referenceText: reference,
            hypothesisText: transcript,
            referenceWordCount: score.referenceWords,
            hypothesisWordCount: score.hypothesisWords,
            substitutions: score.substitutions,
            insertions: score.insertions,
            deletions: score.deletions,
            wordErrors: score.errors,
            wordErrorRate: score.rate,
            referenceCharacterCount: characterScore.referenceCharacters,
            hypothesisCharacterCount: characterScore.hypothesisCharacters,
            characterErrors: characterScore.errors,
            characterErrorRate: characterScore.rate
        )
    }
    let realTimeFactor = audio.durationMilliseconds > 0
        ? Double(inferenceWorkMs) / Double(audio.durationMilliseconds)
        : 0
    let production = productionMetadata.map { metadata in
        let discarded = HallucinationFilter().shouldDiscard(
            text: metadata.text,
            noSpeechProbability: metadata.noSpeechProbability,
            averageLogProbability: metadata.averageLogProbability,
            compressionRatio: metadata.compressionRatio
        )
        return EvaluationProductionSnapshot(
            applicationText: discarded ? "" : metadata.text,
            discarded: discarded,
            noSpeechProbability: metadata.noSpeechProbability,
            averageLogProbability: metadata.averageLogProbability,
            compressionRatio: metadata.compressionRatio
        )
    }

    return BenchmarkResult(
        schemaVersion: production == nil ? 1 : 2,
        engine: engine,
        engineVersion: engineVersion,
        model: model,
        modelLicense: modelLicense,
        computeBackend: computeBackend,
        feedMode: feedMode,
        host: .current(),
        audio: AudioSnapshot(
            durationMs: audio.durationMilliseconds,
            sampleRate: CanonicalBenchmarkAudio.sampleRate,
            sampleCount: audio.samples.count
        ),
        timing: TimingSnapshot(
            modelLoadMs: modelLoadMs,
            warmupMs: warmupMs,
            firstPartialMs: firstPartialMs,
            partialUpdateIntervalsMs: partialIntervalsMs,
            partialUpdateMedianMs: median,
            releaseToFinalMs: releaseToFinalMs,
            inferenceWorkMs: inferenceWorkMs,
            realTimeFactor: realTimeFactor,
            maximumFeedLagMs: maximumFeedLagMs
        ),
        accuracy: accuracy,
        production: production,
        resources: resources,
        targets: TargetSnapshot(
            firstPartialUnder500Ms: firstPartialMs.map { $0 < 500 },
            partialMedianBetween200And400Ms: median.map { (200...400).contains($0) },
            releaseToFinalUnder700Ms: releaseToFinalMs < 700,
            fullyOffline: true
        )
    )
}

private func medianValue(_ values: [Int]) -> Int? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}
