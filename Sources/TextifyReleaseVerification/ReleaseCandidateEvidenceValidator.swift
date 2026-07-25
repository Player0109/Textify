import CryptoKit
import Darwin
import Foundation

public enum ReleaseCandidateEvidenceError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case parentSpecificationChanged
    case invalidReleaseIdentity
    case releaseCommitMismatch
    case duplicateAttachmentID(String)
    case unsafeAttachmentPath(String)
    case attachmentNotFound(String)
    case attachmentHashMismatch(String)
    case missingEvidenceCategory(ReleaseEvidenceCategory)
    case manualEvidenceRequired(ReleaseEvidenceCategory)
    case insufficientOldestSupportedPerformanceEvidence
    case missingLaterDevicePerformanceEvidence
    case missingComputeRouteEvidence(String)
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
        let attachmentDigests = try validateAttachments(
            declaration.attachments,
            evidenceRoot: evidenceRoot
        )
        try validateBuildArtifacts(
            declaration.buildArtifacts,
            attachmentDigests: attachmentDigests
        )
        try validateCategoryCoverage(declaration.attachments)
        try validatePerformance(
            declaration.performanceEvidence,
            attachmentIDs: Set(attachmentDigests.keys)
        )
        try validateComputeRoutes(
            declaration,
            attachmentIDs: Set(attachmentDigests.keys)
        )
        try validateDefects(
            declaration.defects,
            attachmentIDs: Set(attachmentDigests.keys)
        )
        try validateIndependentReviews(
            declaration,
            attachmentIDs: Set(attachmentDigests.keys)
        )
        try validateApprovals(
            declaration.approvals,
            attachmentIDs: Set(attachmentDigests.keys)
        )

        let declarationData = try Self.encoder.encode(declaration)
        return ReleaseCandidateEvidenceBundle(
            schemaVersion: 1,
            releaseCommitSHA: declaration.releaseCommitSHA,
            declarationSHA256: Self.sha256(declarationData),
            attachmentSHA256ByID: attachmentDigests,
            attachmentCount: attachmentDigests.count,
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
    ) throws -> [String: String] {
        var result: [String: String] = [:]
        for attachment in attachments {
            guard result[attachment.id] == nil else {
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
            guard Self.isContainedRegularFile(url, in: evidenceRoot),
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
            result[attachment.id] = digest
        }
        return result
    }

    private func validateCategoryCoverage(
        _ attachments: [ReleaseEvidenceAttachment]
    ) throws {
        for category in ReleaseEvidenceCategory.allCases {
            let matching = attachments.filter {
                $0.categories.contains(category)
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
        attachmentIDs: Set<String>
    ) throws {
        let valid: (ReleasePerformanceEvidence) -> Bool = {
            $0.isRealDevice
                && !$0.deviceID.isEmpty
                && !$0.deviceClass.isEmpty
                && !$0.macOSVersion.isEmpty
                && $0.warmIterationCount >= 30
                && $0.coldLaunchCount >= 3
                && attachmentIDs.contains($0.attachmentID)
        }
        guard evidence.contains(where: {
            $0.isOldestSupportedM1Class && valid($0)
        }) else {
            throw ReleaseCandidateEvidenceError
                .insufficientOldestSupportedPerformanceEvidence
        }
        guard evidence.contains(where: {
            !$0.isOldestSupportedM1Class && valid($0)
        }) else {
            throw ReleaseCandidateEvidenceError
                .missingLaterDevicePerformanceEvidence
        }
    }

    private func validateComputeRoutes(
        _ declaration: ReleaseCandidateEvidenceDeclaration,
        attachmentIDs: Set<String>
    ) throws {
        guard !declaration.declaredComputeRoutes.isEmpty else {
            throw ReleaseCandidateEvidenceError.invalidReleaseIdentity
        }
        let performanceDeviceIDs = Set(
            declaration.performanceEvidence
                .filter(\.isRealDevice)
                .map(\.deviceID)
        )
        for route in Set(declaration.declaredComputeRoutes) {
            guard !route.isEmpty,
                  declaration.computeRouteEvidence.contains(where: {
                      $0.route == route
                          && $0.isRealDevice
                          && performanceDeviceIDs.contains($0.deviceID)
                          && attachmentIDs.contains($0.attachmentID)
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
        attachmentIDs: Set<String>
    ) throws {
        for scope in ReleaseCriticalReviewScope.allCases {
            guard declaration.independentReviews.contains(where: {
                $0.scope == scope
                    && !$0.reviewer.isEmpty
                    && $0.reviewer != declaration.primaryAuthor
                    && attachmentIDs.contains($0.attachmentID)
            }) else {
                throw ReleaseCandidateEvidenceError.missingIndependentReview(
                    scope
                )
            }
        }
    }

    private func validateApprovals(
        _ approvals: [ReleaseHumanApproval],
        attachmentIDs: Set<String>
    ) throws {
        let validApprovers: Set<String> = Set(approvals.compactMap {
            approval -> String? in
            guard !approval.approver.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            Self.isISO8601(approval.approvedAt),
            attachmentIDs.contains(approval.attachmentID)
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

    private static func isContainedRegularFile(
        _ url: URL,
        in root: URL
    ) -> Bool {
        let standardizedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let standardizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = standardizedRoot.path.hasSuffix("/")
            ? standardizedRoot.path
            : standardizedRoot.path + "/"
        guard standardizedURL.path.hasPrefix(rootPath) else {
            return false
        }
        var information = stat()
        guard lstat(url.path, &information) == 0 else {
            return false
        }
        return information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            && information.st_nlink == 1
    }

    private static func isISO8601(_ value: String) -> Bool {
        ISO8601DateFormatter().date(from: value) != nil
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
