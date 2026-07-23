import Foundation

public struct EvaluationRunResult: Codable, Sendable {
    public let schemaVersion: Int
    public let engine: String
    public let engineVersion: String
    public let model: String
    public let modelLicense: String
    public let computeBackend: String
    public let feedMode: String
    public let host: EvaluationHostSnapshot
    public let audio: EvaluationAudioSnapshot
    public let timing: EvaluationTimingSnapshot
    public let accuracy: EvaluationAccuracySnapshot?
    public let production: EvaluationProductionSnapshot?
    public let resources: EvaluationResourceSnapshot
}

public struct EvaluationProductionSnapshot: Codable, Sendable {
    public let applicationText: String
    public let discarded: Bool
    public let noSpeechProbability: Double
    public let averageLogProbability: Double
    public let compressionRatio: Double

    public init(
        applicationText: String,
        discarded: Bool,
        noSpeechProbability: Double,
        averageLogProbability: Double,
        compressionRatio: Double
    ) {
        self.applicationText = applicationText
        self.discarded = discarded
        self.noSpeechProbability = noSpeechProbability
        self.averageLogProbability = averageLogProbability
        self.compressionRatio = compressionRatio
    }
}

public struct EvaluationHostSnapshot: Codable, Equatable, Sendable {
    public let chip: String
    public let operatingSystem: String
    public let architecture: String
}

public struct EvaluationAudioSnapshot: Codable, Sendable {
    public let durationMs: Int
}

public struct EvaluationTimingSnapshot: Codable, Sendable {
    public let modelLoadMs: Int
    public let warmupMs: Int
    public let releaseToFinalMs: Int
    public let realTimeFactor: Double
}

public struct EvaluationAccuracySnapshot: Codable, Sendable {
    public let referenceText: String
    public let hypothesisText: String
    public let referenceWordCount: Int
    public let hypothesisWordCount: Int
    public let wordErrors: Int
    public let referenceCharacterCount: Int
    public let hypothesisCharacterCount: Int
    public let characterErrors: Int
}

public struct EvaluationResourceSnapshot: Codable, Sendable {
    public let peakResidentBytes: Int64
}

public struct EvaluationReport: Codable, Sendable {
    public let schemaVersion: Int
    public let suiteID: String
    public let datasetRevision: String
    public let maxAudioSeconds: Int
    public let complete: Bool
    public let expectedItems: Int
    public let completedItems: Int
    public let missingItemIDs: [String]
    public let completedAudioDurationMs: Int
    public let productionFilteringApplied: Bool
    public let identity: EvaluationRunIdentity
    public let quality: EvaluationQualitySummary
    public let timing: EvaluationTimingSummary
    public let resources: EvaluationResourceSummary
}

public struct EvaluationRunIdentity: Codable, Equatable, Sendable {
    public let engine: String
    public let engineVersion: String
    public let model: String
    public let modelLicense: String
    public let computeBackend: String
    public let feedMode: String
    public let host: EvaluationHostSnapshot
}

public struct EvaluationQualitySummary: Codable, Sendable {
    public let microWordErrorRate: Double?
    public let macroWordErrorRate: Double?
    public let microCharacterErrorRate: Double?
    public let macroCharacterErrorRate: Double?
    public let subsets: [EvaluationSubsetQuality]
    public let slices: [EvaluationSliceQuality]
    public let noSpeech: EvaluationNoSpeechSummary?
}

public struct EvaluationSubsetQuality: Codable, Sendable {
    public let subsetID: String
    public let completedItems: Int
    public let referenceWords: Int
    public let wordErrors: Int
    public let wordErrorRate: Double?
    public let referenceCharacters: Int
    public let characterErrors: Int
    public let characterErrorRate: Double?
}

public struct EvaluationSliceQuality: Codable, Sendable {
    public let dimension: String
    public let value: String
    public let completedItems: Int
    public let referenceWords: Int
    public let wordErrors: Int
    public let wordErrorRate: Double?
    public let referenceCharacters: Int
    public let characterErrors: Int
    public let characterErrorRate: Double?
}

