import CryptoKit
import Foundation
import TextifyModels

public enum ReleaseCandidateEvidenceError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case parentSpecificationChanged
    case invalidReleaseIdentity
    case releaseCommitMismatch
    case duplicateAttachmentID(String)
    case unsafeAttachmentPath(String)
    case attachmentNotFound(String)
    case attachmentHashMismatch(String)
    case invalidEvidenceRecord(String)
    case missingEvidenceCategory(ReleaseEvidenceCategory)
    case manualEvidenceRequired(ReleaseEvidenceCategory)
    case catalogEvidenceMismatch
    case insufficientOldestSupportedPerformanceEvidence
    case missingLaterDevicePerformanceEvidence
    case missingComputeRouteEvidence(ModelComputeRoute)
    case blockingDefect(String)
    case invalidDefectWaiver(String)
    case missingIndependentReview(ReleaseCriticalReviewScope)
    case insufficientHumanApprovals
}

public struct ReleaseCandidateEvidenceValidator: Sendable {
    public init() {}

    public func validate(
        _ declaration: ReleaseCandidateEvidenceDeclaration,
        evidenceRoot: URL,
        specificationURL: URL,
        expectedReleaseCommitSHA: String? = nil
    ) throws -> ReleaseCandidateEvidenceBundle {
        guard declaration.schemaVersion == 1 else {
            throw ReleaseCandidateEvidenceError.unsupportedSchemaVersion(
                declaration.schemaVersion
            )
        }
        try validateParentSpecification(
            declaration,
            specificationURL: specificationURL
        )
        try validateReleaseIdentity(declaration)
        if let expectedReleaseCommitSHA,
           declaration.releaseCommitSHA != expectedReleaseCommitSHA
        {
            throw ReleaseCandidateEvidenceError.releaseCommitMismatch
        }
        let attachments = try validateAttachments(
            declaration.attachments,
            evidenceRoot: evidenceRoot
        )
        try validateBuildArtifacts(
            declaration.buildArtifacts,
            attachmentDigests: attachments.digests
        )
        let records = try validateEvidenceRecords(
            declaration,
            attachmentData: attachments.data
        )
        try validateCategoryCoverage(
            declaration.attachments,
            records: records
        )
        let manifestRoutes = try validateCatalogIdentity(
            declaration,
            attachmentData: attachments.data
        )
        let supportedPerformanceDeviceIDs = try validatePerformance(
            declaration.performanceEvidence,
            records: records
        )
        try validateComputeRoutes(
            declaration,
            manifestRoutes: manifestRoutes,
            supportedPerformanceDeviceIDs: supportedPerformanceDeviceIDs,
            records: records
        )
        try validateDefects(
            declaration.defects,
            attachmentIDs: Set(attachments.digests.keys)
        )
        try validateIndependentReviews(
            declaration,
            records: records
        )
        try validateApprovals(
            declaration.approvals,
            records: records
        )

        let declarationData = try Self.encoder.encode(declaration)
        return ReleaseCandidateEvidenceBundle(
            schemaVersion: 1,
            releaseCommitSHA: declaration.releaseCommitSHA,
            declarationSHA256: Self.sha256(declarationData),
            attachmentSHA256ByID: attachments.digests,
            attachmentCount: attachments.digests.count,
            approvalCount: Set(declaration.approvals.map(\.approver)).count,
            isReleaseApproved: true
        )
    }

    private func validateParentSpecification(
        _ declaration: ReleaseCandidateEvidenceDeclaration,
        specificationURL: URL
    ) throws {
        guard declaration.parentIssueNumber == 1,
              declaration.parentSpecificationUnchanged,
              Self.isSHA256(declaration.parentSpecificationSHA256),
              let specificationData = try? Data(contentsOf: specificationURL),
              Self.sha256(specificationData)
                == declaration.parentSpecificationSHA256
        else {
            throw ReleaseCandidateEvidenceError.parentSpecificationChanged
        }
    }

