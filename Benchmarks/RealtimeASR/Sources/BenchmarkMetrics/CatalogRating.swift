import Foundation

public struct EvaluationBatchSessionSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let engine: String
    public let model: String
    public let feedMode: String
    public let host: EvaluationHostSnapshot
    public let modelLoadCount: Int
    public let modelLoadMs: Int
    public let warmupCount: Int
    public let warmupMs: Int
    public let completedItems: Int
}

public struct CatalogRatingRunMetadata: Codable, Sendable {
    public let schemaVersion: Int
    public let runID: String
    public let modelID: String
    public let engine: String
    public let artifactFingerprint: String
    public let createdAt: String
    public let gitCommit: String
    public let suiteIndexSHA256: String

    public init(
        schemaVersion: Int,
        runID: String,
        modelID: String,
        engine: String,
        artifactFingerprint: String,
        createdAt: String,
        gitCommit: String,
        suiteIndexSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.modelID = modelID
        self.engine = engine
        self.artifactFingerprint = artifactFingerprint
        self.createdAt = createdAt
        self.gitCommit = gitCommit
        self.suiteIndexSHA256 = suiteIndexSHA256
    }
}

public struct CatalogRatingRunEvidence: Sendable {
    public let metadata: CatalogRatingRunMetadata
    public let resultsByComponentID: [String: [String: EvaluationRunResult]]
    public let sessionsByComponentID: [String: EvaluationBatchSessionSnapshot]

    public init(
        metadata: CatalogRatingRunMetadata,
        resultsByComponentID: [String: [String: EvaluationRunResult]],
        sessionsByComponentID: [String: EvaluationBatchSessionSnapshot]
    ) {
        self.metadata = metadata
        self.resultsByComponentID = resultsByComponentID
        self.sessionsByComponentID = sessionsByComponentID
    }
}

public struct CatalogBenchmarkRating: Codable, Sendable {
    public let schemaVersion: Int
    public let policyID: String
    public let suiteID: String
    public let suiteIndexSHA256: String
    public let modelID: String
    public let engine: String
    public let engineVersion: String
    public let modelLicense: String
    public let computeBackend: String
    public let artifactFingerprint: String
    public let sourceRevision: String
    public let language: String
    public let measuredAt: String
    public let referenceHost: EvaluationHostSnapshot
    public let runCount: Int
    public let quality: CatalogQualityRating
    public let speed: CatalogSpeedRating?
    public let speedUnratedReason: String?
}

public struct CatalogQualityRating: Codable, Sendable {
    public let score: Int
    public let level: Int
    public let label: String
    public let speechItems: Int
    public let noSpeechItems: Int
    public let noSpeechFalsePositiveRate: Double
    public let components: [CatalogQualityComponentRating]
}

public struct CatalogQualityComponentRating: Codable, Sendable {
    public let id: String
    public let wordErrorRate: Double
    public let score: Double
    public let weight: Double
}

public struct CatalogSpeedRating: Codable, Sendable {
    public let score: Int
    public let level: Int
    public let label: String
    public let p50ReleaseToFinalMs: Int
    public let p95ReleaseToFinalMs: Int
    public let p95RealTimeFactor: Double
    public let relativeP95Spread: Double
}

