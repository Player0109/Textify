import Foundation
import Testing
@testable import BenchmarkMetrics

@Test func catalogRatingPolicyDecodesFrozenEnglishPolicy() throws {
    let policy = try loadCatalogPolicy()

    #expect(policy.id == "english-catalog-rating-v1")
    #expect(policy.quality.components.map(\.weight) == [0.5, 0.3, 0.2])
    #expect(policy.speed.requiredRuns == 3)
    #expect(policy.speed.referenceChip == "Apple M4 Max")
    #expect(policy.level(for: 89).level == 4)
}

@Test func catalogRatingBuildsAbsoluteQualityAndStableSpeedLevels() throws {
    let rating = try buildCatalogRating(runLatencies: [200, 205, 210])

    #expect(rating.quality.score == 83)
    #expect(rating.quality.level == 4)
    #expect(rating.quality.label == "High")
    #expect(rating.quality.speechItems == 3)
    #expect(rating.quality.noSpeechItems == 1)
    #expect(rating.speed?.score == 92)
    #expect(rating.speed?.level == 5)
    #expect(rating.speed?.p95ReleaseToFinalMs == 205)
    #expect(rating.speedUnratedReason == nil)
}

@Test func catalogRatingCapsQualityForNoSpeechFalsePositives() throws {
    let rating = try buildCatalogRating(
        runLatencies: [200, 205, 210],
        noSpeechFalsePositive: true
    )

    #expect(rating.quality.score == 83)
    #expect(rating.quality.noSpeechFalsePositiveRate == 1)
    #expect(rating.quality.level == 1)
    #expect(rating.quality.label == "Limited")
}

@Test func catalogRatingV2UsesQualityScoreDespiteNoSpeechFalsePositives() throws {
    let rating = try buildCatalogRating(
        runLatencies: [200, 205, 210],
        noSpeechFalsePositive: true,
        policyFilename: "english-catalog-rating-v2.policy.json"
    )

    #expect(rating.policyID == "english-catalog-rating-v2")
    #expect(rating.suiteID == "english-catalog-rating-v1")
    #expect(rating.quality.score == 83)
    #expect(rating.quality.noSpeechFalsePositiveRate == 1)
    #expect(rating.quality.level == 4)
    #expect(rating.quality.label == "High")
}

@Test func catalogRatingLeavesUnstableSpeedUnrated() throws {
    let rating = try buildCatalogRating(runLatencies: [200, 205, 400])

    #expect(rating.quality.level == 4)
    #expect(rating.speed == nil)
    #expect(rating.speedUnratedReason == "unstable-p95")
}

@Test func catalogRatingPolicyRejectsUnknownFields() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot
        .appendingPathComponent("Corpus", isDirectory: true)
        .appendingPathComponent("english-catalog-rating-v1.policy.json")
    var object = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    object["untrusted"] = true

    #expect(throws: CatalogRatingPolicyError.invalidSchemaFields) {
        try CatalogRatingPolicy.decode(JSONSerialization.data(withJSONObject: object))
    }
}

@Test func catalogRatingRejectsDuplicateRunProvenance() throws {
    #expect(throws: CatalogRatingError.invalidRunMetadata(2)) {
        try buildCatalogRating(
            runLatencies: [200, 205, 210],
            runIDs: ["duplicate", "duplicate", "third"]
        )
    }
}

private func buildCatalogRating(
    runLatencies: [Int],
    noSpeechFalsePositive: Bool = false,
    runIDs: [String]? = nil,
    policyFilename: String = "english-catalog-rating-v1.policy.json"
) throws -> CatalogBenchmarkRating {
    let policy = try loadCatalogPolicy(policyFilename)
    let resolved = ratingResolvedComponents()
    let index = EvaluationSuiteIndex(
        schemaVersion: 1,
        id: policy.suiteID,
        language: "en",
        components: resolved.map(\.component)
    )
    let runs = runLatencies.enumerated().map { index, latency in
        ratingRun(
            resolved: resolved,
            runID: runIDs?[index] ?? "test-run-\(index + 1)",
            latency: latency,
            noSpeechFalsePositive: noSpeechFalsePositive
        )
    }
    return try CatalogRatingBuilder.build(
        policy: policy,
        index: index,
        resolvedComponents: resolved,
        suiteIndexSHA256: String(repeating: "a", count: 64),
        modelID: "test-model",
        artifactFingerprint: String(repeating: "b", count: 64),
        measuredAt: "2026-07-22T00:00:00Z",
        runs: runs
    )
}

private func loadCatalogPolicy(
    _ filename: String = "english-catalog-rating-v1.policy.json"
) throws -> CatalogRatingPolicy {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot
        .appendingPathComponent("Corpus", isDirectory: true)
        .appendingPathComponent(filename)
    return try CatalogRatingPolicy.decode(Data(contentsOf: url))
}