public struct EvaluationNoSpeechSummary: Codable, Sendable {
    public let expectedItems: Int
    public let completedItems: Int
    public let falsePositiveItems: Int
    public let falsePositiveRate: Double?
    public let hallucinatedWords: Int
    public let hallucinatedCharacters: Int
    public let subsets: [EvaluationNoSpeechSubsetQuality]
}

public struct EvaluationNoSpeechSubsetQuality: Codable, Sendable {
    public let subsetID: String
    public let expectedItems: Int
    public let completedItems: Int
    public let falsePositiveItems: Int
    public let falsePositiveRate: Double?
    public let hallucinatedWords: Int
    public let hallucinatedCharacters: Int
}

public struct EvaluationTimingSummary: Codable, Sendable {
    public let modelLoadMs: IntegerPercentiles
    public let warmupMs: IntegerPercentiles
    public let releaseToFinalMs: IntegerPercentiles
    public let realTimeFactor: DoublePercentiles
}

public struct IntegerPercentiles: Codable, Equatable, Sendable {
    public let p50: Int
    public let p90: Int
    public let p95: Int
}

public struct DoublePercentiles: Codable, Equatable, Sendable {
    public let p50: Double
    public let p90: Double
    public let p95: Double
}

public struct EvaluationResourceSummary: Codable, Sendable {
    public let maximumPeakResidentBytes: Int64
}

public enum EvaluationReportBuilder {
    public static func build(
        manifest: EvaluationSuiteManifest,
        maxAudioSeconds: Int,
        resultsByItemID: [String: EvaluationRunResult]
    ) throws -> EvaluationReport {
        let expected = manifest.compatibleItems(maxAudioSeconds: maxAudioSeconds)
        guard !expected.isEmpty else {
            throw EvaluationReportError.noCompatibleItems
        }

        let expectedIDs = Set(expected.map(\.id))
        if let unexpectedID = resultsByItemID.keys.sorted().first(where: { !expectedIDs.contains($0) }) {
            throw EvaluationReportError.unexpectedResult(unexpectedID)
        }

        let missingItemIDs = expected.compactMap { item in
            resultsByItemID[item.id] == nil ? item.id : nil
        }
        let completed = try expected.compactMap { item -> CompletedEvaluation? in
            guard let result = resultsByItemID[item.id] else { return nil }
            guard (1 ... 2).contains(result.schemaVersion) else {
                throw EvaluationReportError.unsupportedResultSchema(item.id)
            }
            if result.schemaVersion == 2, result.production == nil {
                throw EvaluationReportError.missingProductionSnapshot(item.id)
            }
            guard let accuracy = result.accuracy else {
                throw EvaluationReportError.missingAccuracy(item.id)
            }
            guard accuracy.referenceText == item.reference else {
                throw EvaluationReportError.referenceMismatch(item.id)
            }
            guard abs(result.audio.durationMs - item.durationMs) <= 2 else {
                throw EvaluationReportError.audioDurationMismatch(item.id)
            }
            let effectiveAccuracy = try productionAccuracy(
                itemID: item.id,
                accuracy: accuracy,
                production: result.production
            )
            return CompletedEvaluation(
                item: item,
                result: result,
                accuracy: effectiveAccuracy
            )
        }
        guard let first = completed.first else {
            throw EvaluationReportError.noResults
        }

        let identity = EvaluationRunIdentity(result: first.result)
        for value in completed.dropFirst() where EvaluationRunIdentity(result: value.result) != identity {
            throw EvaluationReportError.inconsistentRunIdentity(value.item.id)
        }

        let noSpeechSubsetIDs = Set(
            manifest.subsets
                .filter { $0.speechOrigin == .noSpeech }
                .map(\.id)
        )
        let speechCompleted = completed.filter { !noSpeechSubsetIDs.contains($0.item.subsetID) }
        let subsetQuality = manifest.subsets
            .filter { $0.speechOrigin != .noSpeech }
            .map { subset in
                quality(for: subset.id, completed: completed)
            }
        let observedSubsetQuality = subsetQuality.filter { $0.wordErrorRate != nil }

        let totalWords = speechCompleted.reduce(0) { $0 + $1.accuracy.referenceWordCount }
        let totalWordErrors = speechCompleted.reduce(0) { $0 + $1.accuracy.wordErrors }
        let totalCharacters = speechCompleted.reduce(0) { $0 + $1.accuracy.referenceCharacterCount }
        let totalCharacterErrors = speechCompleted.reduce(0) { $0 + $1.accuracy.characterErrors }
        let noSpeech = noSpeechQuality(
            expected: expected,
            completed: completed,
            subsets: manifest.subsets
        )

        return EvaluationReport(
            schemaVersion: 3,
            suiteID: manifest.id,
            datasetRevision: manifest.dataset.revision,
            maxAudioSeconds: maxAudioSeconds,
            complete: missingItemIDs.isEmpty,
            expectedItems: expected.count,
            completedItems: completed.count,
            missingItemIDs: missingItemIDs,
            completedAudioDurationMs: completed.reduce(0) { $0 + $1.result.audio.durationMs },
            productionFilteringApplied: completed.allSatisfy {
                $0.result.schemaVersion == 2 && $0.result.production != nil
            },
            identity: identity,
            quality: EvaluationQualitySummary(
                microWordErrorRate: totalWords > 0
                    ? rate(errors: totalWordErrors, references: totalWords)
                    : nil,
                macroWordErrorRate: observedSubsetQuality.isEmpty
                    ? nil
                    : mean(observedSubsetQuality.compactMap(\.wordErrorRate)),
                microCharacterErrorRate: totalCharacters > 0
                    ? rate(errors: totalCharacterErrors, references: totalCharacters)
                    : nil,
                macroCharacterErrorRate: observedSubsetQuality.isEmpty
                    ? nil
                    : mean(observedSubsetQuality.compactMap(\.characterErrorRate)),
                subsets: subsetQuality,
                slices: sliceQuality(completed: speechCompleted),
                noSpeech: noSpeech
            ),
            timing: EvaluationTimingSummary(
                modelLoadMs: percentiles(completed.map { $0.result.timing.modelLoadMs }),
                warmupMs: percentiles(completed.map { $0.result.timing.warmupMs }),
                releaseToFinalMs: percentiles(completed.map { $0.result.timing.releaseToFinalMs }),
                realTimeFactor: percentiles(completed.map { $0.result.timing.realTimeFactor })
            ),
            resources: EvaluationResourceSummary(
                maximumPeakResidentBytes: completed.map { $0.result.resources.peakResidentBytes }.max() ?? 0
            )
        )
    }