public enum CatalogRatingBuilder {
    public static func build(
        policy: CatalogRatingPolicy,
        index: EvaluationSuiteIndex,
        resolvedComponents: [ResolvedEvaluationSuiteComponent],
        suiteIndexSHA256: String,
        modelID: String,
        artifactFingerprint: String,
        measuredAt: String,
        runs: [CatalogRatingRunEvidence]
    ) throws -> CatalogBenchmarkRating {
        guard index.id == policy.suiteID, index.language == policy.language else {
            throw CatalogRatingError.policySuiteMismatch
        }
        guard isRatingSHA256(suiteIndexSHA256) else {
            throw CatalogRatingError.invalidSuiteIndexSHA256
        }
        guard isRatingSHA256(artifactFingerprint) else {
            throw CatalogRatingError.invalidArtifactFingerprint
        }
        guard ISO8601DateFormatter().date(from: measuredAt) != nil else {
            throw CatalogRatingError.invalidMeasurementDate
        }
        guard runs.count == policy.speed.requiredRuns else {
            throw CatalogRatingError.wrongRunCount(
                expected: policy.speed.requiredRuns,
                actual: runs.count
            )
        }

        let componentIDs = Set(resolvedComponents.map { $0.component.id })
        let expectedComponentIDs = Set(
            policy.quality.components.map(\.id) + [policy.quality.noSpeechComponentID]
        )
        guard componentIDs == expectedComponentIDs,
              componentIDs == Set(index.components.map(\.id))
        else {
            throw CatalogRatingError.componentSetMismatch
        }

        let resolvedByID = Dictionary(
            uniqueKeysWithValues: resolvedComponents.map { ($0.component.id, $0) }
        )
        var reportsByRun: [[String: EvaluationReport]] = []
        var referenceIdentity: EvaluationRunIdentity?
        var runIDs = Set<String>()
        var referenceGitCommit: String?

        for (runIndex, run) in runs.enumerated() {
            let metadata = run.metadata
            guard metadata.schemaVersion == 1,
                  isRatingRunID(metadata.runID),
                  runIDs.insert(metadata.runID).inserted,
                  metadata.modelID == modelID,
                  metadata.artifactFingerprint == artifactFingerprint,
                  metadata.suiteIndexSHA256 == suiteIndexSHA256,
                  ISO8601DateFormatter().date(from: metadata.createdAt) != nil,
                  isRatingGitCommit(metadata.gitCommit)
            else {
                throw CatalogRatingError.invalidRunMetadata(runIndex + 1)
            }
            if let referenceGitCommit {
                guard metadata.gitCommit == referenceGitCommit else {
                    throw CatalogRatingError.inconsistentRuntimeRevision
                }
            } else {
                referenceGitCommit = metadata.gitCommit
            }
            guard Set(run.resultsByComponentID.keys) == componentIDs,
                  Set(run.sessionsByComponentID.keys) == componentIDs
            else {
                throw CatalogRatingError.incompleteRun(runIndex + 1)
            }
            var reports: [String: EvaluationReport] = [:]
            for componentID in componentIDs.sorted() {
                guard let resolved = resolvedByID[componentID],
                      let results = run.resultsByComponentID[componentID],
                      let session = run.sessionsByComponentID[componentID]
                else {
                    throw CatalogRatingError.incompleteRun(runIndex + 1)
                }
                let report = try EvaluationReportBuilder.build(
                    manifest: resolved.manifest,
                    maxAudioSeconds: resolved.component.maxAudioSeconds,
                    resultsByItemID: results
                )
                guard report.complete,
                      report.productionFilteringApplied,
                      report.identity.model == modelID,
                      report.identity.engine == metadata.engine,
                      report.identity.feedMode == policy.speed.requiredFeedMode,
                      report.identity.host.chip == policy.speed.referenceChip
                else {
                    throw CatalogRatingError.incomparableResult(componentID)
                }
                guard session.schemaVersion == 1,
                      session.engine == report.identity.engine,
                      session.model == report.identity.model,
                      session.feedMode == report.identity.feedMode,
                      session.host == report.identity.host,
                      session.modelLoadCount == 1,
                      session.warmupCount == 1,
                      session.completedItems == report.completedItems
                else {
                    throw CatalogRatingError.invalidResidentSession(componentID)
                }
                if let referenceIdentity {
                    guard report.identity == referenceIdentity else {
                        throw CatalogRatingError.inconsistentIdentity(componentID)
                    }
                } else {
                    referenceIdentity = report.identity
                }
                reports[componentID] = report
            }
            reportsByRun.append(reports)
        }

        guard let identity = referenceIdentity, let sourceRevision = referenceGitCommit else {
            throw CatalogRatingError.componentSetMismatch
        }
        let quality = try qualityRating(policy: policy, reportsByRun: reportsByRun)
        let speedResult = speedRating(
            policy: policy,
            resolvedByID: resolvedByID,
            runs: runs
        )
        return CatalogBenchmarkRating(
            schemaVersion: 1,
            policyID: policy.id,
            suiteID: index.id,
            suiteIndexSHA256: suiteIndexSHA256,
            modelID: modelID,
            engine: identity.engine,
            engineVersion: identity.engineVersion,
            modelLicense: identity.modelLicense,
            computeBackend: identity.computeBackend,
            artifactFingerprint: artifactFingerprint,
            sourceRevision: sourceRevision,
            language: policy.language,
            measuredAt: measuredAt,
            referenceHost: identity.host,
            runCount: runs.count,
            quality: quality,
            speed: speedResult.rating,
            speedUnratedReason: speedResult.unratedReason
        )
    }

