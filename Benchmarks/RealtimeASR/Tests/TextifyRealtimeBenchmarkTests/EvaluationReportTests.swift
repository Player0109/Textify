import Testing
@testable import BenchmarkMetrics

@Test func evaluationReportUsesCorpusMacroWERAndNearestRankLatencyPercentiles() throws {
    let report = try EvaluationReportBuilder.build(
        manifest: reportManifest,
        maxAudioSeconds: 29,
        resultsByItemID: [
            "read-item": result(referenceWords: 10, errors: 1, latencyMs: 100, realTimeFactor: 0.1),
            "natural-item": result(referenceWords: 2, errors: 1, latencyMs: 300, realTimeFactor: 0.3),
        ]
    )

    #expect(report.complete)
    #expect(report.completedItems == 2)
    #expect(report.quality.microWordErrorRate == 2.0 / 12.0)
    #expect(report.quality.macroWordErrorRate == 0.3)
    #expect(report.timing.releaseToFinalMs.p50 == 100)
    #expect(report.timing.releaseToFinalMs.p90 == 300)
    #expect(report.timing.releaseToFinalMs.p95 == 300)
    #expect(report.timing.realTimeFactor.p50 == 0.1)
    #expect(report.timing.realTimeFactor.p95 == 0.3)
}

@Test func evaluationReportNamesMissingResultsWithoutDroppingExpectations() throws {
    let report = try EvaluationReportBuilder.build(
        manifest: reportManifest,
        maxAudioSeconds: 29,
        resultsByItemID: [
            "read-item": result(referenceWords: 10, errors: 1, latencyMs: 100, realTimeFactor: 0.1)
        ]
    )

    #expect(!report.complete)
    #expect(report.expectedItems == 2)
    #expect(report.completedItems == 1)
    #expect(report.missingItemIDs == ["natural-item"])
}

@Test func evaluationReportSeparatesNoSpeechFalsePositivesFromWER() throws {
    let report = try EvaluationReportBuilder.build(
        manifest: noSpeechReportManifest,
        maxAudioSeconds: 29,
        resultsByItemID: [
            "quiet-item": result(
                referenceText: "",
                referenceWords: 0,
                errors: 0,
                hypothesisText: "",
                hypothesisWords: 0,
                hypothesisCharacters: 0,
                latencyMs: 100,
                realTimeFactor: 0.1
            ),
            "hallucinated-item": result(
                referenceText: "",
                referenceWords: 0,
                errors: 4,
                hypothesisText: "thank you for watching",
                hypothesisWords: 4,
                hypothesisCharacters: 19,
                latencyMs: 200,
                realTimeFactor: 0.2
            ),
        ]
    )

    #expect(report.schemaVersion == 3)
    #expect(report.quality.microWordErrorRate == nil)
    #expect(report.quality.macroWordErrorRate == nil)
    #expect(report.quality.subsets.isEmpty)
    #expect(report.quality.noSpeech?.expectedItems == 2)
    #expect(report.quality.noSpeech?.completedItems == 2)
    #expect(report.quality.noSpeech?.falsePositiveItems == 1)
    #expect(report.quality.noSpeech?.falsePositiveRate == 0.5)
    #expect(report.quality.noSpeech?.hallucinatedWords == 4)
    #expect(report.quality.noSpeech?.hallucinatedCharacters == 19)
}

@Test func evaluationReportScoresTheProductionFilteringDecision() throws {
    let report = try EvaluationReportBuilder.build(
        manifest: noSpeechReportManifest,
        maxAudioSeconds: 29,
        resultsByItemID: [
            "quiet-item": result(
                referenceText: "",
                referenceWords: 0,
                errors: 0,
                hypothesisText: "[BLANK_AUDIO]",
                hypothesisWords: 1,
                hypothesisCharacters: 13,
                latencyMs: 100,
                realTimeFactor: 0.1,
                production: EvaluationProductionSnapshot(
                    applicationText: "",
                    discarded: true,
                    noSpeechProbability: 0.92,
                    averageLogProbability: -0.4,
                    compressionRatio: 1.0
                )
            ),
            "hallucinated-item": result(
                referenceText: "",
                referenceWords: 0,
                errors: 4,
                hypothesisText: "invented spoken words",
                hypothesisWords: 3,
                hypothesisCharacters: 21,
                latencyMs: 200,
                realTimeFactor: 0.2,
                production: EvaluationProductionSnapshot(
                    applicationText: "invented spoken words",
                    discarded: false,
                    noSpeechProbability: 0.1,
                    averageLogProbability: -0.2,
                    compressionRatio: 1.0
                )
            ),
        ]
    )

    #expect(report.productionFilteringApplied)
    #expect(report.quality.noSpeech?.falsePositiveItems == 1)
    #expect(report.quality.noSpeech?.hallucinatedWords == 3)
}

