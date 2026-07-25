import Foundation

public struct ModelCatalogPublicationEvidence:
    Codable,
    Equatable,
    Sendable
{
    public let schemaVersion: Int
    public let catalogRevision: String
    public let catalogSignerKeyID: String
    public let catalogContentSHA256: String
    public let revocationRevision: String
    public let revocationSignerKeyID: String
    public let revocationContentSHA256: String
    public let buildIdentity: ModelCatalogBuildIdentity
    public let establishesAuthorityBaseline: Bool
    public let artifactCount: Int
    public let acceptedRevocationRecords: [ModelRevocationRecord]
    public let acceptedRestorations: [ModelRestorationRecord]
    public let sourceEndpoint: String?
    public let checkedAt: Date

    public init(
        catalogRevision: String,
        catalogSignerKeyID: String,
        catalogContentSHA256: String,
        revocationRevision: String,
        revocationSignerKeyID: String,
        revocationContentSHA256: String,
        buildIdentity: ModelCatalogBuildIdentity,
        establishesAuthorityBaseline: Bool,
        artifactCount: Int,
        acceptedRevocationRecords: [ModelRevocationRecord] = [],
        acceptedRestorations: [ModelRestorationRecord] = [],
        sourceEndpoint: String?,
        checkedAt: Date
    ) {
        schemaVersion = 1
        self.catalogRevision = catalogRevision
        self.catalogSignerKeyID = catalogSignerKeyID
        self.catalogContentSHA256 = catalogContentSHA256
        self.revocationRevision = revocationRevision
        self.revocationSignerKeyID = revocationSignerKeyID
        self.revocationContentSHA256 = revocationContentSHA256
        self.buildIdentity = buildIdentity
        self.establishesAuthorityBaseline = establishesAuthorityBaseline
        self.artifactCount = artifactCount
        self.acceptedRevocationRecords = acceptedRevocationRecords
        self.acceptedRestorations = acceptedRestorations
        self.sourceEndpoint = sourceEndpoint
        self.checkedAt = checkedAt
    }
}

public enum ModelCatalogPublicationError: Error, Equatable, Sendable {
    case unsupportedEvidenceVersion(Int)
    case requiresManifestV3(Int)
    case unexpectedCatalogSigner(String)
    case unexpectedRevocationSigner(String)
    case invalidSourceEndpoint(String)
    case catalogRollback(candidate: String, published: String)
    case catalogCorrectionRequiresHigherRevision(String)
    case revocationRollback(candidate: String, published: String)
    case revocationCorrectionRequiresHigherRevision(String)
    case conflictingRevocationRecord(String)
    case conflictingRestoration(String)
    case unknownRestorationRecord(
        restorationID: String,
        revocationRecordID: String
    )
    case restorationTargetMismatch(
        restorationID: String,
        revocationRecordID: String
    )
}

