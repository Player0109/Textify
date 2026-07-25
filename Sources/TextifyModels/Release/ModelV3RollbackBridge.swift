import CryptoKit
import Foundation

public struct ModelV3RollbackRehearsalEvidence:
    Codable,
    Equatable,
    Sendable
{
    public let schemaVersion: Int
    public let catalogRevision: String
    public let catalogSignerKeyID: String
    public let revocationRevision: String
    public let revocationSignerKeyID: String
    public let bridgeBuildIdentity: ModelCatalogBuildIdentity
    public let receiptArtifactIDs: [String]
    public let ownedStorageModelIDs: [String]
    public let ownedFileSHA256ByPath: [String: String]
    public let ownedByteCount: UInt64
    public let queueAttemptIDs: [String]
    public let placementsByArtifactID: [
        String: ModelArtifactPlacement
    ]
    public let activeTranscriptionArtifactID: String?
    public let activeVoiceCleaningArtifactID: String?
    public let blockedActiveArtifactIDs: [String]
    public let stateFileSHA256ByPath: [String: String]
    public let rehearsedAt: Date

    init(
        bridgeBuildIdentity: ModelCatalogBuildIdentity,
        catalogRevision: String,
        catalogSignerKeyID: String,
        revocationRevision: String,
        revocationSignerKeyID: String,
        receiptArtifactIDs: [String],
        ownedStorageModelIDs: [String],
        ownedFileSHA256ByPath: [String: String],
        ownedByteCount: UInt64,
        queueAttemptIDs: [String],
        placementsByArtifactID: [String: ModelArtifactPlacement],
        activeTranscriptionArtifactID: String?,
        activeVoiceCleaningArtifactID: String?,
        blockedActiveArtifactIDs: [String],
        stateFileSHA256ByPath: [String: String],
        rehearsedAt: Date
    ) {
        schemaVersion = 1
        self.bridgeBuildIdentity = bridgeBuildIdentity
        self.catalogRevision = catalogRevision
        self.catalogSignerKeyID = catalogSignerKeyID
        self.revocationRevision = revocationRevision
        self.revocationSignerKeyID = revocationSignerKeyID
        self.receiptArtifactIDs = receiptArtifactIDs
        self.ownedStorageModelIDs = ownedStorageModelIDs
        self.ownedFileSHA256ByPath = ownedFileSHA256ByPath
        self.ownedByteCount = ownedByteCount
        self.queueAttemptIDs = queueAttemptIDs
        self.placementsByArtifactID = placementsByArtifactID
        self.activeTranscriptionArtifactID =
            activeTranscriptionArtifactID
        self.activeVoiceCleaningArtifactID =
            activeVoiceCleaningArtifactID
        self.blockedActiveArtifactIDs = blockedActiveArtifactIDs
        self.stateFileSHA256ByPath = stateFileSHA256ByPath
        self.rehearsedAt = rehearsedAt
    }
}

public enum ModelV3RollbackBridgeError: Error, Equatable, Sendable {
    case requiresManifestV3(Int)
    case missingRevocationEvidence
    case receiptOwnershipChanged
    case missingPersistedState(String)
    case missingTrustedCatalog
    case missingOwnedFile(String)
    case persistedStateChanged(String)
    case unexpectedBundleIdentifier(String)
    case designatedBuildMismatch
    case publicationEvidenceMismatch
}

public enum ModelV3RollbackBridge {
    public static func rehearsePersistedWithdrawal(
        bridgeAppBundleURL: URL,
        publicationEvidence: ModelCatalogPublicationEvidence,
        stateLayout: ModelV3RollbackStateLayout,
        rehearsedAt: Date = Date()
    ) throws -> ModelV3RollbackRehearsalEvidence {
        try rehearsePersistedWithdrawal(
            bridgeAppBundleURL: bridgeAppBundleURL,
            publicationEvidence: publicationEvidence,
            stateLayout: stateLayout,
            trustedKeys: ProductionModelCatalogTrust.trustedKeys,
            rehearsedAt: rehearsedAt
        )
    }

