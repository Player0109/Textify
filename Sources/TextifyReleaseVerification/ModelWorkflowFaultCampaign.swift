import CryptoKit
import Foundation
import TextifyModels

public enum ModelWorkflowInjectedFault: String, CaseIterable, Codable, Sendable {
    case processTermination
    case diskFull
    case permissionFailure
    case checksumMismatch
    case truncation
    case renameFailure
    case missingFiles
    case extraFiles
    case catalogReplacement
    case incompatibility
    case revocation
}

public enum ModelWorkflowSecurityProbe: String, CaseIterable, Codable, Sendable {
    case traversal
    case symbolicLinkEscape
    case hardLinkEscape
    case archiveExpansionLimits
    case peakStorageAdmission
    case canonicalDigestAliasing
    case unsafeHelpURL
    case atomicFilesystemContainment
}

public struct ModelWorkflowSecurityProbeResult: Codable, Equatable, Sendable {
    public let probe: ModelWorkflowSecurityProbe
    public let passed: Bool
}

public struct ModelCatalogRequestEvidence: Codable, Equatable, Sendable {
    public let method: String
    public let path: String
    public let query: String?
    public let bodyBytes: Int
    public let localIdentityHeaders: [String]
}

public struct ModelDiagnosticsPrivacyEvidence: Codable, Equatable, Sendable {
    public let containsFullSHA256: Bool
}

public struct ModelWorkflowCoverageEvidence:
    Codable,
    Equatable,
    Sendable
{
    public let declaredTransitions: [String]
    public let transitionHitCounts: [String: Int]
    public let declaredInvariants: [String]
    public let invariantEvaluationCounts: [String: Int]
    public let invariantEvaluationCount: Int
    public let isComplete: Bool

    public init(
        declaredTransitions: [String],
        transitionHitCounts: [String: Int],
        declaredInvariants: [String],
        invariantEvaluationCounts: [String: Int]
    ) {
        self.declaredTransitions = declaredTransitions
        self.transitionHitCounts = transitionHitCounts
        self.declaredInvariants = declaredInvariants
        self.invariantEvaluationCounts = invariantEvaluationCounts
        invariantEvaluationCount =
            invariantEvaluationCounts.values.reduce(0, +)
        isComplete =
            Set(transitionHitCounts.keys) == Set(declaredTransitions)
            && transitionHitCounts.values.allSatisfy { $0 > 0 }
            && Set(invariantEvaluationCounts.keys)
                == Set(declaredInvariants)
            && invariantEvaluationCounts.values.allSatisfy { $0 > 0 }
    }
}

public struct ModelWorkflowFaultExecution: Codable, Equatable, Sendable {
    public let boundary: ModelWorkflowDurableBoundary
    public let fault: ModelWorkflowInjectedFault
    public let modelInvariantHeld: Bool
}

public struct ModelWorkflowFaultCampaignReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let seed: UInt64
    public let operationCount: Int
    public let durableQueueSoak: ModelDurableQueueSoakReport
    public let coveredBoundaries: [ModelWorkflowDurableBoundary]
    public let injectedFaults: [ModelWorkflowInjectedFault]
    public let faultExecutions: [ModelWorkflowFaultExecution]
    public let transitionCoverage: ModelWorkflowCoverageEvidence
    public let invariantViolations: [String]
    public let unexplainedManagedBytes: Int64
    public let securityProbes: [ModelWorkflowSecurityProbeResult]
    public let catalogRequests: [ModelCatalogRequestEvidence]
    public let exportedDiagnostics: ModelDiagnosticsPrivacyEvidence
    public let reportSHA256: String
}