public enum ModelCatalogPublicationPolicy {
    public static func validate(
        catalog: TrustedCatalogSnapshot,
        revocations: TrustedModelRevocationSnapshot,
        allowedCatalogSignerKeyIDs: Set<String>,
        allowedRevocationSignerKeyIDs: Set<String>,
        buildIdentity: ModelCatalogBuildIdentity,
        previousEvidence: ModelCatalogPublicationEvidence? = nil,
        sourceEndpoint: String? = nil,
        checkedAt: Date = Date()
    ) throws -> ModelCatalogPublicationEvidence {
        if let previousEvidence,
           previousEvidence.schemaVersion != 1 {
            throw ModelCatalogPublicationError
                .unsupportedEvidenceVersion(
                    previousEvidence.schemaVersion
                )
        }
        guard catalog.manifest.manifestVersion
                == ModelManifestSchemaVersion.v3.rawValue
        else {
            throw ModelCatalogPublicationError.requiresManifestV3(
                catalog.manifest.manifestVersion
            )
        }
        let catalogSignature = try ManifestSignature.decode(
            catalog.signatureData
        )
        let revocationSignature = try ModelRevocationSignature.decode(
            revocations.signatureData
        )
        guard allowedCatalogSignerKeyIDs.contains(
            catalogSignature.keyId
        ) else {
            throw ModelCatalogPublicationError.unexpectedCatalogSigner(
                catalogSignature.keyId
            )
        }
        guard allowedRevocationSignerKeyIDs.contains(
            revocationSignature.keyId
        )
        else {
            throw ModelCatalogPublicationError.unexpectedRevocationSigner(
                revocationSignature.keyId
            )
        }
        if let sourceEndpoint {
            guard let url = URL(string: sourceEndpoint),
                  url.scheme == "https",
                  url.host != nil,
                  url.user == nil,
                  url.password == nil,
                  url.query == nil,
                  url.fragment == nil
            else {
                throw ModelCatalogPublicationError.invalidSourceEndpoint(
                    sourceEndpoint
                )
            }
        }

        let acceptedRevocationRecords = try merging(
            previousEvidence?.acceptedRevocationRecords ?? [],
            with: revocations.envelope.records,
            id: \.recordID,
            conflict: {
                .conflictingRevocationRecord($0)
            }
        )
        try validateRestorations(
            revocations.envelope.restorations,
            against:
                previousEvidence?.acceptedRevocationRecords ?? []
        )
        let acceptedRestorations = try merging(
            previousEvidence?.acceptedRestorations ?? [],
            with: revocations.envelope.restorations,
            id: \.restorationID,
            conflict: {
                .conflictingRestoration($0)
            }
        )
        let evidence = ModelCatalogPublicationEvidence(
            catalogRevision: catalog.revision,
            catalogSignerKeyID: catalogSignature.keyId,
            catalogContentSHA256: catalogSignature.contentSHA256,
            revocationRevision: revocations.revision,
            revocationSignerKeyID: revocationSignature.keyId,
            revocationContentSHA256:
                revocationSignature.contentSHA256,
            buildIdentity: buildIdentity,
            establishesAuthorityBaseline: previousEvidence == nil,
            artifactCount: catalog.manifest.models.count,
            acceptedRevocationRecords: acceptedRevocationRecords,
            acceptedRestorations: acceptedRestorations,
            sourceEndpoint: sourceEndpoint,
            checkedAt: checkedAt
        )
        if let previousEvidence {
            try validateRevision(
                candidate: evidence.catalogRevision,
                candidateDigest: evidence.catalogContentSHA256,
                published: previousEvidence.catalogRevision,
                publishedDigest: previousEvidence.catalogContentSHA256,
                rollbackError: {
                    .catalogRollback(
                        candidate: $0,
                        published: $1
                    )
                },
                correctionError: {
                    .catalogCorrectionRequiresHigherRevision($0)
                }
            )
            try validateRevision(
                candidate: evidence.revocationRevision,
                candidateDigest: evidence.revocationContentSHA256,
                published: previousEvidence.revocationRevision,
                publishedDigest:
                    previousEvidence.revocationContentSHA256,
                rollbackError: {
                    .revocationRollback(
                        candidate: $0,
                        published: $1
                    )
                },
                correctionError: {
                    .revocationCorrectionRequiresHigherRevision($0)
                }
            )
        }
        return evidence
    }

    private static func validateRevision(
        candidate: String,
        candidateDigest: String,
        published: String,
        publishedDigest: String,
        rollbackError: (String, String) -> ModelCatalogPublicationError,
        correctionError: (String) -> ModelCatalogPublicationError
    ) throws {
        guard let candidateDate = ISO8601DateFormatter().date(
            from: candidate
        ),
        let publishedDate = ISO8601DateFormatter().date(from: published)
        else {
            throw rollbackError(candidate, published)
        }
        guard candidateDate >= publishedDate else {
            throw rollbackError(candidate, published)
        }
        if candidateDate == publishedDate,
           candidateDigest != publishedDigest {
            throw correctionError(candidate)
        }
    }

    private static func merging<Value: Equatable>(
        _ accepted: [Value],
        with candidates: [Value],
        id: KeyPath<Value, String>,
        conflict: (String) -> ModelCatalogPublicationError
    ) throws -> [Value] {
        var result: [Value] = []
        var indexByID: [String: Int] = [:]
        for value in accepted + candidates {
            let valueID = value[keyPath: id]
            if let index = indexByID[valueID] {
                guard result[index] == value else {
                    throw conflict(valueID)
                }
            } else {
                indexByID[valueID] = result.count
                result.append(value)
            }
        }
        return result
    }

    private static func validateRestorations(
        _ restorations: [ModelRestorationRecord],
        against priorRecords: [ModelRevocationRecord]
    ) throws {
        var priorRecordsByID: [String: ModelRevocationRecord] = [:]
        for record in priorRecords {
            if let accepted = priorRecordsByID[record.recordID] {
                guard accepted == record else {
                    throw ModelCatalogPublicationError
                        .conflictingRevocationRecord(record.recordID)
                }
            } else {
                priorRecordsByID[record.recordID] = record
            }
        }
        for restoration in restorations {
            guard let record = priorRecordsByID[
                restoration.revocationRecordID
            ] else {
                throw ModelCatalogPublicationError
                    .unknownRestorationRecord(
                        restorationID: restoration.restorationID,
                        revocationRecordID:
                            restoration.revocationRecordID
                    )
            }
            let exactTargetMatches =
                restoration.exactArtifactID == nil
                || restoration.exactArtifactID == record.exactArtifactID
            let digestTargetMatches =
                restoration.contentDigest == nil
                || restoration.contentDigest == record.contentDigest
            guard exactTargetMatches, digestTargetMatches else {
                throw ModelCatalogPublicationError
                    .restorationTargetMismatch(
                        restorationID: restoration.restorationID,
                        revocationRecordID:
                            restoration.revocationRecordID
                    )
            }
        }
    }
}