    static func rehearsePersistedWithdrawal(
        bridgeAppBundleURL: URL,
        publicationEvidence: ModelCatalogPublicationEvidence,
        stateLayout: ModelV3RollbackStateLayout,
        trustedKeys: [TrustedModelManifestKey],
        rehearsedAt: Date = Date()
    ) throws -> ModelV3RollbackRehearsalEvidence {
        let bridgeBuildIdentity = try ModelCatalogBuildIdentity.loadVerified(
            fromAppBundle: bridgeAppBundleURL
        )
        guard bridgeBuildIdentity.bundleIdentifier
                == ProductionModelCatalogTrust.bundleIdentifier
        else {
            throw ModelV3RollbackBridgeError.unexpectedBundleIdentifier(
                bridgeBuildIdentity.bundleIdentifier
            )
        }
        guard bridgeBuildIdentity == publicationEvidence.buildIdentity else {
            throw ModelV3RollbackBridgeError.designatedBuildMismatch
        }
        let manifestVerifier = ManifestVerifier(
            trustedKeys: trustedKeys
        )
        let catalogState = try TrustedCatalogStore(
            fileURL: stateLayout.catalogStateFileURL,
            verifier: manifestVerifier
        ).load()
        guard let trustedCatalog = catalogState.presentedSnapshot else {
            throw ModelV3RollbackBridgeError.missingTrustedCatalog
        }
        let revocationState = try TrustedModelRevocationStore(
            fileURL: stateLayout.revocationStateFileURL,
            verifier: ModelRevocationVerifier(
                trustedKeys: trustedKeys
            ),
            catalogVerifier: manifestVerifier
        ).load()
        guard trustedCatalog.manifest.manifestVersion
                == ModelManifestSchemaVersion.v3.rawValue
        else {
            throw ModelV3RollbackBridgeError.requiresManifestV3(
                trustedCatalog.manifest.manifestVersion
            )
        }
        guard let latestRevocation = revocationState.snapshots.last else {
            throw ModelV3RollbackBridgeError.missingRevocationEvidence
        }
        let stateURLs = [
            stateLayout.settingsFileURL,
            stateLayout.catalogStateFileURL,
            stateLayout.revocationStateFileURL,
            stateLayout.modelStorageLayout.installedStoreURL,
            stateLayout.modelStorageLayout.installQueueURL,
        ]
        var stateDataByPath: [String: Data] = [:]
        for url in stateURLs {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ModelV3RollbackBridgeError.missingPersistedState(
                    url.path
                )
            }
            stateDataByPath[url.path] = try Data(contentsOf: url)
        }
        let installedModels = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: stateDataByPath[
                stateLayout.modelStorageLayout.installedStoreURL.path
            ]!
        )
        let installQueue = try JSONDecoder().decode(
            ModelInstallQueue.self,
            from: stateDataByPath[
                stateLayout.modelStorageLayout.installQueueURL.path
            ]!
        )
        let activeIdentities = try JSONDecoder().decode(
            PersistedActiveIdentities.self,
            from: stateDataByPath[stateLayout.settingsFileURL.path]!
        )

        let placementSnapshot = ModelArtifactPlacementResolver().reconcile(
            records: installedModels.records,
            trustedManifest: trustedCatalog.manifest
        )
        guard placementSnapshot.records.count
                == installedModels.records.count
        else {
            throw ModelV3RollbackBridgeError.receiptOwnershipChanged
        }
        var placements: [String: ModelArtifactPlacement] = [:]
        for record in placementSnapshot.records {
            guard let placement = placementSnapshot.placement(
                forArtifactID: record.model.id
            ) else {
                throw ModelV3RollbackBridgeError.receiptOwnershipChanged
            }
            placements[record.model.id] = placement
        }

        let overlay = revocationState.overlay
        var ownedFileDigests: [String: String] = [:]
        var ownedByteCount: UInt64 = 0
        for record in installedModels.records {
            for path in record.localFilesByManifestFilename.values {
                guard FileManager.default.fileExists(atPath: path) else {
                    throw ModelV3RollbackBridgeError.missingOwnedFile(path)
                }
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                ownedFileDigests[path] = Self.sha256Hex(data)
                ownedByteCount += UInt64(data.count)
            }
        }
        let activeIDs = [
            activeIdentities.activeModelID,
            activeIdentities.activeVoiceCleaningModelID,
        ].compactMap { $0 }
        let blockedActiveIDs = activeIDs.filter {
            overlay.isRevoked(
                artifactID: $0,
                trustedManifest: trustedCatalog.manifest
            )
        }
        let catalogSignature = try ManifestSignature.decode(
            trustedCatalog.signatureData
        )
        let revocationSignature = try ModelRevocationSignature.decode(
            latestRevocation.signatureData
        )
        guard publicationEvidence.catalogRevision
                == trustedCatalog.revision,
              publicationEvidence.catalogSignerKeyID
                == catalogSignature.keyId,
              publicationEvidence.catalogContentSHA256
                == catalogSignature.contentSHA256,
              publicationEvidence.revocationRevision
                == latestRevocation.revision,
              publicationEvidence.revocationSignerKeyID
                == revocationSignature.keyId,
              publicationEvidence.revocationContentSHA256
                == revocationSignature.contentSHA256
        else {
            throw ModelV3RollbackBridgeError
                .publicationEvidenceMismatch
        }
        for (path, before) in stateDataByPath {
            guard try Data(contentsOf: URL(fileURLWithPath: path)) == before
            else {
                throw ModelV3RollbackBridgeError.persistedStateChanged(path)
            }
        }
        for (path, digest) in ownedFileDigests {
            guard Self.sha256Hex(
                try Data(contentsOf: URL(fileURLWithPath: path))
            ) == digest else {
                throw ModelV3RollbackBridgeError.persistedStateChanged(path)
            }
        }
        return ModelV3RollbackRehearsalEvidence(
            bridgeBuildIdentity: bridgeBuildIdentity,
            catalogRevision: trustedCatalog.revision,
            catalogSignerKeyID: catalogSignature.keyId,
            revocationRevision: latestRevocation.revision,
            revocationSignerKeyID: revocationSignature.keyId,
            receiptArtifactIDs:
                installedModels.records.map(\.model.id).sorted(),
            ownedStorageModelIDs:
                installedModels.records.map(\.storageModelID).sorted(),
            ownedFileSHA256ByPath: ownedFileDigests,
            ownedByteCount: ownedByteCount,
            queueAttemptIDs: installQueue.attempts.map(\.id),
            placementsByArtifactID: placements,
            activeTranscriptionArtifactID:
                activeIdentities.activeModelID,
            activeVoiceCleaningArtifactID:
                activeIdentities.activeVoiceCleaningModelID,
            blockedActiveArtifactIDs: blockedActiveIDs.sorted(),
            stateFileSHA256ByPath: stateDataByPath.mapValues(
                Self.sha256Hex
            ),
            rehearsedAt: rehearsedAt
        )
    }

    private struct PersistedActiveIdentities: Decodable {
        let activeModelID: String?
        let activeVoiceCleaningModelID: String?
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