    private func validateReleaseIdentity(
        _ declaration: ReleaseCandidateEvidenceDeclaration
    ) throws {
        let identity = declaration.catalogIdentity
        guard Self.isLowercaseHex(
            declaration.releaseCommitSHA,
            count: 40
        ),
        !declaration.primaryAuthor.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        !declaration.buildArtifacts.isEmpty,
        declaration.buildArtifacts.allSatisfy({
            !$0.name.isEmpty && Self.isSHA256($0.sha256)
        }),
        Self.isISO8601(identity.catalogRevision),
        Self.isISO8601(identity.revocationRevision),
        !identity.catalogSignerID.isEmpty,
        !identity.revocationSignerID.isEmpty
        else {
            throw ReleaseCandidateEvidenceError.invalidReleaseIdentity
        }
    }

    private func validateAttachments(
        _ attachments: [ReleaseEvidenceAttachment],
        evidenceRoot: URL
    ) throws -> (digests: [String: String], data: [String: Data]) {
        var digests: [String: String] = [:]
        var dataByID: [String: Data] = [:]
        for attachment in attachments {
            guard digests[attachment.id] == nil else {
                throw ReleaseCandidateEvidenceError.duplicateAttachmentID(
                    attachment.id
                )
            }
            guard !attachment.id.isEmpty,
                  Self.isSafeRelativePath(attachment.relativePath),
                  Self.isSHA256(attachment.sha256)
            else {
                throw ReleaseCandidateEvidenceError.unsafeAttachmentPath(
                    attachment.id
                )
            }
            let url = evidenceRoot.appendingPathComponent(
                attachment.relativePath,
                isDirectory: false
            )
            guard ReleaseEvidenceFilePolicy.accepts(url, in: evidenceRoot),
                  let data = try? Data(contentsOf: url)
            else {
                throw ReleaseCandidateEvidenceError.attachmentNotFound(
                    attachment.id
                )
            }
            let digest = Self.sha256(data)
            guard digest == attachment.sha256 else {
                throw ReleaseCandidateEvidenceError.attachmentHashMismatch(
                    attachment.id
                )
            }
            digests[attachment.id] = digest
            dataByID[attachment.id] = data
        }
        return (digests, dataByID)
    }

