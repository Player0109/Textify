import CryptoKit
import Foundation
import TextifyModels
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
        XCTAssertEqual(
            bundle.attachmentCount,
            fixture.declaration.attachments.count
        )
        XCTAssertEqual(bundle.approvalCount, 2)
        XCTAssertTrue(bundle.isReleaseApproved)
    }

    func testGenericAttachmentCannotSelfLabelEveryEvidenceCategory() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        let index = try XCTUnwrap(
            declaration.attachments.firstIndex {
                $0.categories == [.schemaTests]
            }
        )
        declaration.attachments[index].categories =
            ReleaseEvidenceCategory.allCases

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .invalidEvidenceRecord(
                    declaration.attachments[index].id
                )
            )
        }
    }

    func testCatalogIdentityMustMatchPublicationEvidence() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.catalogIdentity.catalogSignerID = "self-declared-signer"

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .catalogEvidenceMismatch
            )
        }
    }

    func testDeclaredComputeRoutesMustEqualAttachedManifestRoutes() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.declaredComputeRoutes = [.cpuOnly]

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .invalidReleaseIdentity
            )
        }
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

    func testOldestSupportedM1ClassificationIsBoundToRecordAndDeviceClass() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        declaration.performanceEvidence[0].isOldestSupportedM1Class = false
        declaration.performanceEvidence[1].isOldestSupportedM1Class = true

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

    func testOldestSupportedM1ClassRejectsPrefixSpoofs() throws {
        for spoofedClass in ["Apple M10", "Apple M1 simulator"] {
            let fixture = try EvidenceFixture()
            defer { fixture.remove() }
            try fixture.replacePerformanceDeviceClass(
                at: 0,
                with: spoofedClass
            )

            XCTAssertThrowsError(
                try ReleaseCandidateEvidenceValidator().validate(
                    fixture.declaration,
                    evidenceRoot: fixture.root,
                    specificationURL: fixture.specificationURL
                ),
                spoofedClass
            ) { error in
                XCTAssertEqual(
                    error as? ReleaseCandidateEvidenceError,
                    .insufficientOldestSupportedPerformanceEvidence
                )
            }
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
                .missingComputeRouteEvidence(.gpuViaMetal)
            )
        }
    }

    func testAttachmentHashAndContainedRegularPathAreRequired() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var declaration = fixture.declaration
        let subjectIndex = try XCTUnwrap(
            declaration.attachments.firstIndex { $0.id == "subject" }
        )
        declaration.attachments[subjectIndex].sha256 =
            String(repeating: "0", count: 64)

        XCTAssertThrowsError(
            try ReleaseCandidateEvidenceValidator().validate(
                declaration,
                evidenceRoot: fixture.root,
                specificationURL: fixture.specificationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? ReleaseCandidateEvidenceError,
                .attachmentHashMismatch("subject")
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
        let voiceOverIndex = try XCTUnwrap(
            declaration.attachments.firstIndex {
                $0.categories == [.voiceOver]
            }
        )
        declaration.attachments[voiceOverIndex].kind = .automated

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
                waiverAttachmentID: "subject"
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
        let fixtureRoot = root
        specificationURL = root.appendingPathComponent("SPEC.md")
        let specificationData = Data("# Frozen parent specification\n".utf8)
        try specificationData.write(to: specificationURL)
        let releaseCommit = String(repeating: "a", count: 40)
        var attachments: [ReleaseEvidenceAttachment] = []
        func addRaw(_ id: String, data: Data) throws {
            let relativePath = "\(id).bin"
            try data.write(
                to: fixtureRoot.appendingPathComponent(relativePath)
            )
            attachments.append(
                ReleaseEvidenceAttachment(
                    id: id,
                    relativePath: relativePath,
                    sha256: Self.hash(data),
                    kind: .automated,
                    categories: []
                )
            )
        }
        func addRecord(
            _ id: String,
            category: ReleaseEvidenceCategory,
            kind: ReleaseEvidenceAttachmentKind = .automated,
            recordedBy: String = "fixture-runner",
            subjects: [String] = ["subject"],
            attributes: [String: String] = [:],
            measurements: [String: [Double]] = [:]
        ) throws {
            let record = ReleaseEvidenceRecord(
                category: category,
                result: .passed,
                releaseCommitSHA: releaseCommit,
                recordedAt: "2026-07-25T00:00:00Z",
                recordedBy: recordedBy,
                notes: ["Structured unit-test evidence fixture."],
                subjectAttachmentIDs: subjects,
                attributes: attributes,
                measurements: measurements
            )
            let data = try JSONEncoder().encode(record)
            let relativePath = "\(id).json"
            try data.write(
                to: fixtureRoot.appendingPathComponent(relativePath)
            )
            attachments.append(
                ReleaseEvidenceAttachment(
                    id: id,
                    relativePath: relativePath,
                    sha256: Self.hash(data),
                    kind: kind,
                    categories: [category]
                )
            )
        }

        let subjectData = Data("retained evidence payload".utf8)
        let executableData = Data("signed app executable fixture".utf8)
        try addRaw("subject", data: subjectData)
        try addRaw("app-executable", data: executableData)
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TextifyModelsTests/Fixtures/Models/manifest_v3.json")
        let manifestData = try Data(contentsOf: manifestURL)
        try addRaw("catalog-manifest", data: manifestData)
        let manifest = try ModelManifest.decode(manifestData)
        let publication = try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "catalogRevision": manifest.generatedAt,
                "catalogSignerKeyID": "catalog-signer",
                "catalogContentSHA256": Self.hash(manifestData),
                "revocationRevision": "2026-07-25T00:00:00Z",
                "revocationSignerKeyID": "revocation-signer",
                "revocationContentSHA256": String(repeating: "b", count: 64),
                "buildIdentity": [
                    "bundleIdentifier": "com.textify.fixture",
                    "shortVersion": "1.1.0",
                    "bundleVersion": "1",
                    "executableSHA256": Self.hash(executableData),
                ],
                "establishesAuthorityBaseline": true,
                "artifactCount": manifest.presentationGraph?.artifacts.count ?? 0,
                "acceptedRevocationRecords": [],
                "acceptedRestorations": [],
                "sourceEndpoint": "https://example.com/models/",
                "checkedAt": 0,
            ],
            options: [.sortedKeys]
        )
        try addRaw("publication", data: publication)

        let specializedCategories: Set<ReleaseEvidenceCategory> = [
            .performance,
            .computeRoutes,
            .securityReview,
            .humanApprovals,
        ]
        for category in ReleaseEvidenceCategory.allCases
        where !specializedCategories.contains(category) {
            try addRecord(
                "record-\(category.rawValue)",
                category: category,
                kind: category.requiresManualEvidence ? .manual : .automated
            )
        }
        let warm = Array(repeating: 1.0, count: 30)
        let cold = Array(repeating: 2.0, count: 3)
        try addRecord(
            "performance-m1",
            category: .performance,
            attributes: [
                "deviceID": "m1-baseline",
                "deviceClass": "Apple M1",
                "macOSVersion": "14.0",
                "isRealDevice": "true",
                "isOldestSupportedM1Class": "true",
            ],
            measurements: ["warm": warm, "cold": cold]
        )
        try addRecord(
            "performance-later",
            category: .performance,
            attributes: [
                "deviceID": "later-device",
                "deviceClass": "Apple M4 Max",
                "macOSVersion": "26.0",
                "isRealDevice": "true",
                "isOldestSupportedM1Class": "false",
            ],
            measurements: ["warm": warm, "cold": cold]
        )
        try addRecord(
            "compute-gpu",
            category: .computeRoutes,
            attributes: [
                "route": ModelComputeRoute.gpuViaMetal.rawValue,
                "deviceID": "m1-baseline",
                "isRealDevice": "true",
            ]
        )
        for scope in ReleaseCriticalReviewScope.allCases {
            try addRecord(
                "review-\(scope.rawValue)",
                category: .securityReview,
                kind: .manual,
                recordedBy: "independent-reviewer",
                attributes: ["scope": scope.rawValue]
            )
        }
        try addRecord(
            "approval-one",
            category: .humanApprovals,
            kind: .manual,
            recordedBy: "release-approver-one",
            subjects: ["app-executable", "publication"],
            attributes: ["approvedAt": "2026-07-25T01:00:00Z"]
        )
        try addRecord(
            "approval-two",
            category: .humanApprovals,
            kind: .manual,
            recordedBy: "release-approver-two",
            subjects: ["app-executable", "publication"],
            attributes: ["approvedAt": "2026-07-25T02:00:00Z"]
        )
        declaration = ReleaseCandidateEvidenceDeclaration(
            schemaVersion: 1,
            parentIssueNumber: 1,
            parentSpecificationSHA256: Self.hash(specificationData),
            parentSpecificationUnchanged: true,
            primaryAuthor: "primary-author",
            releaseCommitSHA: releaseCommit,
            buildArtifacts: [
                ReleaseBuildArtifact(
                    name: "Textify",
                    sha256: Self.hash(executableData),
                    attachmentID: "app-executable"
                ),
            ],
            catalogIdentity: ReleaseCatalogIdentity(
                catalogRevision: manifest.generatedAt,
                catalogSignerID: "catalog-signer",
                revocationRevision: "2026-07-25T00:00:00Z",
                revocationSignerID: "revocation-signer",
                publicationEvidenceAttachmentID: "publication",
                catalogManifestAttachmentID: "catalog-manifest"
            ),
            attachments: attachments,
            performanceEvidence: [
                ReleasePerformanceEvidence(
                    deviceID: "m1-baseline",
                    deviceClass: "Apple M1",
                    macOSVersion: "14.0",
                    isRealDevice: true,
                    isOldestSupportedM1Class: true,
                    warmIterationCount: 30,
                    coldLaunchCount: 3,
                    attachmentID: "performance-m1"
                ),
                ReleasePerformanceEvidence(
                    deviceID: "later-device",
                    deviceClass: "Apple M4 Max",
                    macOSVersion: "26.0",
                    isRealDevice: true,
                    isOldestSupportedM1Class: false,
                    warmIterationCount: 30,
                    coldLaunchCount: 3,
                    attachmentID: "performance-later"
                ),
            ],
            declaredComputeRoutes: [.gpuViaMetal],
            computeRouteEvidence: [
                ReleaseComputeRouteEvidence(
                    route: .gpuViaMetal,
                    deviceID: "m1-baseline",
                    isRealDevice: true,
                    attachmentID: "compute-gpu"
                ),
            ],
            defects: [],
            independentReviews: ReleaseCriticalReviewScope.allCases.map {
                ReleaseIndependentReview(
                    scope: $0,
                    reviewer: "independent-reviewer",
                    attachmentID: "review-\($0.rawValue)"
                )
            },
            approvals: [
                ReleaseHumanApproval(
                    approver: "release-approver-one",
                    approvedAt: "2026-07-25T01:00:00Z",
                    attachmentID: "approval-one"
                ),
                ReleaseHumanApproval(
                    approver: "release-approver-two",
                    approvedAt: "2026-07-25T02:00:00Z",
                    attachmentID: "approval-two"
                ),
            ]
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func replacePerformanceDeviceClass(
        at performanceIndex: Int,
        with deviceClass: String
    ) throws {
        let attachmentID =
            declaration.performanceEvidence[performanceIndex].attachmentID
        let attachmentIndex = try XCTUnwrap(
            declaration.attachments.firstIndex { $0.id == attachmentID }
        )
        let attachment = declaration.attachments[attachmentIndex]
        let attachmentURL = root.appendingPathComponent(
            attachment.relativePath
        )
        var record = try JSONDecoder().decode(
            ReleaseEvidenceRecord.self,
            from: Data(contentsOf: attachmentURL)
        )
        record.attributes["deviceClass"] = deviceClass
        let data = try JSONEncoder().encode(record)
        try data.write(to: attachmentURL)

        declaration.performanceEvidence[performanceIndex].deviceClass =
            deviceClass
        declaration.attachments[attachmentIndex].sha256 = Self.hash(data)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