    private static func qualityRating(
        policy: CatalogRatingPolicy,
        reportsByRun: [[String: EvaluationReport]]
    ) throws -> CatalogQualityRating {
        var components: [CatalogQualityComponentRating] = []
        var weightedScore = 0.0
        var speechItems = 0
        for componentPolicy in policy.quality.components {
            let reports = try reportsByRun.map { reports in
                guard let report = reports[componentPolicy.id],
                      let wordErrorRate = report.quality.microWordErrorRate
                else {
                    throw CatalogRatingError.missingQuality(componentPolicy.id)
                }
                return (report, wordErrorRate)
            }
            let wordErrorRate = median(reports.map(\.1))
            let score = lowerIsBetterScore(
                value: wordErrorRate,
                excellent: componentPolicy.excellentWordErrorRate,
                unacceptable: componentPolicy.unacceptableWordErrorRate
            )
            weightedScore += score * componentPolicy.weight
            speechItems += reports[0].0.completedItems
            components.append(
                CatalogQualityComponentRating(
                    id: componentPolicy.id,
                    wordErrorRate: wordErrorRate,
                    score: score,
                    weight: componentPolicy.weight
                )
            )
        }

        let noSpeechReports = try reportsByRun.map { reports in
            guard let report = reports[policy.quality.noSpeechComponentID],
                  let noSpeech = report.quality.noSpeech,
                  let falsePositiveRate = noSpeech.falsePositiveRate
            else {
                throw CatalogRatingError.missingNoSpeechQuality
            }
            return (report, falsePositiveRate)
        }
        let falsePositiveRate = median(noSpeechReports.map(\.1))
        let score = Int(weightedScore.rounded())
        let uncappedLevel = policy.level(for: score).level
        let maximumLevel = policy.quality.noSpeechCaps.first(where: {
            falsePositiveRate > $0.aboveFalsePositiveRate
        })?.maximumLevel ?? 5
        let level = min(uncappedLevel, maximumLevel)
        let levelPolicy = policy.levels.first(where: { $0.level == level })!
        return CatalogQualityRating(
            score: score,
            level: level,
            label: levelPolicy.qualityLabel,
            speechItems: speechItems,
            noSpeechItems: noSpeechReports[0].0.completedItems,
            noSpeechFalsePositiveRate: falsePositiveRate,
            components: components
        )
    }

    private static func speedRating(
        policy: CatalogRatingPolicy,
        resolvedByID: [String: ResolvedEvaluationSuiteComponent],
        runs: [CatalogRatingRunEvidence]
    ) -> (rating: CatalogSpeedRating?, unratedReason: String?) {
        let speechComponentIDs = Set(policy.quality.components.map(\.id))
        let runMetrics: [(p50: Int, p95: Int, p95RTF: Double)] = runs.map { run in
            let results = speechComponentIDs.flatMap { componentID -> [EvaluationRunResult] in
                guard resolvedByID[componentID] != nil else { return [] }
                return Array(run.resultsByComponentID[componentID, default: [:]].values)
            }
            return (
                p50: nearestRank(results.map { $0.timing.releaseToFinalMs }, percentile: 0.50),
                p95: nearestRank(results.map { $0.timing.releaseToFinalMs }, percentile: 0.95),
                p95RTF: nearestRank(results.map { $0.timing.realTimeFactor }, percentile: 0.95)
            )
        }
        let latencySpread = relativeSpread(runMetrics.map(\.p95))
        let realTimeSpread = relativeSpread(runMetrics.map(\.p95RTF))
        let spread = max(latencySpread, realTimeSpread)
        guard spread <= policy.speed.maximumRelativeP95Spread else {
            return (nil, "unstable-p95")
        }

        let p50 = median(runMetrics.map(\.p50))
        let p95 = median(runMetrics.map(\.p95))
        let p95RTF = median(runMetrics.map(\.p95RTF))
        let latencyScore = lowerIsBetterScore(
            value: Double(p95),
            excellent: Double(policy.speed.excellentP95ReleaseToFinalMs),
            unacceptable: Double(policy.speed.unacceptableP95ReleaseToFinalMs)
        )
        let realTimeScore = lowerIsBetterScore(
            value: p95RTF,
            excellent: policy.speed.excellentP95RealTimeFactor,
            unacceptable: policy.speed.unacceptableP95RealTimeFactor
        )
        let score = Int((
            latencyScore * policy.speed.releaseToFinalWeight
                + realTimeScore * policy.speed.realTimeFactorWeight
        ).rounded())
        let levelPolicy = policy.level(for: score)
        return (
            CatalogSpeedRating(
                score: score,
                level: levelPolicy.level,
                label: levelPolicy.speedLabel,
                p50ReleaseToFinalMs: p50,
                p95ReleaseToFinalMs: p95,
                p95RealTimeFactor: p95RTF,
                relativeP95Spread: spread
            ),
            nil
        )
    }
}

