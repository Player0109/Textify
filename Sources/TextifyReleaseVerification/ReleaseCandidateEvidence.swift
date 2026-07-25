import Foundation
import TextifyModels

public enum ReleaseEvidenceCategory: String, CaseIterable, Codable, Sendable {
    case schemaTests = "schema_tests"
    case propertyTests = "property_tests"
    case transitionTests = "transition_tests"
    case malformedInputTests = "malformed_input_tests"
    case migrationTests = "migration_tests"
    case faultInjection = "fault_injection"
    case hierarchy
    case selection
    case comparison
    case actions
    case scopes
    case query
    case pinnedReveal = "pinned_reveal"
    case inspector
    case downloads
    case onboarding
    case trustStates = "trust_states"
    case revocation
    case deletion
    case voiceOver = "voice_over"
    case fullKeyboardAccess = "full_keyboard_access"
    case textScaling = "text_scaling"
    case reduceMotion = "reduce_motion"
    case increaseContrast = "increase_contrast"
    case reduceTransparency = "reduce_transparency"
    case performance
    case computeRoutes = "compute_routes"
    case securityReview = "security_review"
    case publicationReport = "publication_report"
    case soakLog = "soak_log"
    case diagnosticsReview = "diagnostics_review"
    case packagingValidation = "packaging_validation"
    case rollbackRehearsal = "rollback_rehearsal"
    case humanApprovals = "human_approvals"

    var requiresManualEvidence: Bool {
        switch self {
        case .voiceOver, .fullKeyboardAccess, .textScaling, .reduceMotion,
             .increaseContrast, .reduceTransparency, .securityReview,
             .humanApprovals:
            true
        default:
            false
        }
    }
}

public enum ReleaseEvidenceAttachmentKind: String, Codable, Sendable {
    case automated
    case manual
}

public struct ReleaseEvidenceAttachment: Codable, Equatable, Sendable {
    public var id: String
    public var relativePath: String
    public var sha256: String
    public var kind: ReleaseEvidenceAttachmentKind
    public var categories: [ReleaseEvidenceCategory]

    public init(
        id: String,
        relativePath: String,
        sha256: String,
        kind: ReleaseEvidenceAttachmentKind,
        categories: [ReleaseEvidenceCategory]
    ) {
        self.id = id
        self.relativePath = relativePath
        self.sha256 = sha256
        self.kind = kind
        self.categories = categories
    }
}

public enum ReleaseEvidenceResult: String, Codable, Sendable {
    case passed
    case failed
}

public struct ReleaseEvidenceRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var category: ReleaseEvidenceCategory
    public var result: ReleaseEvidenceResult
    public var releaseCommitSHA: String
    public var recordedAt: String
    public var recordedBy: String
    public var notes: [String]
    public var subjectAttachmentIDs: [String]
    public var attributes: [String: String]
    public var measurements: [String: [Double]]

    public init(
        schemaVersion: Int = 1,
        category: ReleaseEvidenceCategory,
        result: ReleaseEvidenceResult,
        releaseCommitSHA: String,
        recordedAt: String,
        recordedBy: String,
        notes: [String],
        subjectAttachmentIDs: [String],
        attributes: [String: String] = [:],
        measurements: [String: [Double]] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.category = category
        self.result = result
        self.releaseCommitSHA = releaseCommitSHA
        self.recordedAt = recordedAt
        self.recordedBy = recordedBy
        self.notes = notes
        self.subjectAttachmentIDs = subjectAttachmentIDs
        self.attributes = attributes
        self.measurements = measurements
    }
}

public struct ReleaseBuildArtifact: Codable, Equatable, Sendable {
    public var name: String
    public var sha256: String
    public var attachmentID: String

    public init(name: String, sha256: String, attachmentID: String) {
        self.name = name
        self.sha256 = sha256
        self.attachmentID = attachmentID
    }
}

public struct ReleaseCatalogIdentity: Codable, Equatable, Sendable {
    public var catalogRevision: String
    public var catalogSignerID: String
    public var revocationRevision: String
    public var revocationSignerID: String
    public var publicationEvidenceAttachmentID: String
    public var catalogManifestAttachmentID: String

    public init(
        catalogRevision: String,
        catalogSignerID: String,
        revocationRevision: String,
        revocationSignerID: String,
        publicationEvidenceAttachmentID: String,
        catalogManifestAttachmentID: String
    ) {
        self.catalogRevision = catalogRevision
        self.catalogSignerID = catalogSignerID
        self.revocationRevision = revocationRevision
        self.revocationSignerID = revocationSignerID
        self.publicationEvidenceAttachmentID =
            publicationEvidenceAttachmentID
        self.catalogManifestAttachmentID = catalogManifestAttachmentID
    }
}

public struct ReleasePerformanceEvidence: Codable, Equatable, Sendable {
    public var deviceID: String
    public var deviceClass: String
    public var macOSVersion: String
    public var isRealDevice: Bool
    public var isOldestSupportedM1Class: Bool
    public var warmIterationCount: Int
    public var coldLaunchCount: Int
    public var attachmentID: String

    public init(
        deviceID: String,
        deviceClass: String,
        macOSVersion: String,
        isRealDevice: Bool,
        isOldestSupportedM1Class: Bool,
        warmIterationCount: Int,
        coldLaunchCount: Int,
        attachmentID: String
    ) {
        self.deviceID = deviceID
        self.deviceClass = deviceClass
        self.macOSVersion = macOSVersion
        self.isRealDevice = isRealDevice
        self.isOldestSupportedM1Class = isOldestSupportedM1Class
        self.warmIterationCount = warmIterationCount
        self.coldLaunchCount = coldLaunchCount
        self.attachmentID = attachmentID
    }
}