public struct ModelWorkflowFaultCampaign: Sendable {
    private let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    public func run(operationCount: Int) throws -> ModelWorkflowFaultCampaignReport {
        precondition(operationCount > 0)

        var generator = SeededGenerator(seed: seed)
        var state = WorkflowState()
        var violations: [String] = []
        var executions: [ModelWorkflowFaultExecution] = []
        var transitionHitCounts: [String: Int] = [:]
        var invariantEvaluationCounts: [String: Int] =
            Dictionary(
                uniqueKeysWithValues: Self.declaredInvariants.map {
                    ($0, 0)
                }
            )

        for operationIndex in 0..<operationCount {
            let snapshot = state
            let operation = Int(generator.next() % 6)
            let artifactID = "artifact-\(generator.next() % 17)"
            apply(operation: operation, artifactID: artifactID, to: &state)
            if state != snapshot {
                transitionHitCounts[
                    Self.declaredTransitions[operation],
                    default: 0
                ] += 1
            }

            let matrixSize = ModelWorkflowDurableBoundary.allCases.count
                * ModelWorkflowInjectedFault.allCases.count
            let matrixIndex = operationIndex % matrixSize
            let boundary = ModelWorkflowDurableBoundary.allCases[
                matrixIndex / ModelWorkflowInjectedFault.allCases.count
            ]
            let fault = ModelWorkflowInjectedFault.allCases[
                matrixIndex % ModelWorkflowInjectedFault.allCases.count
            ]
            recover(
                from: fault,
                at: boundary,
                snapshot: snapshot,
                state: &state
            )
            let operationViolations = state.invariantViolations()
            for invariant in Self.declaredInvariants {
                invariantEvaluationCounts[invariant, default: 0] += 1
            }
            violations.append(contentsOf: operationViolations)
            executions.append(
                ModelWorkflowFaultExecution(
                    boundary: boundary,
                    fault: fault,
                    modelInvariantHeld: operationViolations.isEmpty
                )
            )
        }

        let durableQueueSoak = try ModelDurableQueueSoak().run(
            operationCount: operationCount
        )
        if durableQueueSoak.lostAttemptCount != 0 {
            violations.append("durable_queue_lost_attempt")
        }
        if durableQueueSoak.partialCleanupMismatchCount != 0 {
            violations.append("retained_partial_cleanup_mismatch")
        }
        let probes = ModelWorkflowSecurityProbeRunner().run()
        let requests = ModelCatalogPrivacyProbe.catalogRequests()
        let exportedDiagnostics =
            ModelCatalogPrivacyProbe.diagnosticsEvidence()
        let coveredBoundaries = ModelWorkflowDurableBoundary.allCases.filter {
            boundary in executions.contains { $0.boundary == boundary }
        }
        let injectedFaults = ModelWorkflowInjectedFault.allCases.filter {
            fault in executions.contains { $0.fault == fault }
        }
        let payload = ReportPayload(
            schemaVersion: 1,
            seed: seed,
            operationCount: operationCount,
            durableQueueSoak: durableQueueSoak,
            faultExecutions: executions,
            transitionCoverage: ModelWorkflowCoverageEvidence(
                declaredTransitions: Self.declaredTransitions,
                transitionHitCounts: transitionHitCounts,
                declaredInvariants: Self.declaredInvariants,
                invariantEvaluationCounts:
                    invariantEvaluationCounts
            ),
            invariantViolations: violations,
            unexplainedManagedBytes:
                state.unexplainedManagedBytes
                    + durableQueueSoak.unexplainedManagedBytes,
            securityProbes: probes,
            catalogRequests: requests,
            exportedDiagnostics: exportedDiagnostics
        )
        let encoded = try Self.encoder.encode(payload)

        return ModelWorkflowFaultCampaignReport(
            schemaVersion: payload.schemaVersion,
            seed: seed,
            operationCount: operationCount,
            durableQueueSoak: durableQueueSoak,
            coveredBoundaries: coveredBoundaries,
            injectedFaults: injectedFaults,
            faultExecutions: executions,
            transitionCoverage: payload.transitionCoverage,
            invariantViolations: violations,
            unexplainedManagedBytes: payload.unexplainedManagedBytes,
            securityProbes: probes,
            catalogRequests: requests,
            exportedDiagnostics: exportedDiagnostics,
            reportSHA256: SHA256.hash(data: encoded).hexString
        )
    }

    public static func encodedEvidence(
        _ report: ModelWorkflowFaultCampaignReport
    ) throws -> Data {
        try encoder.encode(report)
    }