public enum CatalogRatingError: Error, Equatable, CustomStringConvertible {
    case policySuiteMismatch
    case invalidSuiteIndexSHA256
    case invalidArtifactFingerprint
    case invalidMeasurementDate
    case wrongRunCount(expected: Int, actual: Int)
    case componentSetMismatch
    case incompleteRun(Int)
    case invalidRunMetadata(Int)
    case inconsistentRuntimeRevision
    case incomparableResult(String)
    case invalidResidentSession(String)
    case inconsistentIdentity(String)
    case missingQuality(String)
    case missingNoSpeechQuality

    public var description: String {
        switch self {
        case .policySuiteMismatch:
            return "Rating policy does not match the evaluation suite."
        case .invalidSuiteIndexSHA256:
            return "Rating suite index SHA-256 is invalid."
        case .invalidArtifactFingerprint:
            return "Rating model artifact fingerprint is invalid."
        case .invalidMeasurementDate:
            return "Rating measurement date must be ISO-8601."
        case let .wrongRunCount(expected, actual):
            return "Rating requires \(expected) runs, received \(actual)."
        case .componentSetMismatch:
            return "Rating suite components do not match the policy."
        case let .incompleteRun(run):
            return "Rating run \(run) is missing a component or resident session."
        case let .invalidRunMetadata(run):
            return "Rating run \(run) has invalid or mismatched provenance metadata."
        case .inconsistentRuntimeRevision:
            return "Rating runs were produced by different runtime revisions."
        case let .incomparableResult(component):
            return "Rating result is incomplete or incomparable: \(component)"
        case let .invalidResidentSession(component):
            return "Rating component was not produced by one resident load and warmup: \(component)"
        case let .inconsistentIdentity(component):
            return "Rating component uses a different model, backend, mode, or host: \(component)"
        case let .missingQuality(component):
            return "Rating component is missing speech quality: \(component)"
        case .missingNoSpeechQuality:
            return "Rating suite is missing no-speech quality."
        }
    }
}

private func lowerIsBetterScore(value: Double, excellent: Double, unacceptable: Double) -> Double {
    min(100, max(0, (unacceptable - value) / (unacceptable - excellent) * 100))
}

private func nearestRank<T: Comparable>(_ values: [T], percentile: Double) -> T {
    let sorted = values.sorted()
    let index = max(0, Int(ceil(percentile * Double(sorted.count))) - 1)
    return sorted[index]
}

private func median(_ values: [Int]) -> Int {
    nearestRank(values, percentile: 0.50)
}

private func median(_ values: [Double]) -> Double {
    nearestRank(values, percentile: 0.50)
}

private func relativeSpread(_ values: [Int]) -> Double {
    relativeSpread(values.map(Double.init))
}

private func relativeSpread(_ values: [Double]) -> Double {
    let middle = median(values)
    guard middle > 0, let minimum = values.min(), let maximum = values.max() else { return 0 }
    return (maximum - minimum) / middle
}

private func isRatingSHA256(_ value: String) -> Bool {
    let allowed = Set("0123456789abcdef")
    return value.count == 64 && value.allSatisfy(allowed.contains)
}

private func isRatingGitCommit(_ value: String) -> Bool {
    (value.count == 40 || value.count == 64)
        && value.allSatisfy(Set("0123456789abcdef").contains)
}

private func isRatingRunID(_ value: String) -> Bool {
    !value.isEmpty
        && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0))
        }
}