    private static func quality(
        for subsetID: String,
        completed: [CompletedEvaluation]
    ) -> EvaluationSubsetQuality {
        let matches = completed.filter { $0.item.subsetID == subsetID }
        let referenceWords = matches.reduce(0) { $0 + $1.accuracy.referenceWordCount }
        let wordErrors = matches.reduce(0) { $0 + $1.accuracy.wordErrors }
        let referenceCharacters = matches.reduce(0) { $0 + $1.accuracy.referenceCharacterCount }
        let characterErrors = matches.reduce(0) { $0 + $1.accuracy.characterErrors }
        return EvaluationSubsetQuality(
            subsetID: subsetID,
            completedItems: matches.count,
            referenceWords: referenceWords,
            wordErrors: wordErrors,
            wordErrorRate: referenceWords > 0 ? rate(errors: wordErrors, references: referenceWords) : nil,
            referenceCharacters: referenceCharacters,
            characterErrors: characterErrors,
            characterErrorRate: referenceCharacters > 0
                ? rate(errors: characterErrors, references: referenceCharacters)
                : nil
        )
    }

    private static func productionAccuracy(
        itemID: String,
        accuracy: EvaluationAccuracySnapshot,
        production: EvaluationProductionSnapshot?
    ) throws -> EvaluationAccuracySnapshot {
        guard let production else { return accuracy }
        guard !production.discarded || production.applicationText.isEmpty else {
            throw EvaluationReportError.invalidProductionSnapshot(itemID)
        }
        guard production.discarded || production.applicationText == accuracy.hypothesisText else {
            throw EvaluationReportError.invalidProductionSnapshot(itemID)
        }
        guard production.discarded else { return accuracy }
        return EvaluationAccuracySnapshot(
            referenceText: accuracy.referenceText,
            hypothesisText: "",
            referenceWordCount: accuracy.referenceWordCount,
            hypothesisWordCount: 0,
            wordErrors: accuracy.referenceWordCount,
            referenceCharacterCount: accuracy.referenceCharacterCount,
            hypothesisCharacterCount: 0,
            characterErrors: accuracy.referenceCharacterCount
        )
    }