public struct ReleaseComputeRouteEvidence: Codable, Equatable, Sendable {
    public var route: ModelComputeRoute
    public var deviceID: String
    public var isRealDevice: Bool
    public var attachmentID: String

    public init(
        route: ModelComputeRoute,
        deviceID: String,
        isRealDevice: Bool,
        attachmentID: String
    ) {
        self.route = route
        self.deviceID = deviceID
        self.isRealDevice = isRealDevice
        self.attachmentID = attachmentID
    }
}

public enum ReleaseDefectSeverity: String, Codable, Sendable {
    case critical
    case high
    case medium
    case low
}

public enum ReleaseDefectDomain: String, Codable, Sendable {
    case trust
    case migration
    case activation
    case deletion
    case queueDurability = "queue_durability"
    case recovery
    case privacy
    case primaryAccessibility = "primary_accessibility"
    case other

    var blocksMediumDefect: Bool {
        self != .other
    }
}

public struct ReleaseEvidenceDefect: Codable, Equatable, Sendable {
    public var id: String
    public var severity: ReleaseDefectSeverity
    public var domain: ReleaseDefectDomain
    public var safeWorkaround: String?
    public var waiverAttachmentID: String?

    public init(
        id: String,
        severity: ReleaseDefectSeverity,
        domain: ReleaseDefectDomain,
        safeWorkaround: String?,
        waiverAttachmentID: String?
    ) {
        self.id = id
        self.severity = severity
        self.domain = domain
        self.safeWorkaround = safeWorkaround
        self.waiverAttachmentID = waiverAttachmentID
    }
}

public enum ReleaseCriticalReviewScope: String, CaseIterable, Codable, Sendable {
    case trust
    case migration
    case revocation
    case destructiveFilesystem = "destructive_filesystem"
}

public struct ReleaseIndependentReview: Codable, Equatable, Sendable {
    public var scope: ReleaseCriticalReviewScope
    public var reviewer: String
    public var attachmentID: String

    public init(
        scope: ReleaseCriticalReviewScope,
        reviewer: String,
        attachmentID: String
    ) {
        self.scope = scope
        self.reviewer = reviewer
        self.attachmentID = attachmentID
    }
}

public struct ReleaseHumanApproval: Codable, Equatable, Sendable {
    public var approver: String
    public var approvedAt: String
    public var attachmentID: String

    public init(
        approver: String,
        approvedAt: String,
        attachmentID: String
    ) {
        self.approver = approver
        self.approvedAt = approvedAt
        self.attachmentID = attachmentID
    }
}

public struct ReleaseCandidateEvidenceDeclaration:
    Codable,
    Equatable,
    Sendable
{
    public var schemaVersion: Int
    public var parentIssueNumber: Int
    public var parentSpecificationSHA256: String
    public var parentSpecificationUnchanged: Bool
    public var primaryAuthor: String
    public var releaseCommitSHA: String
    public var buildArtifacts: [ReleaseBuildArtifact]
    public var catalogIdentity: ReleaseCatalogIdentity
    public var attachments: [ReleaseEvidenceAttachment]
    public var performanceEvidence: [ReleasePerformanceEvidence]
    public var declaredComputeRoutes: [ModelComputeRoute]
    public var computeRouteEvidence: [ReleaseComputeRouteEvidence]
    public var defects: [ReleaseEvidenceDefect]
    public var independentReviews: [ReleaseIndependentReview]
    public var approvals: [ReleaseHumanApproval]

    public init(
        schemaVersion: Int,
        parentIssueNumber: Int,
        parentSpecificationSHA256: String,
        parentSpecificationUnchanged: Bool,
        primaryAuthor: String,
        releaseCommitSHA: String,
        buildArtifacts: [ReleaseBuildArtifact],
        catalogIdentity: ReleaseCatalogIdentity,
        attachments: [ReleaseEvidenceAttachment],
        performanceEvidence: [ReleasePerformanceEvidence],
        declaredComputeRoutes: [ModelComputeRoute],
        computeRouteEvidence: [ReleaseComputeRouteEvidence],
        defects: [ReleaseEvidenceDefect],
        independentReviews: [ReleaseIndependentReview],
        approvals: [ReleaseHumanApproval]
    ) {
        self.schemaVersion = schemaVersion
        self.parentIssueNumber = parentIssueNumber
        self.parentSpecificationSHA256 = parentSpecificationSHA256
        self.parentSpecificationUnchanged = parentSpecificationUnchanged
        self.primaryAuthor = primaryAuthor
        self.releaseCommitSHA = releaseCommitSHA
        self.buildArtifacts = buildArtifacts
        self.catalogIdentity = catalogIdentity
        self.attachments = attachments
        self.performanceEvidence = performanceEvidence
        self.declaredComputeRoutes = declaredComputeRoutes
        self.computeRouteEvidence = computeRouteEvidence
        self.defects = defects
        self.independentReviews = independentReviews
        self.approvals = approvals
    }
}

public struct ReleaseCandidateEvidenceBundle: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let releaseCommitSHA: String
    public let declarationSHA256: String
    public let attachmentSHA256ByID: [String: String]
    public let attachmentCount: Int
    public let approvalCount: Int
    public let isReleaseApproved: Bool
}
