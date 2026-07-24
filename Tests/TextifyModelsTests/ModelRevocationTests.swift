import CryptoKit
import TextifyModels
import XCTest

final class ModelRevocationTests: XCTestCase {
    func testSignedRevocationSnapshotVerifiesWithoutCatalogData() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let revocationData = Data(
            """
            {
              "revocationVersion": 1,
              "generatedAt": "2026-07-24T12:00:00Z",
              "records": [
                {
                  "recordID": "revocation-1",
                  "exactArtifactID": "artifact-a",
                  "contentDigest": null
                }
              ]
            }
            """.utf8
        )
        let signatureData = try signedEnvelope(
            revocationData: revocationData,
            privateKey: privateKey
        )
        let verifier = ModelRevocationVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "revocation-test-key",
                    publicKeyBase64: privateKey.publicKey.rawRepresentation
                        .base64EncodedString()
                ),
            ]
        )

        let snapshot = try TrustedModelRevocationSnapshot(
            revocationData: revocationData,
            signatureData: signatureData,
            verifier: verifier
        )

        XCTAssertEqual(snapshot.revision, "2026-07-24T12:00:00Z")
        XCTAssertEqual(
            snapshot.envelope.records.map(\.recordID),
            ["revocation-1"]
        )
    }

    func testExactArtifactIDAndScopedDigestUseORMatching() throws {
        let manifest = try ModelManifest.decode(
            fixtureData("manifest_v3.json")
        )
        let model = try XCTUnwrap(manifest.models.first)
        let nonmatchingDigest = String(repeating: "0", count: 64)
        let byID = ModelRevocationRecord(
            recordID: "by-id",
            exactArtifactID: model.id,
            contentDigest: ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: nonmatchingDigest,
                scope: .singleFilePayload
            )
        )
        let byDigest = ModelRevocationRecord(
            recordID: "by-digest",
            exactArtifactID: "different-artifact",
            contentDigest: ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: try XCTUnwrap(model.files.first?.sha256),
                scope: .singleFilePayload
            )
        )
        let neither = ModelRevocationRecord(
            recordID: "neither",
            exactArtifactID: "different-artifact",
            contentDigest: ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: nonmatchingDigest,
                scope: .singleFilePayload
            )
        )

        XCTAssertTrue(
            ModelRevocationOverlay(records: [byID])
                .isRevoked(model: model, trustedManifest: manifest)
        )
        XCTAssertTrue(
            ModelRevocationOverlay(records: [byDigest])
                .isRevoked(model: model, trustedManifest: manifest)
        )
        XCTAssertFalse(
            ModelRevocationOverlay(records: [neither])
                .isRevoked(model: model, trustedManifest: manifest)
        )
    }

    func testCanonicalLayoutAndManagedFileDigestsRequireExactScope() throws {
        let manifest = try ModelManifest.decode(
            fixtureData("manifest_v3.json")
        )
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let canonical = ModelRevocationRecord(
            recordID: "canonical",
            contentDigest: ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: model.artifactFingerprint(),
                scope: .canonicalLayout(version: 1)
            )
        )
        let managedFile = ModelRevocationRecord(
            recordID: "managed-file",
            contentDigest: ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: file.sha256,
                scope: .managedFile(
                    relativePath: file.relativePath ?? file.filename
                )
            )
        )
        let wrongManagedPath = ModelRevocationRecord(
            recordID: "wrong-managed-path",
            contentDigest: ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: file.sha256,
                scope: .managedFile(relativePath: "different.bin")
            )
        )

        XCTAssertTrue(
            ModelRevocationOverlay(records: [canonical])
                .isRevoked(model: model, trustedManifest: manifest)
        )
        XCTAssertTrue(
            ModelRevocationOverlay(records: [managedFile])
                .isRevoked(model: model, trustedManifest: manifest)
        )
        XCTAssertFalse(
            ModelRevocationOverlay(records: [wrongManagedPath])
                .isRevoked(model: model, trustedManifest: manifest)
        )
    }

    func testAliasAndImportedIdentityHistoryMatchWithoutFilenameIdentity() throws {
        let decoded = try ModelManifest.decode(
            fixtureData("manifest_v3.json")
        )
        let model = try XCTUnwrap(decoded.models.first)
        let aliasID = "legacy-artifact-alias"
        let manifest = ModelManifest(
            manifestVersion: decoded.manifestVersion,
            generatedAt: decoded.generatedAt,
            models: decoded.models,
            presentationGraph: decoded.presentationGraph,
            artifactAliases: [
                ModelArtifactAlias(
                    aliasArtifactID: aliasID,
                    canonicalArtifactID: model.id
                ),
            ]
        )
        let digest = try XCTUnwrap(model.files.first?.sha256)
        let importedRecord = InstalledModelRecord(
            model: model,
            installedAt: "2026-07-24T00:00:00Z",
            localFilesByManifestFilename: [:],
            storageModelID: "legacy-storage-id",
            identityHistory: InstalledModelIdentityHistory(
                customImport: CustomModelImportHistory(
                    contentDigest: ModelArtifactTypedDigest(
                        type: .singleFileSHA256,
                        value: digest
                    ),
                    localNames: ["Imported model"],
                    sourceFilenames: ["renamed-model.bin"]
                )
            )
        )
        let overlay = ModelRevocationOverlay(
            records: [
                ModelRevocationRecord(
                    recordID: "alias",
                    exactArtifactID: aliasID
                ),
                ModelRevocationRecord(
                    recordID: "digest",
                    contentDigest: ModelRevocationDigestTarget(
                        algorithm: .sha256,
                        value: digest,
                        scope: .singleFilePayload
                    )
                ),
            ]
        )

        XCTAssertTrue(
            overlay.isRevoked(model: model, trustedManifest: manifest)
        )
        XCTAssertEqual(
            overlay.matchingRecordIDs(
                for: importedRecord,
                trustedManifest: manifest
            ),
            ["alias", "digest"]
        )
        XCTAssertFalse(
            ModelRevocationOverlay(
                records: [
                    ModelRevocationRecord(
                        recordID: "filename",
                        exactArtifactID: try XCTUnwrap(
                            model.files.first?.filename
                        )
                    ),
                ]
            ).isRevoked(model: model, trustedManifest: manifest)
        )
        let laterManifest = ModelManifest(
            manifestVersion: decoded.manifestVersion,
            generatedAt: "2026-07-25T00:00:00Z",
            models: decoded.models,
            presentationGraph: decoded.presentationGraph
        )
        XCTAssertTrue(
            ModelRevocationOverlay(
                records: [
                    ModelRevocationRecord(
                        recordID: "retained-alias",
                        exactArtifactID: aliasID
                    ),
                ],
                retainedArtifactAliases: manifest.artifactAliases
            ).isRevoked(
                model: model,
                trustedManifest: laterManifest
            )
        )
    }

    func testCustomReimportRemainsRevokedByTypedContentDigest() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ModelRevocationImport-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let sourceURL = root.appendingPathComponent("renamed.gguf")
        var sourceData = Data("GGUF".utf8)
        sourceData.append(
            Data(
                repeating: 0x52,
                count: Int(
                    CustomWhisperModelImporter.minimumFileSizeBytes
                ) - 4
            )
        )
        try sourceData.write(to: sourceURL)
        let importer = CustomWhisperModelImporter(
            layout: ModelStorageLayout(
                rootDirectory: root.appendingPathComponent("Models")
            ),
            nowISO8601: { "2026-07-24T00:00:00Z" }
        )
        _ = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "First name",
                licenseName: "User-provided"
            )
        )
        let reimported = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Second name",
                licenseName: "User-provided"
            )
        )
        let digest = SHA256.hash(data: sourceData)
            .map { String(format: "%02x", $0) }
            .joined()
        let overlay = ModelRevocationOverlay(
            records: [
                ModelRevocationRecord(
                    recordID: "custom-content",
                    contentDigest: ModelRevocationDigestTarget(
                        algorithm: .sha256,
                        value: digest,
                        scope: .singleFilePayload
                    )
                ),
            ]
        )

        XCTAssertEqual(
            reimported.identityHistory.customImport?.localNames,
            ["First name", "Second name"]
        )
        XCTAssertTrue(
            overlay.isRevoked(
                record: reimported,
                trustedManifest: nil
            )
        )
    }

    func testLegacyCustomIdentityMigrationRetainsDigestRevocation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ModelRevocationLegacy-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let sourceURL = root.appendingPathComponent("legacy.ggml")
        var sourceData = Data([0x6c, 0x6d, 0x67, 0x67])
        sourceData.append(
            Data(
                repeating: 0x4c,
                count: Int(
                    CustomWhisperModelImporter.minimumFileSizeBytes
                ) - 4
            )
        )
        try sourceData.write(to: sourceURL)
        let imported = try await CustomWhisperModelImporter(
            layout: ModelStorageLayout(
                rootDirectory: root.appendingPathComponent("Models")
            ),
            nowISO8601: { "2026-07-24T00:00:00Z" }
        ).importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Legacy import",
                licenseName: "User-provided"
            )
        )
        let digest = try XCTUnwrap(
            imported.identityHistory.customImport?.contentDigest.value
        )
        let legacyID = "custom-whisper-\(digest.prefix(16))"
        let legacyRecord = InstalledModelRecord(
            model: copy(imported.model, id: legacyID),
            installedAt: imported.installedAt,
            localFilesByManifestFilename:
                imported.localFilesByManifestFilename,
            storageModelID: legacyID,
            identityHistory: InstalledModelIdentityHistory()
        )
        let migrated = try XCTUnwrap(
            ModelArtifactPlacementResolver()
                .reconcile(
                    records: [legacyRecord],
                    trustedManifest: nil
                )
                .records
                .first
        )

        XCTAssertEqual(
            migrated.model.id,
            CustomWhisperModelImporter.importedModelIDPrefix + digest
        )
        XCTAssertTrue(
            ModelRevocationOverlay(
                records: [
                    ModelRevocationRecord(
                        recordID: "legacy-content",
                        contentDigest: ModelRevocationDigestTarget(
                            algorithm: .sha256,
                            value: digest,
                            scope: .singleFilePayload
                        )
                    ),
                ]
            ).isRevoked(
                record: migrated,
                trustedManifest: nil
            )
        )
    }

    func testAmbiguousDigestScopeIsRejected() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let revocationData = Data(
            """
            {
              "revocationVersion": 1,
              "generatedAt": "2026-07-24T12:00:00Z",
              "records": [
                {
                  "recordID": "ambiguous",
                  "exactArtifactID": null,
                  "contentDigest": {
                    "algorithm": "sha256",
                    "value": "\(String(repeating: "a", count: 64))",
                    "scope": {
                      "type": "single_file_payload",
                      "relativePath": "model.bin"
                    }
                  }
                }
              ]
            }
            """.utf8
        )
        let verifier = verifier(for: privateKey)

        XCTAssertThrowsError(
            try TrustedModelRevocationSnapshot(
                revocationData: revocationData,
                signatureData: signedEnvelope(
                    revocationData: revocationData,
                    privateKey: privateKey
                ),
                verifier: verifier
            )
        )
    }

    func testRestorationSchemaRejectsVersionKeyMismatches() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let v1WithRestorations = Data(
            """
            {
              "revocationVersion": 1,
              "generatedAt": "2026-07-24T12:00:00Z",
              "records": [],
              "restorations": []
            }
            """.utf8
        )
        let v2WithoutRestorations = Data(
            """
            {
              "revocationVersion": 2,
              "generatedAt": "2026-07-24T12:00:00Z",
              "records": []
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try TrustedModelRevocationSnapshot(
                revocationData: v1WithRestorations,
                signatureData: signedEnvelope(
                    revocationData: v1WithRestorations,
                    privateKey: privateKey
                ),
                verifier: verifier(for: privateKey)
            )
        )
        XCTAssertThrowsError(
            try TrustedModelRevocationSnapshot(
                revocationData: v2WithoutRestorations,
                signatureData: signedEnvelope(
                    revocationData: v2WithoutRestorations,
                    privateKey: privateKey,
                    contentTypeVersion: 2
                ),
                verifier: verifier(for: privateKey)
            )
        )
    }

    func testRestorationPolicyRejectsInvalidDuplicateAndMissingIdentity() {
        let validTarget = ModelRestorationRecord(
            restorationID: "restoration-a",
            revocationRecordID: "revocation-a",
            exactArtifactID: "artifact-a"
        )
        let invalidID = ModelRevocationEnvelope(
            revocationVersion: 2,
            generatedAt: "2026-07-24T12:00:00Z",
            records: [],
            restorations: [
                ModelRestorationRecord(
                    restorationID: "invalid/id",
                    revocationRecordID: "revocation-a",
                    exactArtifactID: "artifact-a"
                ),
            ]
        )
        let duplicateID = ModelRevocationEnvelope(
            revocationVersion: 2,
            generatedAt: "2026-07-24T12:00:00Z",
            records: [],
            restorations: [validTarget, validTarget]
        )
        let missingTarget = ModelRevocationEnvelope(
            revocationVersion: 2,
            generatedAt: "2026-07-24T12:00:00Z",
            records: [],
            restorations: [
                ModelRestorationRecord(
                    restorationID: "restoration-missing-target",
                    revocationRecordID: "revocation-a"
                ),
            ]
        )

        XCTAssertThrowsError(
            try ModelRevocationPolicy.validate(invalidID)
        ) { error in
            XCTAssertEqual(
                error as? ModelRevocationPolicyError,
                .invalidRestorationID("invalid/id")
            )
        }
        XCTAssertThrowsError(
            try ModelRevocationPolicy.validate(duplicateID)
        ) { error in
            XCTAssertEqual(
                error as? ModelRevocationPolicyError,
                .duplicateRestorationID("restoration-a")
            )
        }
        XCTAssertThrowsError(
            try ModelRevocationPolicy.validate(missingTarget)
        ) { error in
            XCTAssertEqual(
                error as? ModelRevocationPolicyError,
                .missingRestorationTarget("restoration-missing-target")
            )
        }
    }

    func testRestorationIdentityIsImmutableAcrossSignedRevisions() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let revoked = try snapshot(
            revision: "2026-07-24T10:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "revocation-a",
                    exactArtifactID: "artifact-a"
                ),
                ModelRevocationRecord(
                    recordID: "revocation-b",
                    exactArtifactID: "artifact-a"
                ),
            ],
            privateKey: privateKey
        )
        let firstRestoration = try snapshot(
            revision: "2026-07-24T11:00:00Z",
            version: 2,
            records: [],
            restorations: [
                ModelRestorationRecord(
                    restorationID: "restoration-a",
                    revocationRecordID: "revocation-a",
                    exactArtifactID: "artifact-a"
                ),
            ],
            privateKey: privateKey
        )
        let conflictingRestoration = try snapshot(
            revision: "2026-07-24T12:00:00Z",
            version: 2,
            records: [],
            restorations: [
                ModelRestorationRecord(
                    restorationID: "restoration-a",
                    revocationRecordID: "revocation-b",
                    exactArtifactID: "artifact-a"
                ),
            ],
            privateKey: privateKey
        )
        let state = try TrustedModelRevocationState()
            .accepting(revoked)
            .accepting(firstRestoration)

        XCTAssertThrowsError(
            try state.accepting(conflictingRestoration)
        ) { error in
            XCTAssertEqual(
                error as? TrustedModelRevocationStateError,
                .conflictingRestoration("restoration-a")
            )
        }
    }

    func testAcceptedRevocationsAreStickyAcrossOmissionStoreReloadAndRollback() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let first = try snapshot(
            revision: "2026-07-24T10:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "first",
                    exactArtifactID: "artifact-a"
                ),
            ],
            privateKey: privateKey
        )
        let second = try snapshot(
            revision: "2026-07-24T11:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "second",
                    exactArtifactID: "artifact-b"
                ),
            ],
            privateKey: privateKey
        )
        let rollback = try snapshot(
            revision: "2026-07-24T09:00:00Z",
            records: [],
            privateKey: privateKey
        )
        let accepted = try TrustedModelRevocationState()
            .accepting(first)
            .accepting(second)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelRevocationTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrustedModelRevocationStore(
            fileURL: directory.appendingPathComponent("state.json"),
            verifier: verifier(for: privateKey),
            catalogVerifier: catalogVerifier(for: privateKey)
        )

        try store.save(accepted)
        let restored = try store.load()

        XCTAssertEqual(
            restored.overlay.records.map(\.recordID),
            ["first", "second"]
        )
        XCTAssertThrowsError(try restored.accepting(rollback)) { error in
            XCTAssertEqual(
                error as? TrustedModelRevocationStateError,
                .rollback(
                    candidateRevision: rollback.revision,
                    highestAcceptedRevision: second.revision
                )
            )
        }
        XCTAssertEqual(
            restored.overlay.records.map(\.recordID),
            ["first", "second"]
        )
    }

    func testHigherSignedRevisionRestoresOnlyReferencedExactTargets() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let digest = ModelRevocationDigestTarget(
            algorithm: .sha256,
            value: String(repeating: "a", count: 64),
            scope: .singleFilePayload
        )
        let first = try snapshot(
            revision: "2026-07-24T10:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "revocation-a",
                    exactArtifactID: "artifact-a",
                    contentDigest: digest
                ),
                ModelRevocationRecord(
                    recordID: "overlapping-revocation",
                    exactArtifactID: "artifact-a"
                ),
            ],
            privateKey: privateKey
        )
        let restoration = try snapshot(
            revision: "2026-07-24T11:00:00Z",
            version: 2,
            records: [],
            restorations: [
                ModelRestorationRecord(
                    restorationID: "restoration-a",
                    revocationRecordID: "revocation-a",
                    exactArtifactID: "artifact-a",
                    contentDigest: digest
                ),
            ],
            privateKey: privateKey
        )

        let state = try TrustedModelRevocationState()
            .accepting(first)
            .accepting(restoration)

        XCTAssertTrue(
            state.overlay.isRevoked(
                artifactID: "artifact-a",
                trustedManifest: nil
            ),
            "Restoring one record must not clear another matching revocation."
        )
        XCTAssertEqual(
            state.restorationIDsRequiringIntegrityVerification(
                artifactID: "artifact-a",
                trustedManifest: nil
            ),
            ["restoration-a"]
        )
        XCTAssertEqual(
            state.overlay.records.map(\.recordID),
            ["overlapping-revocation"]
        )
    }

    func testRestorationRejectsUnknownRecordAndNonExactTarget() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let first = try snapshot(
            revision: "2026-07-24T10:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "revocation-a",
                    exactArtifactID: "artifact-a"
                ),
            ],
            privateKey: privateKey
        )
        let unknown = try snapshot(
            revision: "2026-07-24T11:00:00Z",
            version: 2,
            records: [],
            restorations: [
                ModelRestorationRecord(
                    restorationID: "unknown-restoration",
                    revocationRecordID: "missing-record",
                    exactArtifactID: "artifact-a"
                ),
            ],
            privateKey: privateKey
        )
        let mismatched = try snapshot(
            revision: "2026-07-24T12:00:00Z",
            version: 2,
            records: [],
            restorations: [
                ModelRestorationRecord(
                    restorationID: "mismatched-restoration",
                    revocationRecordID: "revocation-a",
                    exactArtifactID: "artifact-b"
                ),
            ],
            privateKey: privateKey
        )
        let state = try TrustedModelRevocationState().accepting(first)

        XCTAssertThrowsError(try state.accepting(unknown)) { error in
            XCTAssertEqual(
                error as? TrustedModelRevocationStateError,
                .unknownRestorationRecord(
                    restorationID: "unknown-restoration",
                    revocationRecordID: "missing-record"
                )
            )
        }
        XCTAssertThrowsError(try state.accepting(mismatched)) { error in
            XCTAssertEqual(
                error as? TrustedModelRevocationStateError,
                .restorationTargetMismatch(
                    restorationID: "mismatched-restoration",
                    revocationRecordID: "revocation-a"
                )
            )
        }
    }

    func testSignedAliasEvidenceSurvivesCatalogOmissionAndStoreReload() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let aliasSnapshot = try signedAliasCatalogSnapshot(
            privateKey: privateKey
        )
        let redundantAliasSnapshot = try signedAliasCatalogSnapshot(
            privateKey: privateKey,
            revision: "2026-07-24T11:30:00Z"
        )
        let alias = try XCTUnwrap(
            aliasSnapshot.manifest.artifactAliases.first
        )
        let revocation = try snapshot(
            revision: "2026-07-24T12:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "alias-revocation",
                    exactArtifactID: alias.aliasArtifactID
                ),
            ],
            privateKey: privateKey
        )
        let state = try TrustedModelRevocationState()
            .accepting(revocation)
            .retainingAliases(from: aliasSnapshot)
            .retainingAliases(from: redundantAliasSnapshot)
        XCTAssertEqual(state.aliasSnapshots.count, 1)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelAliasStore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrustedModelRevocationStore(
            fileURL: directory.appendingPathComponent("state.json"),
            verifier: verifier(for: privateKey),
            catalogVerifier: catalogVerifier(for: privateKey)
        )

        try store.save(state)
        let restored = try store.load()
        let laterManifest = try ModelManifest.decode(
            fixtureData("manifest_v3.json")
        )
        let canonical = try XCTUnwrap(
            laterManifest.models.first {
                $0.id == alias.canonicalArtifactID
            }
        )

        XCTAssertTrue(
            restored.overlay.isRevoked(
                model: canonical,
                trustedManifest: laterManifest
            )
        )
        XCTAssertTrue(laterManifest.artifactAliases.isEmpty)
    }

    func testDownloadUsesOnlyConfiguredAnonymousGETs() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let revocationData = try JSONEncoder().encode(
            ModelRevocationEnvelope(
                revocationVersion: 1,
                generatedAt: "2026-07-24T12:00:00Z",
                records: []
            )
        )
        let signatureData = try signedEnvelope(
            revocationData: revocationData,
            privateKey: privateKey
        )
        let revocationURL = URL(
            string: "https://example.com/revocations.json"
        )!
        let signatureURL = URL(
            string: "https://example.com/revocations.json.sig"
        )!
        let transport = CapturingRevocationTransport(
            responses: [
                revocationURL: revocationData,
                signatureURL: signatureData,
            ]
        )

        _ = try await ModelRevocationDownloader(
            transport: transport,
            verifier: verifier(for: privateKey)
        ).downloadSnapshot(
            revocationURL: revocationURL,
            signatureURL: signatureURL
        )

        XCTAssertEqual(
            transport.requests.map(\.url),
            [revocationURL, signatureURL]
        )
        XCTAssertEqual(transport.requests.map(\.httpMethod), ["GET", "GET"])
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpBody == nil })
        XCTAssertTrue(
            transport.requests.allSatisfy {
                $0.url?.query == nil && $0.allHTTPHeaderFields?.isEmpty != false
            }
        )
    }

    private func snapshot(
        revision: String,
        version: Int = 1,
        records: [ModelRevocationRecord],
        restorations: [ModelRestorationRecord] = [],
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> TrustedModelRevocationSnapshot {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let revocationData = try encoder.encode(
            ModelRevocationEnvelope(
                revocationVersion: version,
                generatedAt: revision,
                records: records,
                restorations: restorations
            )
        )
        return try TrustedModelRevocationSnapshot(
            revocationData: revocationData,
            signatureData: signedEnvelope(
                revocationData: revocationData,
                privateKey: privateKey,
                contentTypeVersion: version
            ),
            verifier: verifier(for: privateKey)
        )
    }

    private func verifier(
        for privateKey: Curve25519.Signing.PrivateKey
    ) -> ModelRevocationVerifier {
        ModelRevocationVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "revocation-test-key",
                    publicKeyBase64: privateKey.publicKey.rawRepresentation
                        .base64EncodedString()
                ),
            ]
        )
    }

    private func catalogVerifier(
        for privateKey: Curve25519.Signing.PrivateKey
    ) -> ManifestVerifier {
        ManifestVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "revocation-test-key",
                    publicKeyBase64: privateKey.publicKey.rawRepresentation
                        .base64EncodedString()
                ),
            ],
            legacyPolicy: .publishedV1_1
        )
    }

    private func signedAliasCatalogSnapshot(
        privateKey: Curve25519.Signing.PrivateKey,
        revision: String = "2026-07-24T11:00:00Z"
    ) throws -> TrustedCatalogSnapshot {
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: fixtureData("manifest_v3.json")
            ) as? [String: Any]
        )
        var models = try XCTUnwrap(root["models"] as? [[String: Any]])
        let canonicalIndex = try XCTUnwrap(
            models.firstIndex {
                $0["id"] as? String == "whisper-small-q5_1"
            }
        )
        let aliasIndex = try XCTUnwrap(
            models.firstIndex {
                $0["id"] as? String == "whisper-small-q8_0"
            }
        )
        models[aliasIndex]["files"] = models[canonicalIndex]["files"]
        models[aliasIndex]["sizeBytes"] =
            models[canonicalIndex]["sizeBytes"]
        models[aliasIndex]["installationStorage"] =
            models[canonicalIndex]["installationStorage"]
        root["models"] = models
        root["artifactAliases"] = [
            [
                "aliasArtifactID": "whisper-small-q8_0",
                "canonicalArtifactID": "whisper-small-q5_1",
            ],
        ]
        root["generatedAt"] = revision
        let manifestData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys]
        )
        let contentSHA256 = SHA256.hash(data: manifestData)
            .map { String(format: "%02x", $0) }
            .joined()
        let contentType = ManifestVerifier.contentTypeV3
        let payload = Data(
            """
            TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1
            signatureVersion=1
            signatureType=io.github.Player0109.Textify.model-manifest
            algorithm=Ed25519
            keyId=revocation-test-key
            manifestFile=manifest.json
            contentType=\(contentType)
            contentSHA256=\(contentSHA256)

            """.utf8
        )
        let signature = try privateKey.signature(for: payload)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let signatureData = Data(
            """
            {
              "signatureVersion": 1,
              "signatureType": "io.github.Player0109.Textify.model-manifest",
              "algorithm": "Ed25519",
              "keyId": "revocation-test-key",
              "manifestFile": "manifest.json",
              "contentType": "\(contentType)",
              "contentSHA256": "\(contentSHA256)",
              "signature": "\(signature)"
            }
            """.utf8
        )
        return try TrustedCatalogSnapshot(
            manifestData: manifestData,
            signatureData: signatureData,
            verifier: catalogVerifier(for: privateKey)
        )
    }

    private func signedEnvelope(
        revocationData: Data,
        privateKey: Curve25519.Signing.PrivateKey,
        keyID: String = "revocation-test-key",
        contentTypeVersion: Int = 1
    ) throws -> Data {
        let contentSHA256 = SHA256.hash(data: revocationData)
            .map { String(format: "%02x", $0) }
            .joined()
        let contentType =
            "application/vnd.textify.model-revocations+json;version=\(contentTypeVersion)"
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
        return Data(
            """
            {
              "signatureVersion": 1,
              "signatureType": "io.github.Player0109.Textify.model-revocations",
              "algorithm": "Ed25519",
              "keyId": "\(keyID)",
              "revocationFile": "revocations.json",
              "contentType": "\(contentType)",
              "contentSHA256": "\(contentSHA256)",
              "signature": "\(signature)"
            }
            """.utf8
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

    private func copy(_ model: ModelEntry, id: String) -> ModelEntry {
        ModelEntry(
            id: id,
            displayName: model.displayName,
            tier: model.tier,
            description: model.description,
            sizeBytes: model.sizeBytes,
            files: model.files,
            licenses: model.licenses,
            provenance: model.provenance,
            runtimeParameters: model.runtimeParameters,
            hallucinationThresholds: model.hallucinationThresholds,
            minAppVersion: model.minAppVersion,
            runtime: model.runtime,
            capabilities: model.capabilities,
            presentation: model.presentation,
            purpose: model.purpose,
            installationStorage: model.installationStorage,
            benchmark: model.benchmark
        )
    }
}

private final class CapturingRevocationTransport: DownloadTransport {
    private let responses: [URL: Data]
    private(set) var requests: [URLRequest] = []

    init(responses: [URL: Data]) {
        self.responses = responses
    }

    func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        requests.append(request)
        guard let url = request.url, let data = responses[url] else {
            throw CapturingRevocationTransportError.missingResponse
        }
        return DownloadResponse(data: data)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL
    ) async throws -> DownloadFileResponse {
        throw CapturingRevocationTransportError.unsupported
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        throw CapturingRevocationTransportError.unsupported
    }
}

private enum CapturingRevocationTransportError: Error {
    case missingResponse
    case unsupported
}
