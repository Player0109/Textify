import CryptoKit
import Foundation
@testable import TextifyModels
import XCTest

final class ModelCatalogPublicationTests: XCTestCase {
    private let buildIdentity = ModelCatalogBuildIdentity(
        bundleIdentifier: "io.github.Player0109.Textify",
        shortVersion: "1.1.0",
        bundleVersion: "1",
        executableSHA256: String(repeating: "a", count: 64)
    )

    func testPublicationEvidenceBindsBothSignersRevisionsAndBuild() throws {
        let catalog = try signedCatalogFixture()
        let revocations = try signedRevocations(
            generatedAt: "2026-07-25T08:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "security-1",
                    exactArtifactID: catalog.snapshot.manifest.models[0].id
                ),
            ]
        )
        let checkedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-25T09:00:00Z")
        )

        let evidence = try ModelCatalogPublicationPolicy.validate(
            catalog: catalog.snapshot,
            revocations: revocations.snapshot,
            allowedCatalogSignerKeyIDs: [catalog.keyID],
            allowedRevocationSignerKeyIDs: [revocations.keyID],
            buildIdentity: buildIdentity,
            sourceEndpoint: "https://staging.example.test/models",
            checkedAt: checkedAt
        )

        XCTAssertEqual(evidence.schemaVersion, 1)
        XCTAssertTrue(evidence.establishesAuthorityBaseline)
        XCTAssertEqual(evidence.catalogRevision, catalog.snapshot.revision)
        XCTAssertEqual(evidence.catalogSignerKeyID, catalog.keyID)
        XCTAssertEqual(
            evidence.revocationRevision,
            revocations.snapshot.revision
        )
        XCTAssertEqual(evidence.revocationSignerKeyID, revocations.keyID)
        XCTAssertEqual(
            evidence.buildIdentity,
            buildIdentity
        )
        XCTAssertEqual(evidence.artifactCount, 3)
        XCTAssertEqual(
            evidence.sourceEndpoint,
            "https://staging.example.test/models"
        )
        XCTAssertEqual(
            evidence.acceptedRevocationRecords.map(\.recordID),
            ["security-1"]
        )
    }

    func testPublicationEvidenceKeepsOmittedRevocationStickyAndRejectsMutation()
        throws
    {
        let catalog = try signedCatalogFixture()
        let firstRevocations = try signedRevocations(
            generatedAt: "2026-07-25T08:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "security-1",
                    exactArtifactID: catalog.snapshot.manifest.models[0].id
                ),
            ]
        )
        let firstEvidence = try ModelCatalogPublicationPolicy.validate(
            catalog: catalog.snapshot,
            revocations: firstRevocations.snapshot,
            allowedCatalogSignerKeyIDs: [catalog.keyID],
            allowedRevocationSignerKeyIDs: [firstRevocations.keyID],
            buildIdentity: buildIdentity
        )
        let omission = try signedRevocations(
            generatedAt: "2026-07-25T09:00:00Z",
            records: []
        )

        let retained = try ModelCatalogPublicationPolicy.validate(
            catalog: catalog.snapshot,
            revocations: omission.snapshot,
            allowedCatalogSignerKeyIDs: [catalog.keyID],
            allowedRevocationSignerKeyIDs: [omission.keyID],
            buildIdentity: buildIdentity,
            previousEvidence: firstEvidence
        )

        XCTAssertEqual(
            retained.acceptedRevocationRecords,
            firstEvidence.acceptedRevocationRecords
        )

        let mutation = try signedRevocations(
            generatedAt: "2026-07-25T10:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "security-1",
                    exactArtifactID: catalog.snapshot.manifest.models[1].id
                ),
            ]
        )
        XCTAssertThrowsError(
            try ModelCatalogPublicationPolicy.validate(
                catalog: catalog.snapshot,
                revocations: mutation.snapshot,
                allowedCatalogSignerKeyIDs: [catalog.keyID],
                allowedRevocationSignerKeyIDs: [mutation.keyID],
                buildIdentity: buildIdentity,
                previousEvidence: firstEvidence
            )
        ) { error in
            XCTAssertEqual(
                error as? ModelCatalogPublicationError,
                .conflictingRevocationRecord("security-1")
            )
        }
    }

    func testCatalogCorrectionAtSameRevisionIsRejected() throws {
        let catalog = try signedCatalogFixture()
        let revocations = try signedRevocations(
            generatedAt: "2026-07-25T08:00:00Z",
            records: []
        )
        let previous = ModelCatalogPublicationEvidence(
            catalogRevision: catalog.snapshot.revision,
            catalogSignerKeyID: catalog.keyID,
            catalogContentSHA256: String(repeating: "0", count: 64),
            revocationRevision: revocations.snapshot.revision,
            revocationSignerKeyID: revocations.keyID,
            revocationContentSHA256:
                try ModelRevocationSignature.decode(
                    revocations.snapshot.signatureData
                ).contentSHA256,
            buildIdentity: buildIdentity,
            establishesAuthorityBaseline: false,
            artifactCount: 3,
            sourceEndpoint: nil,
            checkedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertThrowsError(
            try ModelCatalogPublicationPolicy.validate(
                catalog: catalog.snapshot,
                revocations: revocations.snapshot,
                allowedCatalogSignerKeyIDs: [catalog.keyID],
                allowedRevocationSignerKeyIDs: [revocations.keyID],
                buildIdentity: buildIdentity,
                previousEvidence: previous,
                checkedAt: Date(timeIntervalSince1970: 1)
            )
        ) { error in
            XCTAssertEqual(
                error as? ModelCatalogPublicationError,
                .catalogCorrectionRequiresHigherRevision(
                    catalog.snapshot.revision
                )
            )
        }
    }

    func testPublicationRestorationMustRepeatAPriorAcceptedTarget() throws {
        let catalog = try signedCatalogFixture()
        let firstRevocations = try signedRevocations(
            generatedAt: "2026-07-25T08:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "security-1",
                    exactArtifactID: catalog.snapshot.manifest.models[0].id
                ),
            ]
        )
        let firstEvidence = try ModelCatalogPublicationPolicy.validate(
            catalog: catalog.snapshot,
            revocations: firstRevocations.snapshot,
            allowedCatalogSignerKeyIDs: [catalog.keyID],
            allowedRevocationSignerKeyIDs: [firstRevocations.keyID],
            buildIdentity: buildIdentity
        )
        let mismatched = try signedRevocations(
            generatedAt: "2026-07-25T09:00:00Z",
            records: [],
            restorations: [
                ModelRestorationRecord(
                    restorationID: "restoration-1",
                    revocationRecordID: "security-1",
                    exactArtifactID:
                        catalog.snapshot.manifest.models[1].id
                ),
            ]
        )

        XCTAssertThrowsError(
            try ModelCatalogPublicationPolicy.validate(
                catalog: catalog.snapshot,
                revocations: mismatched.snapshot,
                allowedCatalogSignerKeyIDs: [catalog.keyID],
                allowedRevocationSignerKeyIDs: [mismatched.keyID],
                buildIdentity: buildIdentity,
                previousEvidence: firstEvidence
            )
        ) { error in
            XCTAssertEqual(
                error as? ModelCatalogPublicationError,
                .restorationTargetMismatch(
                    restorationID: "restoration-1",
                    revocationRecordID: "security-1"
                )
            )
        }
    }

    func testRollbackBridgeRetainsOwnedStateAndBlocksRevokedActiveContent()
        throws
    {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyRollbackBridgeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let applicationSupportDirectory = temporaryDirectory
            .appendingPathComponent(
                "Application Support/Textify",
                isDirectory: true
            )
        let rollbackStateLayout = ModelV3RollbackStateLayout(
            applicationSupportDirectory: applicationSupportDirectory
        )
        let layout = ModelStorageLayout(
            rootDirectory: applicationSupportDirectory.appendingPathComponent(
                "Models",
                isDirectory: true
            )
        )
        try FileManager.default.createDirectory(
            at: layout.installedModelsDirectory,
            withIntermediateDirectories: true
        )
        let catalog = try signedCatalogFixture()
        let manifest = catalog.snapshot.manifest
        let activeModel = manifest.models[0]
        let ownedFileURL = try layout.installedFileURL(
            modelID: "owned-storage-id",
            filename: activeModel.files[0].filename
        )
        try FileManager.default.createDirectory(
            at: ownedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let ownedBytes = Data("retained model bytes".utf8)
        try ownedBytes.write(to: ownedFileURL)
        let revocations = try signedRevocations(
            generatedAt: "2026-07-25T08:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "security-active",
                    exactArtifactID: activeModel.id
                ),
            ]
        )
        let revocationState = try TrustedModelRevocationState(
            snapshots: [revocations.snapshot],
            aliasSnapshots: [catalog.snapshot]
        )
        let trustedKeys = [
            TrustedModelManifestKey(
                keyId: catalog.keyID,
                publicKeyBase64: catalog.publicKeyBase64
            ),
            TrustedModelManifestKey(
                keyId: revocations.keyID,
                publicKeyBase64: revocations.publicKeyBase64
            ),
        ]
        let manifestCacheDirectory = applicationSupportDirectory
            .appendingPathComponent("ManifestCache", isDirectory: true)
        let manifestVerifier = ManifestVerifier(trustedKeys: trustedKeys)
        try TrustedCatalogStore(
            fileURL: manifestCacheDirectory.appendingPathComponent(
                "catalog-state.json"
            ),
            verifier: manifestVerifier
        ).save(
            TrustedCatalogStoredState(
                highestAcceptedRevision: catalog.snapshot.revision,
                presentedSnapshot: catalog.snapshot
            )
        )
        try TrustedModelRevocationStore(
            fileURL: manifestCacheDirectory.appendingPathComponent(
                "revocation-state.json"
            ),
            verifier: ModelRevocationVerifier(trustedKeys: trustedKeys),
            catalogVerifier: manifestVerifier
        ).save(revocationState)
        let frozenReceipt = String(
            decoding: try fixtureData(
                "rollback_bridge_v3_installed-models.json"
            ),
            as: UTF8.self
        ).replacingOccurrences(
            of: "__APPLICATION_SUPPORT__",
            with: applicationSupportDirectory.path
        )
        try Data(frozenReceipt.utf8).write(
            to: layout.installedStoreURL,
            options: .atomic
        )
        try fixtureData(
            "rollback_bridge_v3_install-queue.json"
        ).write(
            to: layout.installQueueURL,
            options: .atomic
        )
        let settingsURL = applicationSupportDirectory
            .appendingPathComponent("settings.json")
        try fixtureData("rollback_bridge_v3_settings.json").write(
            to: settingsURL,
            options: .atomic
        )
        let receiptBytesBefore = try Data(
            contentsOf: layout.installedStoreURL
        )
        let queueBytesBefore = try Data(
            contentsOf: layout.installQueueURL
        )
        let bridgeAppURL = try makeSignedCandidateApp(
            in: temporaryDirectory
        )
        let bridgeBuildIdentity = try ModelCatalogBuildIdentity
            .loadVerified(fromAppBundle: bridgeAppURL)
        let publicationEvidence = try ModelCatalogPublicationPolicy.validate(
            catalog: catalog.snapshot,
            revocations: revocations.snapshot,
            allowedCatalogSignerKeyIDs: [catalog.keyID],
            allowedRevocationSignerKeyIDs: [revocations.keyID],
            buildIdentity: bridgeBuildIdentity
        )

        let evidence = try ModelV3RollbackBridge
            .rehearsePersistedWithdrawal(
            bridgeAppBundleURL: bridgeAppURL,
            publicationEvidence: publicationEvidence,
            stateLayout: rollbackStateLayout,
            trustedKeys: trustedKeys,
            rehearsedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(evidence.catalogRevision, catalog.snapshot.revision)
        XCTAssertEqual(evidence.catalogSignerKeyID, catalog.keyID)
        XCTAssertEqual(
            evidence.revocationRevision,
            revocations.snapshot.revision
        )
        XCTAssertEqual(evidence.revocationSignerKeyID, revocations.keyID)
        XCTAssertEqual(evidence.receiptArtifactIDs, [activeModel.id])
        XCTAssertEqual(evidence.ownedStorageModelIDs, ["owned-storage-id"])
        XCTAssertEqual(evidence.queueAttemptIDs, ["queue-attempt-1"])
        XCTAssertEqual(
            evidence.activeTranscriptionArtifactID,
            activeModel.id
        )
        XCTAssertEqual(evidence.blockedActiveArtifactIDs, [activeModel.id])
        XCTAssertEqual(
            evidence.placementsByArtifactID[activeModel.id],
            .curated
        )
        XCTAssertEqual(
            evidence.bridgeBuildIdentity,
            bridgeBuildIdentity
        )
        XCTAssertEqual(evidence.ownedByteCount, UInt64(ownedBytes.count))
        XCTAssertNotNil(evidence.ownedFileSHA256ByPath[ownedFileURL.path])
        XCTAssertEqual(
            try Data(contentsOf: layout.installedStoreURL),
            receiptBytesBefore
        )
        XCTAssertEqual(
            try Data(contentsOf: layout.installQueueURL),
            queueBytesBefore
        )
        XCTAssertEqual(try Data(contentsOf: ownedFileURL), ownedBytes)

        let encoded = try JSONEncoder().encode(evidence)
        XCTAssertEqual(
            try JSONDecoder().decode(
                ModelV3RollbackRehearsalEvidence.self,
                from: encoded
            ),
            evidence
        )
    }

    func testBuildIdentityIsDerivedFromCandidateAppBytes() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyBuildIdentityTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let appURL = temporaryDirectory.appendingPathComponent(
            "Textify.app",
            isDirectory: true
        )
        let macOSURL = appURL.appendingPathComponent(
            "Contents/MacOS",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: macOSURL,
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "io.github.Player0109.Textify",
            "CFBundleShortVersionString": "1.1.0",
            "CFBundleVersion": "1",
            "CFBundleExecutable": "Textify",
        ]
        try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        ).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        let executableBytes = Data("signed candidate executable".utf8)
        try executableBytes.write(
            to: macOSURL.appendingPathComponent("Textify")
        )

        let identity = try ModelCatalogBuildIdentity.load(
            fromAppBundle: appURL
        )

        XCTAssertEqual(
            identity.bundleIdentifier,
            "io.github.Player0109.Textify"
        )
        XCTAssertEqual(identity.shortVersion, "1.1.0")
        XCTAssertEqual(identity.bundleVersion, "1")
        XCTAssertEqual(
            identity.executableSHA256,
            SHA256.hash(data: executableBytes)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }

    func testProductionPublicationRejectsIncompleteLicenseAndProvenance()
        throws
    {
        var json = try fixtureJSON("manifest_v3.json")
        var models = try XCTUnwrap(json["models"] as? [[String: Any]])
        var licenses = try XCTUnwrap(
            models[0]["licenses"] as? [[String: Any]]
        )
        licenses[0]["scope"] = ""
        models[0]["licenses"] = licenses
        json["models"] = models

        XCTAssertThrowsError(
            try ProductionModelPolicy.validateProductionManifest(
                ModelManifest.decode(
                    JSONSerialization.data(withJSONObject: json)
                )
            )
        )

        json = try fixtureJSON("manifest_v3.json")
        models = try XCTUnwrap(json["models"] as? [[String: Any]])
        var provenance = try XCTUnwrap(
            models[0]["provenance"] as? [String: Any]
        )
        provenance["sourceRevision"] = ""
        models[0]["provenance"] = provenance
        json["models"] = models

        XCTAssertThrowsError(
            try ProductionModelPolicy.validateProductionManifest(
                ModelManifest.decode(
                    JSONSerialization.data(withJSONObject: json)
                )
            )
        )
    }

    private func signedCatalogFixture() throws -> (
        snapshot: TrustedCatalogSnapshot,
        keyID: String,
        publicKeyBase64: String
    ) {
        let keyID = "fixture-v3-key"
        let publicKey = String(
            decoding: try fixtureData(
                "manifest_v3.fixture-public-key.base64"
            ),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: keyID,
                publicKeyBase64: publicKey
            ),
        ])
        return (
            try TrustedCatalogSnapshot(
                manifestData: fixtureData("manifest_v3.json"),
                signatureData: fixtureData("manifest_v3.json.sig"),
                verifier: verifier
            ),
            keyID,
            publicKey
        )
    }

    private func signedRevocations(
        generatedAt: String,
        records: [ModelRevocationRecord],
        restorations: [ModelRestorationRecord] = []
    ) throws -> (
        snapshot: TrustedModelRevocationSnapshot,
        keyID: String,
        publicKeyBase64: String
    ) {
        let keyID = "fixture-revocation-key"
        let privateKey = Curve25519.Signing.PrivateKey()
        let envelope = ModelRevocationEnvelope(
            revocationVersion: 2,
            generatedAt: generatedAt,
            records: records,
            restorations: restorations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let revocationData = try encoder.encode(envelope)
        let signatureData = try signedRevocationEnvelope(
            revocationData: revocationData,
            privateKey: privateKey,
            keyID: keyID
        )
        let verifier = ModelRevocationVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: keyID,
                publicKeyBase64:
                    privateKey.publicKey.rawRepresentation.base64EncodedString()
            ),
        ])
        return (
            try TrustedModelRevocationSnapshot(
                revocationData: revocationData,
                signatureData: signatureData,
                verifier: verifier
            ),
            keyID,
            privateKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func makeSignedCandidateApp(
        in directory: URL
    ) throws -> URL {
        let appURL = directory.appendingPathComponent(
            "Textify.app",
            isDirectory: true
        )
        let macOSURL = appURL.appendingPathComponent(
            "Contents/MacOS",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: macOSURL,
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "io.github.Player0109.Textify",
            "CFBundleShortVersionString": "1.1.0",
            "CFBundleVersion": "1",
            "CFBundleExecutable": "Textify",
            "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        ).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        let executableURL = macOSURL.appendingPathComponent("Textify")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"),
            to: executableURL
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--force",
            "--sign",
            "-",
            appURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return appURL
    }

    private func signedRevocationEnvelope(
        revocationData: Data,
        privateKey: Curve25519.Signing.PrivateKey,
        keyID: String
    ) throws -> Data {
        let contentSHA256 = SHA256.hash(data: revocationData)
            .map { String(format: "%02x", $0) }
            .joined()
        let contentType =
            "application/vnd.textify.model-revocations+json;version=2"
        let payload = Data(
            """
            TEXTIFY-MODEL-REVOCATIONS-SIGNATURE-V1
            signatureVersion=1
            signatureType=io.github.Player0109.Textify.model-revocations
            algorithm=Ed25519
            keyId=\(keyID)
            revocationFile=revocations.json
            contentType=\(contentType)
            contentSHA256=\(contentSHA256)

            """.utf8
        )
        let signature = try privateKey.signature(for: payload)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return try JSONSerialization.data(
            withJSONObject: [
                "signatureVersion": 1,
                "signatureType":
                    "io.github.Player0109.Textify.model-revocations",
                "algorithm": "Ed25519",
                "keyId": keyID,
                "revocationFile": "revocations.json",
                "contentType": contentType,
                "contentSHA256": contentSHA256,
                "signature": signature,
            ],
            options: [.sortedKeys]
        )
    }

    private func fixtureJSON(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData(name))
                as? [String: Any]
        )
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }
}
