import CryptoKit
import Foundation
import XCTest
@testable import TextifyReleaseVerification

final class ReleaseCandidateEvidenceTests: XCTestCase {
    func testCompleteEvidenceBundleValidatesAndBindsAttachments() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }

        let bundle = try ReleaseCandidateEvidenceValidator().validate(
            fixture.declaration,
            evidenceRoot: fixture.root,
            specificationURL: fixture.specificationURL
        )

        XCTAssertEqual(bundle.schemaVersion, 1)
        XCTAssertEqual(bundle.releaseCommitSHA, fixture.declaration.releaseCommitSHA)
        XCTAssertEqual(bundle.attachmentCount, 1)
        XCTAssertEqual(bundle.approvalCount, 2)
        XCTAssertTrue(bundle.isReleaseApproved)
    }

    func testTwoDistinctHumanApprovalsAreRequired() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.approvals = [declaration.approvals[0]]

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .insufficientHumanApprovals
            )
        }
    }

    func testPerformanceRequiresThirtyWarmIterationsAndThreeColdLaunchesOnRealM1() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.performanceEvidence[0].warmIterationCount = 29

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .insufficientOldestSupportedPerformanceEvidence
            )
        }
    }

    func testSensitiveMediumDefectBlocksRelease() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.defects = [
            ReleaseEvidenceDefect(
                id: "DEF-1",
                severity: .medium,
                domain: .queueDurability,
                safeWorkaround: nil,
                waiverAttachmentID: nil
            ),
        ]

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .blockingDefect("DEF-1")
            )
        }
    }

    func testEveryDeclaredComputeRouteRequiresRealDeviceEvidence() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.computeRouteEvidence = []

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .missingComputeRouteEvidence("metal_gpu")
            )
        }
    }

    func testAttachmentHashAndContainedRegularPathAreRequired() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.attachments[0].sha256 = String(repeating: "0", count: 64)

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .attachmentHashMismatch("complete-evidence")
            )
        }
    }

    func testTrustCriticalScopesRequireIndependentReviewer() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.independentReviews = []

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .missingIndependentReview(.trust)
            )
        }
    }

    func testAccessibilityCategoryCannotBeSatisfiedByAutomatedAttachment() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.attachments[0].kind = .automated

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .manualEvidenceRequired(.voiceOver)
            )
        }
    }

    func testOtherMediumDefectRequiresWaiverAndSafeWorkaround() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.defects = [
            ReleaseEvidenceDefect(
                id: "DEF-2",
                severity: .medium,
                domain: .other,
                safeWorkaround: nil,
                waiverAttachmentID: "complete-evidence"
            ),
        ]

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .invalidDefectWaiver("DEF-2")
            )
        }
    }

    func testExpectedReleaseCommitMustMatchDeclaration() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                fixture.declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL,
                expectedReleaseCommitSHA: String(repeating: "b", count: 40)
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .releaseCommitMismatch
            )
        }
    }
}

private final class EvidenceFixture {
    let root: URL
    let specificationURL: URL
    var declaration: ReleaseCandidateEvidenceDeclaration

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TextifyEvidence-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let evidenceURL = root.appendingPathComponent("complete-evidence.json")
        let evidenceData = Data(#"{"result":"passed"}"#.utf8)
        try evidenceData.write(to: evidenceURL)
        specificationURL = root.appendingPathComponent("SPEC.md")
        let specificationData = Data("# Frozen parent specification\n".utf8)
        try specificationData.write(to: specificationURL)

        let attachment = ReleaseEvidenceAttachment(
            id: "complete-evidence",
            relativePath: "complete-evidence.json",
            sha256: Self.hash(evidenceData),
            kind: .manual,
            categories: ReleaseEvidenceCategory.allCases
        )
        declaration = ReleaseCandidateEvidenceDeclaration(
            schemaVersion: 1,
            parentIssueNumber: 1,
            parentSpecificationSHA256: Self.hash(specificationData),
            parentSpecificationUnchanged: true,
            primaryAuthor: "primary-author",
            releaseCommitSHA: String(repeating: "a", count: 40),
            buildArtifacts: [
                ReleaseBuildArtifact(
                    name: "Textify-1.1.0-arm64.dmg",
                    sha256: attachment.sha256,
                    attachmentID: attachment.id
                ),
            ],
            catalogIdentity: ReleaseCatalogIdentity(
                catalogRevision: "2026-07-25T00:00:00Z",
                catalogSignerID: "textify-model-manifest-2026",
                revocationRevision: "2026-07-25T00:00:00Z",
                revocationSignerID: "textify-model-manifest-2026"
            ),
            attachments: [attachment],
            performanceEvidence: [
                ReleasePerformanceEvidence(
                    deviceID: "m1-baseline",
                    deviceClass: "Apple M1",
                    macOSVersion: "14.0",
                    isRealDevice: true,
                    isOldestSupportedM1Class: true,
                    warmIterationCount: 30,
                    coldLaunchCount: 3,
                    attachmentID: "complete-evidence"
                ),
                ReleasePerformanceEvidence(
                    deviceID: "later-device",
                    deviceClass: "Apple M4 Max",
                    macOSVersion: "26.0",
                    isRealDevice: true,
                    isOldestSupportedM1Class: false,
                    warmIterationCount: 30,
                    coldLaunchCount: 3,
                    attachmentID: "complete-evidence"
                ),
            ],
            declaredComputeRoutes: ["metal_gpu"],
            computeRouteEvidence: [
                ReleaseComputeRouteEvidence(
                    route: "metal_gpu",
                    deviceID: "m1-baseline",
                    isRealDevice: true,
                    attachmentID: "complete-evidence"
                ),
            ],
            defects: [],
            independentReviews: ReleaseCriticalReviewScope.allCases.map {
                ReleaseIndependentReview(
                    scope: $0,
                    reviewer: "independent-reviewer",
                    attachmentID: "complete-evidence"
                )
            },
            approvals: [
                ReleaseHumanApproval(
                    approver: "release-approver-one",
                    approvedAt: "2026-07-25T01:00:00Z",
                    attachmentID: "complete-evidence"
                ),
                ReleaseHumanApproval(
                    approver: "release-approver-two",
                    approvedAt: "2026-07-25T02:00:00Z",
                    attachmentID: "complete-evidence"
                ),
            ]
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