@Test func evaluationReportCountsDiscardedSpeechAsDeletions() throws {
    let report = try EvaluationReportBuilder.build(
        manifest: reportManifest,
        maxAudioSeconds: 29,
        resultsByItemID: [
            "read-item": result(
                referenceWords: 10,
                errors: 1,
                latencyMs: 100,
                realTimeFactor: 0.1,
                production: EvaluationProductionSnapshot(
                    applicationText: "",
                    discarded: true,
                    noSpeechProbability: 0.7,
                    averageLogProbability: -0.2,
                    compressionRatio: 1.0
                )
            ),
            "natural-item": result(
                referenceWords: 2,
                errors: 1,
                latencyMs: 300,
                realTimeFactor: 0.3,
                production: EvaluationProductionSnapshot(
                    applicationText: "hypothesis",
                    discarded: false,
                    noSpeechProbability: 0.1,
                    averageLogProbability: -0.2,
                    compressionRatio: 1.0
                )
            ),
        ]
    )

    #expect(report.productionFilteringApplied)
    #expect(report.quality.microWordErrorRate == 11.0 / 12.0)
}

@Test func evaluationReportDoesNotTreatLegacySchemaAsProductionEvidence() throws {
    let legacy = result(
        referenceWords: 10,
        errors: 1,
        latencyMs: 100,
        realTimeFactor: 0.1,
        production: EvaluationProductionSnapshot(
            applicationText: "hypothesis",
            discarded: false,
            noSpeechProbability: 0.1,
            averageLogProbability: -0.2,
            compressionRatio: 1.0
        ),
        schemaVersion: 1
    )
    let report = try EvaluationReportBuilder.build(
        manifest: reportManifest,
        maxAudioSeconds: 29,
        resultsByItemID: ["read-item": legacy]
    )

    #expect(!report.productionFilteringApplied)
}

@Test func evaluationReportDoesNotCountNoSpeechOutputAsSpeechErrors() throws {
    let manifest = EvaluationSuiteManifest(
        schemaVersion: 1,
        id: "mixed-report-suite",
        name: "Mixed report suite",
        language: "en",
        dataset: reportManifest.dataset,
        durationLanes: reportManifest.durationLanes,
        requiredDurationBuckets: reportManifest.requiredDurationBuckets,
        subsets: reportManifest.subsets + noSpeechReportManifest.subsets,
        items: reportManifest.items + [noSpeechReportManifest.items[1]]
    )
    let report = try EvaluationReportBuilder.build(
        manifest: manifest,
        maxAudioSeconds: 29,
        resultsByItemID: [
            "read-item": result(referenceWords: 10, errors: 1, latencyMs: 100, realTimeFactor: 0.1),
            "natural-item": result(referenceWords: 2, errors: 1, latencyMs: 300, realTimeFactor: 0.3),
            "hallucinated-item": result(
                referenceText: "",
                referenceWords: 0,
                errors: 4,
                hypothesisText: "thank you for watching",
                hypothesisWords: 4,
                hypothesisCharacters: 19,
                latencyMs: 200,
                realTimeFactor: 0.2
            ),
        ]
    )

    #expect(report.quality.microWordErrorRate == 2.0 / 12.0)
    #expect(report.quality.macroWordErrorRate == 0.3)
    #expect(report.quality.noSpeech?.falsePositiveItems == 1)
}

@Test func evaluationReportAggregatesManifestSliceDimensions() throws {
    let manifest = EvaluationSuiteManifest(
        schemaVersion: 2,
        id: "slice-report-suite",
        name: "Slice report suite",
        language: "en",
        dataset: reportManifest.dataset,
        durationLanes: reportManifest.durationLanes,
        requiredDurationBuckets: reportManifest.requiredDurationBuckets,
        subsets: reportManifest.subsets,
        items: [
            reportItem(
                id: "read-item",
                subsetID: "read",
                sha: String(repeating: "a", count: 64),
                slices: ["device": "phone", "shoutLevel": "no-shout"]
            ),
            reportItem(
                id: "natural-item",
                subsetID: "natural",
                sha: String(repeating: "b", count: 64),
                slices: ["device": "phone", "shoutLevel": "shout"]
            ),
        ]
    )
    let report = try EvaluationReportBuilder.build(
        manifest: manifest,
        maxAudioSeconds: 29,
        resultsByItemID: [
            "read-item": result(referenceWords: 10, errors: 1, latencyMs: 100, realTimeFactor: 0.1),
            "natural-item": result(referenceWords: 2, errors: 1, latencyMs: 300, realTimeFactor: 0.3),
        ]
    )

    let device = try #require(
        report.quality.slices.first { $0.dimension == "device" && $0.value == "phone" }
    )
    #expect(device.completedItems == 2)
    #expect(device.referenceWords == 12)
    #expect(device.wordErrors == 2)
    #expect(device.wordErrorRate == 2.0 / 12.0)
    #expect(report.quality.slices.filter { $0.dimension == "shoutLevel" }.count == 2)
    #expect(
        report.quality.slices.first {
            $0.dimension == "durationBucket" && $0.value == "1-3"
        }?.completedItems == 2
    )
}