    private static func noSpeechQuality(
        expected: [EvaluationCorpusItem],
        completed: [CompletedEvaluation],
        subsets: [EvaluationSubset]
    ) -> EvaluationNoSpeechSummary? {
        let noSpeechSubsets = subsets.filter { $0.speechOrigin == .noSpeech }
        let subsetIDs = Set(noSpeechSubsets.map(\.id))
        let expectedMatches = expected.filter { subsetIDs.contains($0.subsetID) }
        guard !expectedMatches.isEmpty else { return nil }

        let completedMatches = completed.filter { subsetIDs.contains($0.item.subsetID) }
        let subsetQuality = noSpeechSubsets.map { subset in
            noSpeechQuality(
                for: subset.id,
                expected: expectedMatches,
                completed: completedMatches
            )
        }
        let falsePositiveItems = completedMatches.filter(isFalsePositive).count
        return EvaluationNoSpeechSummary(
            expectedItems: expectedMatches.count,
            completedItems: completedMatches.count,
            falsePositiveItems: falsePositiveItems,
            falsePositiveRate: completedMatches.isEmpty
                ? nil
                : Double(falsePositiveItems) / Double(completedMatches.count),
            hallucinatedWords: completedMatches.reduce(0) {
                $0 + $1.accuracy.hypothesisWordCount
            },
            hallucinatedCharacters: completedMatches.reduce(0) {
                $0 + $1.accuracy.hypothesisCharacterCount
            },
            subsets: subsetQuality
        )
    }

    private static func sliceQuality(
        completed: [CompletedEvaluation]
    ) -> [EvaluationSliceQuality] {
        var grouped: [EvaluationSliceKey: [CompletedEvaluation]] = [:]
        for evaluation in completed {
            grouped[
                EvaluationSliceKey(
                    dimension: "durationBucket",
                    value: evaluation.item.durationBucket.rawValue
                ),
                default: []
            ].append(evaluation)
            for (dimension, value) in evaluation.item.slices ?? [:] {
                grouped[EvaluationSliceKey(dimension: dimension, value: value), default: []]
                    .append(evaluation)
            }
        }

        return grouped.keys.sorted().map { key in
            let matches = grouped[key, default: []]
            let referenceWords = matches.reduce(0) { $0 + $1.accuracy.referenceWordCount }
            let wordErrors = matches.reduce(0) { $0 + $1.accuracy.wordErrors }
            let referenceCharacters = matches.reduce(0) {
                $0 + $1.accuracy.referenceCharacterCount
            }
            let characterErrors = matches.reduce(0) { $0 + $1.accuracy.characterErrors }
            return EvaluationSliceQuality(
                dimension: key.dimension,
                value: key.value,
                completedItems: matches.count,
                referenceWords: referenceWords,
                wordErrors: wordErrors,
                wordErrorRate: referenceWords > 0
                    ? rate(errors: wordErrors, references: referenceWords)
                    : nil,
                referenceCharacters: referenceCharacters,
                characterErrors: characterErrors,
                characterErrorRate: referenceCharacters > 0
                    ? rate(errors: characterErrors, references: referenceCharacters)
                    : nil
            )
        }
    }