    private func validateEvidenceRecords(
        _ declaration: ReleaseCandidateEvidenceDeclaration,
        attachmentData: [String: Data]
    ) throws -> [String: ReleaseEvidenceRecord] {
        var records: [String: ReleaseEvidenceRecord] = [:]
        let attachmentIDs = Set(attachmentData.keys)
        for attachment in declaration.attachments
        where !attachment.categories.isEmpty {
            guard attachment.categories.count == 1,
                  let data = attachmentData[attachment.id],
                  let record = try? JSONDecoder().decode(
                      ReleaseEvidenceRecord.self,
                      from: data
                  ),
                  record.schemaVersion == 1,
                  record.category == attachment.categories[0],
                  record.result == .passed,
                  record.releaseCommitSHA == declaration.releaseCommitSHA,
                  Self.isISO8601(record.recordedAt),
                  !record.recordedBy.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ).isEmpty,
                  record.notes.contains(where: {
                      !$0.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ).isEmpty
                  }),
                  !record.subjectAttachmentIDs.isEmpty,
                  record.subjectAttachmentIDs.allSatisfy({
                      $0 != attachment.id && attachmentIDs.contains($0)
                  })
            else {
                throw ReleaseCandidateEvidenceError.invalidEvidenceRecord(
                    attachment.id
                )
            }
            if record.category.requiresManualEvidence,
               attachment.kind != .manual
            {
                throw ReleaseCandidateEvidenceError.manualEvidenceRequired(
                    record.category
                )
            }
            records[attachment.id] = record
        }
        return records
    }

    private func validateCategoryCoverage(
        _ attachments: [ReleaseEvidenceAttachment],
        records: [String: ReleaseEvidenceRecord]
    ) throws {
        for category in ReleaseEvidenceCategory.allCases {
            let matching = attachments.filter {
                $0.categories == [category] && records[$0.id] != nil
            }
            guard !matching.isEmpty else {
                throw ReleaseCandidateEvidenceError.missingEvidenceCategory(
                    category
                )
            }
            if category.requiresManualEvidence,
               !matching.contains(where: { $0.kind == .manual })
            {
                throw ReleaseCandidateEvidenceError.manualEvidenceRequired(
                    category
                )
            }
        }
    }

    private func validateCatalogIdentity(
        _ declaration: ReleaseCandidateEvidenceDeclaration,
        attachmentData: [String: Data]
    ) throws -> Set<ModelComputeRoute> {
        let identity = declaration.catalogIdentity
        guard let publicationData =
                attachmentData[identity.publicationEvidenceAttachmentID],
              let manifestData =
                attachmentData[identity.catalogManifestAttachmentID],
              let publication = try? JSONDecoder().decode(
                  ModelCatalogPublicationEvidence.self,
                  from: publicationData
              ),
              let manifest = try? ModelManifest.decode(manifestData),
              manifest.manifestVersion == 3,
              let graph = manifest.presentationGraph,
              publication.catalogRevision == identity.catalogRevision,
              publication.catalogSignerKeyID == identity.catalogSignerID,
              publication.revocationRevision == identity.revocationRevision,
              publication.revocationSignerKeyID
                == identity.revocationSignerID,
              publication.catalogContentSHA256 == Self.sha256(manifestData),
              publication.artifactCount == graph.artifacts.count,
              declaration.buildArtifacts.contains(where: {
                  $0.sha256
                    == publication.buildIdentity.executableSHA256
              })
        else {
            throw ReleaseCandidateEvidenceError.catalogEvidenceMismatch
        }
        return Set(graph.artifacts.map(\.computeRoute))
    }

    private func validateBuildArtifacts(
        _ artifacts: [ReleaseBuildArtifact],
        attachmentDigests: [String: String]
    ) throws {
        guard artifacts.allSatisfy({
            attachmentDigests[$0.attachmentID] == $0.sha256
        }) else {
            throw ReleaseCandidateEvidenceError.invalidReleaseIdentity
        }
    }

    private func validatePerformance(
        _ evidence: [ReleasePerformanceEvidence],
        records: [String: ReleaseEvidenceRecord]
    ) throws -> Set<String> {
        let valid: (ReleasePerformanceEvidence) -> Bool = {
            guard $0.isRealDevice,
                  let record = records[$0.attachmentID],
                  record.category == .performance
            else {
                return false
            }
            return !$0.deviceID.isEmpty
                && !$0.deviceClass.isEmpty
                && !$0.macOSVersion.isEmpty
                && Self.isSupportedAppleSiliconDeviceClass($0.deviceClass)
                && Self.isSupportedMacOSVersion($0.macOSVersion)
                && $0.warmIterationCount >= 30
                && $0.coldLaunchCount >= 3
                && record.attributes["deviceID"] == $0.deviceID
                && record.attributes["deviceClass"] == $0.deviceClass
                && record.attributes["macOSVersion"] == $0.macOSVersion
                && record.attributes["isRealDevice"] == "true"
                && record.attributes["isOldestSupportedM1Class"]
                    == String($0.isOldestSupportedM1Class)
                && (
                    $0.isOldestSupportedM1Class
                        ? $0.deviceClass == "Apple M1"
                        : $0.deviceClass != "Apple M1"
                )
                && record.measurements["warm"]?.count
                    == $0.warmIterationCount
                && record.measurements["cold"]?.count
                    == $0.coldLaunchCount
        }
        let validEvidence = evidence.filter(valid)
        let oldestSupportedDeviceIDs = Set(
            validEvidence
                .filter(\.isOldestSupportedM1Class)
                .map(\.deviceID)
        )
        guard !oldestSupportedDeviceIDs.isEmpty else {
            throw ReleaseCandidateEvidenceError
                .insufficientOldestSupportedPerformanceEvidence
        }
        guard validEvidence.contains(where: {
            !$0.isOldestSupportedM1Class
                && !oldestSupportedDeviceIDs.contains($0.deviceID)
        }) else {
            throw ReleaseCandidateEvidenceError
                .missingLaterDevicePerformanceEvidence
        }
        return Set(validEvidence.map(\.deviceID))
    }

    private func validateComputeRoutes(
        _ declaration: ReleaseCandidateEvidenceDeclaration,
        manifestRoutes: Set<ModelComputeRoute>,
        supportedPerformanceDeviceIDs: Set<String>,
        records: [String: ReleaseEvidenceRecord]
    ) throws {
        guard !manifestRoutes.isEmpty,
              Set(declaration.declaredComputeRoutes) == manifestRoutes
        else {
            throw ReleaseCandidateEvidenceError.invalidReleaseIdentity
        }
        for route in manifestRoutes {
            guard declaration.computeRouteEvidence.contains(where: {
                      guard $0.route == route,
                            $0.isRealDevice,
                            supportedPerformanceDeviceIDs.contains($0.deviceID),
                            let record = records[$0.attachmentID]
                      else {
                          return false
                      }
                      return record.category == .computeRoutes
                          && record.attributes["route"] == route.rawValue
                          && record.attributes["deviceID"] == $0.deviceID
                          && record.attributes["isRealDevice"] == "true"
                  })
            else {
                throw ReleaseCandidateEvidenceError
                    .missingComputeRouteEvidence(route)
            }
        }
    }

    private func validateDefects(
        _ defects: [ReleaseEvidenceDefect],
        attachmentIDs: Set<String>
    ) throws {
        for defect in defects {
            switch defect.severity {
            case .critical, .high:
                throw ReleaseCandidateEvidenceError.blockingDefect(defect.id)
            case .medium where defect.domain.blocksMediumDefect:
                throw ReleaseCandidateEvidenceError.blockingDefect(defect.id)
            case .medium:
                guard let workaround = defect.safeWorkaround,
                      !workaround.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ).isEmpty,
                      let waiverAttachmentID = defect.waiverAttachmentID,
                      attachmentIDs.contains(waiverAttachmentID)
                else {
                    throw ReleaseCandidateEvidenceError.invalidDefectWaiver(
                        defect.id
                    )
                }
            case .low:
                break
            }
        }
    }

    private func validateIndependentReviews(
        _ declaration: ReleaseCandidateEvidenceDeclaration,
        records: [String: ReleaseEvidenceRecord]
    ) throws {
        for scope in ReleaseCriticalReviewScope.allCases {
            guard declaration.independentReviews.contains(where: {
                guard $0.scope == scope,
                      !$0.reviewer.isEmpty,
                      $0.reviewer != declaration.primaryAuthor,
                      let record = records[$0.attachmentID]
                else {
                    return false
                }
                return record.category == .securityReview
                    && record.recordedBy == $0.reviewer
                    && record.attributes["scope"] == scope.rawValue
            }) else {
                throw ReleaseCandidateEvidenceError.missingIndependentReview(
                    scope
                )
            }
        }
    }

    private func validateApprovals(
        _ approvals: [ReleaseHumanApproval],
        records: [String: ReleaseEvidenceRecord]
    ) throws {
        let validApprovers: Set<String> = Set(approvals.compactMap {
            approval -> String? in
            guard let record = records[approval.attachmentID],
            record.category == .humanApprovals,
            record.recordedBy == approval.approver,
            record.attributes["approvedAt"] == approval.approvedAt,
            !approval.approver.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            Self.isISO8601(approval.approvedAt),
            record.subjectAttachmentIDs.count >= 2
            else {
                return nil
            }
            return approval.approver
        })
        guard validApprovers.count >= 2 else {
            throw ReleaseCandidateEvidenceError.insufficientHumanApprovals
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\")
        else {
            return false
        }
        return path.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    private static func isISO8601(_ value: String) -> Bool {
        ISO8601DateFormatter().date(from: value) != nil
    }

    private static func isSupportedAppleSiliconDeviceClass(
        _ value: String
    ) -> Bool {
        let components = value.split(separator: " ")
        guard components.count == 2 || components.count == 3,
              components[0] == "Apple",
              components[1].first == "M",
              let generation = Int(components[1].dropFirst()),
              generation >= 1
        else {
            return false
        }
        return components.count == 2
            || ["Pro", "Max", "Ultra"].contains(String(components[2]))
    }

    private static func isSupportedMacOSVersion(_ value: String) -> Bool {
        let components = value.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard (1 ... 3).contains(components.count),
              components.allSatisfy({
                  !$0.isEmpty && $0.allSatisfy(\.isNumber)
              }),
              let majorVersion = Int(components[0])
        else {
            return false
        }
        return majorVersion >= 14
    }

    private static func isSHA256(_ value: String) -> Bool {
        isLowercaseHex(value, count: 64)
    }

    private static func isLowercaseHex(
        _ value: String,
        count: Int
    ) -> Bool {
        value.count == count
            && value.allSatisfy {
                $0.isNumber || ("a"..."f").contains(String($0))
            }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}