private let reportManifest = EvaluationSuiteManifest(
    schemaVersion: 1,
    id: "report-suite",
    name: "Report suite",
    language: "en",
    dataset: EvaluationDatasetSource(
        id: "example/report-suite",
        revision: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        viewerBaseURL: "https://datasets-server.huggingface.co"
    ),
    durationLanes: [EvaluationDurationLane(id: "universal", maxAudioSeconds: 29)],
    requiredDurationBuckets: [.seconds1To3],
    subsets: [
        EvaluationSubset(
            id: "read",
            config: "read",
            split: "test",
            role: .publicQuality,
            speechOrigin: .humanRead,
            license: "CC-BY-4.0",
            sourceURL: "https://example.com/read"
        ),
        EvaluationSubset(
            id: "natural",
            config: "natural",
            split: "test",
            role: .publicQuality,
            speechOrigin: .humanNatural,
            license: "CC-BY-4.0",
            sourceURL: "https://example.com/natural"
        ),
    ],
    items: [
        reportItem(id: "read-item", subsetID: "read", sha: String(repeating: "a", count: 64)),
        reportItem(id: "natural-item", subsetID: "natural", sha: String(repeating: "b", count: 64)),
    ]
)

private let noSpeechReportManifest = EvaluationSuiteManifest(
    schemaVersion: 1,
    id: "no-speech-report-suite",
    name: "No-speech report suite",
    language: "en",
    dataset: EvaluationDatasetSource(
        id: "example/no-speech-suite",
        revision: "cccccccccccccccccccccccccccccccccccccccc",
        viewerBaseURL: "https://datasets-server.huggingface.co"
    ),
    durationLanes: [EvaluationDurationLane(id: "universal", maxAudioSeconds: 29)],
    requiredDurationBuckets: [.seconds1To3],
    subsets: [
        EvaluationSubset(
            id: "environmental-noise",
            config: "noise",
            split: "test",
            role: .negativeControl,
            speechOrigin: .noSpeech,
            license: "Public Domain",
            sourceURL: "https://example.com/noise"
        ),
    ],
    items: [
        reportItem(
            id: "quiet-item",
            subsetID: "environmental-noise",
            reference: "",
            sha: String(repeating: "c", count: 64)
        ),
        reportItem(
            id: "hallucinated-item",
            subsetID: "environmental-noise",
            reference: "",
            sha: String(repeating: "d", count: 64)
        ),
    ]
)

private func reportItem(
    id: String,
    subsetID: String,
    reference: String = "reference",
    sha: String,
    slices: [String: String]? = nil
) -> EvaluationCorpusItem {
    EvaluationCorpusItem(
        id: id,
        subsetID: subsetID,
        row: 0,
        audio: "\(id).wav",
        reference: reference,
        durationMs: 2_000,
        durationBucket: .seconds1To3,
        sizeBytes: 100,
        sha256: sha,
        slices: slices
    )
}

private func result(
    referenceText: String = "reference",
    referenceWords: Int,
    errors: Int,
    hypothesisText: String = "hypothesis",
    hypothesisWords: Int = 1,
    hypothesisCharacters: Int = 10,
    latencyMs: Int,
    realTimeFactor: Double,
    production: EvaluationProductionSnapshot? = nil,
    schemaVersion: Int? = nil
) -> EvaluationRunResult {
    EvaluationRunResult(
        schemaVersion: schemaVersion ?? (production == nil ? 1 : 2),
        engine: "test-engine",
        engineVersion: "test-engine-1",
        model: "test-model",
        modelLicense: "MIT",
        computeBackend: "test-backend",
        feedMode: "accelerated",
        host: EvaluationHostSnapshot(chip: "test-chip", operatingSystem: "test-os", architecture: "arm64"),
        audio: EvaluationAudioSnapshot(durationMs: 2_000),
        timing: EvaluationTimingSnapshot(
            modelLoadMs: 50,
            warmupMs: 20,
            releaseToFinalMs: latencyMs,
            realTimeFactor: realTimeFactor
        ),
        accuracy: EvaluationAccuracySnapshot(
            referenceText: referenceText,
            hypothesisText: hypothesisText,
            referenceWordCount: referenceWords,
            hypothesisWordCount: hypothesisWords,
            wordErrors: errors,
            referenceCharacterCount: referenceWords * 5,
            hypothesisCharacterCount: hypothesisCharacters,
            characterErrors: errors
        ),
        production: production,
        resources: EvaluationResourceSnapshot(peakResidentBytes: 1_000)
    )
}