    private static func noSpeechQuality(
        for subsetID: String,
        expected: [EvaluationCorpusItem],
        completed: [CompletedEvaluation]
    ) -> EvaluationNoSpeechSubsetQuality {
        let expectedMatches = expected.filter { $0.subsetID == subsetID }
        let completedMatches = completed.filter { $0.item.subsetID == subsetID }
        let falsePositiveItems = completedMatches.filter(isFalsePositive).count
        return EvaluationNoSpeechSubsetQuality(
            subsetID: subsetID,
            expectedItems: expectedMatches.count,
            completedItems: completedMatches.count,
            falsePositiveItems: falsePositiveItems,
            falsePositiveRate: completedMatches.isEmpty
                ? nil
                : Double(falsePositiveItems) / Double(completedMatches.count),
            hallucinatedWords: completedMatches.reduce(0) {
                $0 + $1.accuracy.hypothesisWordCount
            },
            hallucinatedCharacters: completedMatches.reduce(0) {
                $0 + $1.accuracy.hypothesisCharacterCount
            }
        )
    }

    private static func isFalsePositive(_ evaluation: CompletedEvaluation) -> Bool {
        evaluation.accuracy.hypothesisCharacterCount > 0
    }

    private static func rate(errors: Int, references: Int) -> Double {
        guard references > 0 else { return 0 }
        return Double(errors) / Double(references)
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func percentiles(_ values: [Int]) -> IntegerPercentiles {
        let sorted = values.sorted()
        return IntegerPercentiles(
            p50: nearestRank(sorted, percentile: 0.50),
            p90: nearestRank(sorted, percentile: 0.90),
            p95: nearestRank(sorted, percentile: 0.95)
        )
    }

    private static func percentiles(_ values: [Double]) -> DoublePercentiles {
        let sorted = values.sorted()
        return DoublePercentiles(
            p50: nearestRank(sorted, percentile: 0.50),
            p90: nearestRank(sorted, percentile: 0.90),
            p95: nearestRank(sorted, percentile: 0.95)
        )
    }

    private static func nearestRank<T>(_ sorted: [T], percentile: Double) -> T {
        let index = max(0, Int(ceil(percentile * Double(sorted.count))) - 1)
        return sorted[index]
    }
}

public enum EvaluationReportError: Error, Equatable, CustomStringConvertible {
    case noCompatibleItems
    case unexpectedResult(String)
    case unsupportedResultSchema(String)
    case missingProductionSnapshot(String)
    case invalidProductionSnapshot(String)
    case missingAccuracy(String)
    case referenceMismatch(String)
    case audioDurationMismatch(String)
    case inconsistentRunIdentity(String)
    case noResults

    public var description: String {
        switch self {
        case .noCompatibleItems:
            return "The selected duration lane contains no corpus items."
        case let .unexpectedResult(id):
            return "Result does not belong to the selected corpus lane: \(id)"
        case let .unsupportedResultSchema(id):
            return "Result uses an unsupported schema version: \(id)"
        case let .missingProductionSnapshot(id):
            return "Schema V2 result is missing its production filtering decision: \(id)"
        case let .invalidProductionSnapshot(id):
            return "Result contains an inconsistent production filtering decision: \(id)"
        case let .missingAccuracy(id):
            return "Result does not contain reference-based accuracy data: \(id)"
        case let .referenceMismatch(id):
            return "Result reference does not match the pinned corpus reference: \(id)"
        case let .audioDurationMismatch(id):
            return "Result audio duration does not match the pinned corpus duration: \(id)"
        case let .inconsistentRunIdentity(id):
            return "Result was produced by a different model, engine, mode, backend, or host: \(id)"
        case .noResults:
            return "No benchmark result files were found for the selected duration lane."
        }
    }
}

private struct CompletedEvaluation {
    let item: EvaluationCorpusItem
    let result: EvaluationRunResult
    let accuracy: EvaluationAccuracySnapshot
}

private struct EvaluationSliceKey: Hashable, Comparable {
    let dimension: String
    let value: String

    static func < (lhs: EvaluationSliceKey, rhs: EvaluationSliceKey) -> Bool {
        if lhs.dimension != rhs.dimension {
            return lhs.dimension < rhs.dimension
        }
        return lhs.value < rhs.value
    }
}

private extension EvaluationRunIdentity {
    init(result: EvaluationRunResult) {
        self.init(
            engine: result.engine,
            engineVersion: result.engineVersion,
            model: result.model,
            modelLicense: result.modelLicense,
            computeBackend: result.computeBackend,
            feedMode: result.feedMode,
            host: result.host
        )
    }
}