private func ratingResolvedComponents() -> [ResolvedEvaluationSuiteComponent] {
    let definitions: [(String, EvaluationMetricsProfile, EvaluationSpeechOrigin, Double)] = [
        ("open-asr-english-nightly-v1", .standard, .humanRead, 0.10),
        ("edacc-english-nightly-v1", .standard, .humanNatural, 0.20),
        ("berst-english-nightly-v1", .stress, .humanNatural, 0.30),
        ("musan-no-speech-nightly-v1", .negativeControl, .noSpeech, 0),
    ]
    return definitions.map { id, profile, origin, _ in
        let subsetID = "\(id)-subset"
        let reference = origin == .noSpeech ? "" : "reference"
        let manifest = EvaluationSuiteManifest(
            schemaVersion: 2,
            id: id,
            name: id,
            language: "en",
            dataset: EvaluationDatasetSource(
                id: id,
                revision: String(repeating: "c", count: 40),
                viewerBaseURL: "https://datasets-server.huggingface.co"
            ),
            durationLanes: [EvaluationDurationLane(id: "universal", maxAudioSeconds: 29)],
            requiredDurationBuckets: [.seconds1To3],
            subsets: [
                EvaluationSubset(
                    id: subsetID,
                    config: "default",
                    split: "test",
                    role: origin == .noSpeech ? .negativeControl : .publicQuality,
                    speechOrigin: origin,
                    license: "CC-BY-4.0",
                    sourceURL: "https://example.com/\(id)"
                )
            ],
            items: [
                EvaluationCorpusItem(
                    id: "\(id)-item",
                    subsetID: subsetID,
                    row: 0,
                    audio: "\(id).wav",
                    reference: reference,
                    durationMs: 2_000,
                    durationBucket: .seconds1To3,
                    sizeBytes: 100,
                    sha256: String(repeating: "d", count: 64)
                )
            ]
        )
        let component = EvaluationSuiteComponent(
            id: id,
            manifest: "\(id).json",
            sha256: String(repeating: "e", count: 64),
            maxAudioSeconds: 29,
            metricsProfile: profile
        )
        return ResolvedEvaluationSuiteComponent(
            component: component,
            manifestURL: URL(fileURLWithPath: "/tmp/\(id).json"),
            manifest: manifest
        )
    }
}

private func ratingRun(
    resolved: [ResolvedEvaluationSuiteComponent],
    runID: String,
    latency: Int,
    noSpeechFalsePositive: Bool
) -> CatalogRatingRunEvidence {
    let wordErrorRates: [String: Double] = [
        "open-asr-english-nightly-v1": 0.10,
        "edacc-english-nightly-v1": 0.20,
        "berst-english-nightly-v1": 0.30,
    ]
    let host = EvaluationHostSnapshot(
        chip: "Apple M4 Max",
        operatingSystem: "macOS 26.5.2 (25F84)",
        architecture: "arm64"
    )
    var results: [String: [String: EvaluationRunResult]] = [:]
    var sessions: [String: EvaluationBatchSessionSnapshot] = [:]
    for component in resolved {
        let id = component.component.id
        let item = component.manifest.items[0]
        let noSpeech = component.component.metricsProfile == .negativeControl
        let falsePositiveText = noSpeech && noSpeechFalsePositive ? "invented words" : ""
        let errors = Int((wordErrorRates[id, default: 0] * 100).rounded())
        let accuracy = EvaluationAccuracySnapshot(
            referenceText: item.reference,
            hypothesisText: noSpeech ? falsePositiveText : "hypothesis",
            referenceWordCount: noSpeech ? 0 : 100,
            hypothesisWordCount: falsePositiveText.isEmpty ? (noSpeech ? 0 : 1) : 2,
            wordErrors: noSpeech ? (falsePositiveText.isEmpty ? 0 : 2) : errors,
            referenceCharacterCount: noSpeech ? 0 : 500,
            hypothesisCharacterCount: noSpeech ? falsePositiveText.count : 10,
            characterErrors: noSpeech ? falsePositiveText.count : errors
        )
        let production = EvaluationProductionSnapshot(
            applicationText: accuracy.hypothesisText,
            discarded: false,
            noSpeechProbability: 0.1,
            averageLogProbability: -0.2,
            compressionRatio: 1.0
        )
        let result = EvaluationRunResult(
            schemaVersion: 2,
            engine: "test-engine",
            engineVersion: "test-engine-1",
            model: "test-model",
            modelLicense: "MIT",
            computeBackend: "test-backend",
            feedMode: "accelerated",
            host: host,
            audio: EvaluationAudioSnapshot(durationMs: item.durationMs),
            timing: EvaluationTimingSnapshot(
                modelLoadMs: 50,
                warmupMs: 20,
                releaseToFinalMs: latency,
                realTimeFactor: 0.05
            ),
            accuracy: accuracy,
            production: production,
            resources: EvaluationResourceSnapshot(peakResidentBytes: 1_000)
        )
        results[id] = [item.id: result]
        sessions[id] = EvaluationBatchSessionSnapshot(
            schemaVersion: 1,
            engine: result.engine,
            model: result.model,
            feedMode: result.feedMode,
            host: host,
            modelLoadCount: 1,
            modelLoadMs: 50,
            warmupCount: 1,
            warmupMs: 20,
            completedItems: 1
        )
    }
    return CatalogRatingRunEvidence(
        metadata: CatalogRatingRunMetadata(
            schemaVersion: 1,
            runID: runID,
            modelID: "test-model",
            engine: "test-engine",
            artifactFingerprint: String(repeating: "b", count: 64),
            createdAt: "2026-07-22T00:00:00Z",
            gitCommit: String(repeating: "c", count: 40),
            suiteIndexSHA256: String(repeating: "a", count: 64)
        ),
        resultsByComponentID: results,
        sessionsByComponentID: sessions
    )
}