    private func apply(
        operation: Int,
        artifactID: String,
        to state: inout WorkflowState
    ) {
        switch operation {
        case 0:
            state.queueAttempts.insert(artifactID)
        case 1:
            state.queueAttempts.remove(artifactID)
            state.receipts.insert(artifactID)
            state.ownedBytes[artifactID] = max(
                state.ownedBytes[artifactID, default: 0],
                1_024
            )
        case 2:
            guard state.receipts.contains(artifactID),
                  !state.revokedArtifacts.contains(artifactID)
            else {
                return
            }
            state.activeArtifactID = artifactID
        case 3:
            state.queueAttempts.remove(artifactID)
            if state.activeArtifactID == artifactID {
                state.activeArtifactID = nil
            }
            state.receipts.remove(artifactID)
            state.ownedBytes.removeValue(forKey: artifactID)
        case 4:
            state.revokedArtifacts.insert(artifactID)
            state.queueAttempts.remove(artifactID)
            if state.activeArtifactID == artifactID {
                state.activeArtifactID = nil
            }
        default:
            state.revokedArtifacts.remove(artifactID)
        }
    }

    private static let declaredTransitions = [
        "authorize_install",
        "persist_installation_receipt",
        "activate_installed_artifact",
        "delete_artifact",
        "accept_revocation",
        "accept_restoration",
    ]

    private static let declaredInvariants = [
        "active_identity_has_receipt",
        "revoked_identity_is_not_active",
        "owned_byte_accounting_is_nonnegative",
        "managed_bytes_are_attributable",
    ]

    private func recover(
        from fault: ModelWorkflowInjectedFault,
        at boundary: ModelWorkflowDurableBoundary,
        snapshot: WorkflowState,
        state: inout WorkflowState
    ) {
        switch fault {
        case .missingFiles:
            for artifactID in state.receipts {
                state.ownedBytes[artifactID] = max(
                    0,
                    state.ownedBytes[artifactID, default: 0]
                )
            }
        case .extraFiles:
            let owner = state.receipts.sorted().first ?? "retained-download-data"
            state.ownedBytes[owner, default: 0] += 37
        case .revocation:
            if let active = state.activeArtifactID {
                state.revokedArtifacts.insert(active)
                state.activeArtifactID = nil
            }
        case .catalogReplacement, .incompatibility:
            state.activeArtifactID = state.activeArtifactID.flatMap {
                state.receipts.contains($0) && !state.revokedArtifacts.contains($0)
                    ? $0
                    : nil
            }
        case .processTermination, .diskFull, .permissionFailure,
             .checksumMismatch, .truncation, .renameFailure:
            state = snapshot
        }

        if boundary == .restorationIntegrityAcknowledged,
           let active = state.activeArtifactID,
           state.revokedArtifacts.contains(active)
        {
            state.activeArtifactID = nil
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

private struct ReportPayload: Codable {
    let schemaVersion: Int
    let seed: UInt64
    let operationCount: Int
    let durableQueueSoak: ModelDurableQueueSoakReport
    let faultExecutions: [ModelWorkflowFaultExecution]
    let transitionCoverage: ModelWorkflowCoverageEvidence
    let invariantViolations: [String]
    let unexplainedManagedBytes: Int64
    let securityProbes: [ModelWorkflowSecurityProbeResult]
    let catalogRequests: [ModelCatalogRequestEvidence]
    let exportedDiagnostics: ModelDiagnosticsPrivacyEvidence
}

private struct WorkflowState: Equatable {
    var receipts: Set<String> = []
    var queueAttempts: Set<String> = []
    var ownedBytes: [String: Int64] = [:]
    var activeArtifactID: String?
    var revokedArtifacts: Set<String> = []

    var unexplainedManagedBytes: Int64 {
        ownedBytes
            .filter { !receipts.contains($0.key) && $0.key != "retained-download-data" }
            .values
            .reduce(0, +)
    }

    func invariantViolations() -> [String] {
        var result: [String] = []
        if let activeArtifactID {
            if !receipts.contains(activeArtifactID) {
                result.append("active_without_receipt")
            }
            if revokedArtifacts.contains(activeArtifactID) {
                result.append("revoked_active_identity")
            }
        }
        if ownedBytes.values.contains(where: { $0 < 0 }) {
            result.append("negative_owned_bytes")
        }
        if unexplainedManagedBytes != 0 {
            result.append("unexplained_managed_bytes")
        }
        return result
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
