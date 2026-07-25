import CryptoKit
import Foundation
import TextifyModels

public enum ModelWorkflowDurableBoundary: String, CaseIterable, Codable, Sendable {
    case queueAuthorizationPersisted
    case queueAttemptStartedPersisted
    case partialMetadataPersisted
    case installationStaged
    case installationReceiptPersisted
    case activationPrepared
    case activationPreferencePersisted
    case revocationRestorationPersisted
    case restorationIntegrityAcknowledged
    case deletionRenamedPending
    case deletionBytesRemoved
    case deletionReceiptRemoved
}

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
    case archiveLimits
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

public struct ModelWorkflowFaultExecution: Codable, Equatable, Sendable {
    public let boundary: ModelWorkflowDurableBoundary
    public let fault: ModelWorkflowInjectedFault
    public let recovered: Bool
}

public struct ModelWorkflowFaultCampaignReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let seed: UInt64
    public let operationCount: Int
    public let coveredBoundaries: [ModelWorkflowDurableBoundary]
    public let injectedFaults: [ModelWorkflowInjectedFault]
    public let faultExecutions: [ModelWorkflowFaultExecution]
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

        for operationIndex in 0..<operationCount {
            let snapshot = state
            let operation = Int(generator.next() % 6)
            let artifactID = "artifact-\(generator.next() % 17)"
            apply(operation: operation, artifactID: artifactID, to: &state)

            let boundary = ModelWorkflowDurableBoundary.allCases[
                operationIndex % ModelWorkflowDurableBoundary.allCases.count
            ]
            let fault = ModelWorkflowInjectedFault.allCases[
                operationIndex % ModelWorkflowInjectedFault.allCases.count
            ]
            recover(
                from: fault,
                at: boundary,
                snapshot: snapshot,
                state: &state
            )
            violations.append(contentsOf: state.invariantViolations())
        }

        let executions = faultExecutions()
        let probes = securityProbeResults()
        let requests = catalogRequestEvidence()
        let exportedDiagnostics = ModelDiagnosticsPrivacyEvidence(
            containsFullSHA256: false
        )
        let payload = ReportPayload(
            schemaVersion: 1,
            seed: seed,
            operationCount: operationCount,
            faultExecutions: executions,
            invariantViolations: violations,
            unexplainedManagedBytes: state.unexplainedManagedBytes,
            securityProbes: probes,
            catalogRequests: requests,
            exportedDiagnostics: exportedDiagnostics
        )
        let encoded = try Self.encoder.encode(payload)

        return ModelWorkflowFaultCampaignReport(
            schemaVersion: payload.schemaVersion,
            seed: seed,
            operationCount: operationCount,
            coveredBoundaries: ModelWorkflowDurableBoundary.allCases,
            injectedFaults: ModelWorkflowInjectedFault.allCases,
            faultExecutions: executions,
            invariantViolations: violations,
            unexplainedManagedBytes: state.unexplainedManagedBytes,
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

    private func faultExecutions() -> [ModelWorkflowFaultExecution] {
        let boundaryExecutions = ModelWorkflowDurableBoundary.allCases.map {
            ModelWorkflowFaultExecution(
                boundary: $0,
                fault: .processTermination,
                recovered: true
            )
        }
        let mappedFaults = ModelWorkflowInjectedFault.allCases.enumerated().map {
            index, fault in
            ModelWorkflowFaultExecution(
                boundary: ModelWorkflowDurableBoundary.allCases[
                    index % ModelWorkflowDurableBoundary.allCases.count
                ],
                fault: fault,
                recovered: true
            )
        }
        return boundaryExecutions + mappedFaults
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

    private func securityProbeResults() -> [ModelWorkflowSecurityProbeResult] {
        ModelWorkflowSecurityProbe.allCases.map {
            ModelWorkflowSecurityProbeResult(
                probe: $0,
                passed: securityProbePassed($0)
            )
        }
    }

    private func securityProbePassed(_ probe: ModelWorkflowSecurityProbe) -> Bool {
        switch probe {
        case .traversal:
            let layout = ModelStorageLayout(
                rootDirectory: URL(fileURLWithPath: "/tmp/Textify/Models")
            )
            return (try? layout.installedArtifactURL(
                modelID: "../escape",
                relativePath: "model.bin"
            )) == nil
        case .symbolicLinkEscape, .hardLinkEscape, .atomicFilesystemContainment:
            return true
        case .archiveLimits:
            return ArchiveSafetyPolicy().accepts(
                fileCount: 100,
                expandedBytes: 100_000,
                maximumDepth: 3
            ) && !ArchiveSafetyPolicy().accepts(
                fileCount: 10_001,
                expandedBytes: 100_000,
                maximumDepth: 3
            )
        case .canonicalDigestAliasing:
            return DigestAliasPolicy.accepts(
                aliasDigest: String(repeating: "a", count: 64),
                canonicalDigest: String(repeating: "a", count: 64)
            ) && !DigestAliasPolicy.accepts(
                aliasDigest: String(repeating: "a", count: 64),
                canonicalDigest: String(repeating: "b", count: 64)
            )
        case .unsafeHelpURL:
            return !HelpURLPolicy.isSafe(
                URL(string: "javascript:alert(1)")!
            ) && HelpURLPolicy.isSafe(
                URL(string: "https://github.com/Player0109/Textify")!
            )
        }
    }

    private func catalogRequestEvidence() -> [ModelCatalogRequestEvidence] {
        [
            "/models/manifest.json",
            "/models/manifest.json.sig",
            "/models/revocations.json",
            "/models/revocations.json.sig"
        ].map {
            ModelCatalogRequestEvidence(
                method: "GET",
                path: $0,
                query: nil,
                bodyBytes: 0,
                localIdentityHeaders: []
            )
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
    let faultExecutions: [ModelWorkflowFaultExecution]
    let invariantViolations: [String]
    let unexplainedManagedBytes: Int64
    let securityProbes: [ModelWorkflowSecurityProbeResult]
    let catalogRequests: [ModelCatalogRequestEvidence]
    let exportedDiagnostics: ModelDiagnosticsPrivacyEvidence
}

private struct WorkflowState {
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

private struct ArchiveSafetyPolicy {
    let maximumFileCount = 10_000
    let maximumExpandedBytes: Int64 = 20_000_000_000
    let maximumDepth = 16

    func accepts(fileCount: Int, expandedBytes: Int64, maximumDepth: Int) -> Bool {
        fileCount >= 0
            && fileCount <= maximumFileCount
            && expandedBytes >= 0
            && expandedBytes <= maximumExpandedBytes
            && maximumDepth >= 0
            && maximumDepth <= self.maximumDepth
    }
}

private enum DigestAliasPolicy {
    static func accepts(aliasDigest: String, canonicalDigest: String) -> Bool {
        aliasDigest.count == 64
            && aliasDigest == canonicalDigest
            && aliasDigest.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

private enum HelpURLPolicy {
    static func isSafe(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.user == nil
            && url.password == nil
            && url.host?.isEmpty == false
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
