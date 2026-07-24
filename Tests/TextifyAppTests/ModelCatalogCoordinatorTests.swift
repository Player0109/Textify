@testable import Textify
import CryptoKit
import TextifyModels
import XCTest

final class ModelCatalogCoordinatorTests: XCTestCase {
    @MainActor
    func testNoTrustedSnapshotStartsInStableCheckingState() {
        let coordinator = ModelCatalogCoordinator {
            throw ModelCatalogRefreshError.unavailable
        }

        XCTAssertNil(coordinator.manifest)
        XCTAssertEqual(coordinator.status, .checking)
        XCTAssertTrue(coordinator.isLoading)
    }

    @MainActor
    func testTrustedSnapshotRendersWhileRemoteCheckContinues() async throws {
        let initial = try manifest(revision: "2026-07-24T00:00:00Z")
        let gate = CatalogRefreshGate()
        let coordinator = ModelCatalogCoordinator(
            initialManifest: initial,
            loadOperation: {
                await gate.wait()
                return initial
            }
        )

        let refresh = Task { await coordinator.refresh() }
        await Task.yield()

        XCTAssertEqual(coordinator.manifest, initial)
        XCTAssertEqual(coordinator.status, .checkingForUpdates)
        XCTAssertTrue(coordinator.isLoading)

        await gate.open()
        _ = await refresh.value
    }

    @MainActor
    func testReadingCachedSnapshotDoesNotRefreshIntegrityCheckTime() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let cached = try signedSnapshot(
            revision: "2026-07-24T00:00:00Z",
            privateKey: privateKey
        )
        let checkTime = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )
        let coordinator = ModelCatalogCoordinator(
            storedState: TrustedCatalogStoredState(
                highestAcceptedRevision: cached.revision,
                presentedSnapshot: cached
            ),
            bundledSnapshot: nil,
            snapshotLoadOperation: { cached },
            saveOperation: { _ in },
            now: { checkTime }
        )

        XCTAssertNil(coordinator.lastSuccessfulCatalogIntegrityCheckAt)
    }

    @MainActor
    func testAcceptedAuthoritativeResponsePersistsIntegrityCheckTime() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let cached = try signedSnapshot(
            revision: "2026-07-24T00:00:00Z",
            privateKey: privateKey
        )
        let checkTime = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )
        var persisted: TrustedCatalogStoredState?
        let coordinator = ModelCatalogCoordinator(
            storedState: TrustedCatalogStoredState(
                highestAcceptedRevision: cached.revision,
                presentedSnapshot: cached
            ),
            bundledSnapshot: nil,
            snapshotLoadOperation: { cached },
            saveOperation: { persisted = $0 },
            now: { checkTime }
        )

        let result = await coordinator.refresh()

        XCTAssertEqual(result, .authoritativeIntegrityAccepted)
        XCTAssertEqual(
            coordinator.lastSuccessfulCatalogIntegrityCheckAt,
            checkTime
        )
        XCTAssertEqual(
            persisted?.lastSuccessfulCatalogIntegrityCheckAt,
            checkTime
        )
    }

    @MainActor
    func testConcurrentRefreshCallersShareOneAuthoritativeResult() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let cached = try signedSnapshot(
            revision: "2026-07-24T00:00:00Z",
            privateKey: privateKey
        )
        let gate = CatalogRefreshGate()
        let calls = CatalogRefreshCallCounter()
        let coordinator = ModelCatalogCoordinator(
            storedState: TrustedCatalogStoredState(
                highestAcceptedRevision: cached.revision,
                presentedSnapshot: cached
            ),
            bundledSnapshot: nil,
            snapshotLoadOperation: {
                await calls.increment()
                await gate.wait()
                return cached
            },
            saveOperation: { _ in }
        )

        let first = Task { await coordinator.refresh() }
        await Task.yield()
        let second = Task { await coordinator.refresh() }
        await Task.yield()
        await gate.open()

        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, .authoritativeIntegrityAccepted)
        XCTAssertEqual(secondResult, .authoritativeIntegrityAccepted)
        let callCount = await calls.value
        XCTAssertEqual(callCount, 1)
    }

    @MainActor
    func testRejectedAuthoritativeResponseDoesNotRefreshIntegrityCheckTime() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let cached = try signedSnapshot(
            revision: "2026-07-24T00:00:00Z",
            privateKey: privateKey
        )
        let priorCheck = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T01:00:00Z")
        )
        let rejectedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )
        var persisted: TrustedCatalogStoredState?
        let coordinator = ModelCatalogCoordinator(
            storedState: TrustedCatalogStoredState(
                highestAcceptedRevision: cached.revision,
                presentedSnapshot: cached,
                lastSuccessfulCatalogIntegrityCheckAt: priorCheck
            ),
            bundledSnapshot: nil,
            snapshotLoadOperation: {
                throw ManifestVerificationError.signatureRejected
            },
            saveOperation: { persisted = $0 },
            now: { rejectedAt }
        )

        let result = await coordinator.refresh()

        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(
            coordinator.lastSuccessfulCatalogIntegrityCheckAt,
            priorCheck
        )
        XCTAssertEqual(
            persisted?.lastSuccessfulCatalogIntegrityCheckAt,
            priorCheck
        )
    }

    @MainActor
    func testOfflineTransportErrorDoesNotRefreshIntegrityCheckTime() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let cached = try signedSnapshot(
            revision: "2026-07-24T00:00:00Z",
            privateKey: privateKey
        )
        let priorCheck = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T01:00:00Z")
        )
        let coordinator = ModelCatalogCoordinator(
            storedState: TrustedCatalogStoredState(
                highestAcceptedRevision: cached.revision,
                presentedSnapshot: cached,
                lastSuccessfulCatalogIntegrityCheckAt: priorCheck
            ),
            bundledSnapshot: nil,
            snapshotLoadOperation: {
                throw URLError(.notConnectedToInternet)
            },
            saveOperation: { _ in }
        )

        let result = await coordinator.refresh()

        XCTAssertEqual(result, .networkUnavailable)
        XCTAssertEqual(coordinator.status, .offline)
        XCTAssertEqual(
            coordinator.lastSuccessfulCatalogIntegrityCheckAt,
            priorCheck
        )
    }

    @MainActor
    func testAcceptedUpdateStagesWhileEitherModelsDestinationIsOpenAndApplyNowPreservesAnchors() async throws {
        let initial = try manifest(revision: "2026-07-24T00:00:00Z")
        let update = try manifest(revision: "2026-07-25T00:00:00Z")
        let coordinator = ModelCatalogCoordinator(
            initialManifest: initial,
            loadOperation: { update }
        )
        coordinator.destinationOpened(.transcription)
        var hierarchy = ModelCatalogHierarchyState(
            selection: .exactArtifact("qwen3-asr-0.6b-mlx-8bit"),
            expandedCheckpointIDs: ["checkpoint.qwen.qwen3-asr-0.6b"],
            focusedRowID: .exactArtifact("qwen3-asr-0.6b-mlx-8bit"),
            scrollAnchorID: .checkpoint("checkpoint.qwen.qwen3-asr-0.6b")
        )

        await coordinator.refresh()

        XCTAssertEqual(coordinator.manifest, initial)
        XCTAssertEqual(
            coordinator.highestAcceptedRevision,
            update.generatedAt
        )
        XCTAssertEqual(coordinator.presentedRevision, initial.generatedAt)
        XCTAssertEqual(coordinator.stagedRevision, update.generatedAt)
        XCTAssertEqual(coordinator.status, .updateAvailable)

        coordinator.applyStagedUpdate()
        hierarchy.reconcile(
            with: ModelCatalogExperience(
                trustedManifest: coordinator.manifest,
                installedRecords: [],
                activePreferences: ModelCatalogActivePreferences(),
                transferState: nil
            )
        )

        XCTAssertEqual(coordinator.manifest, update)
        XCTAssertEqual(coordinator.presentedRevision, update.generatedAt)
        XCTAssertNil(coordinator.stagedRevision)
        XCTAssertEqual(
            hierarchy.selection,
            .exactArtifact("qwen3-asr-0.6b-mlx-8bit")
        )
        XCTAssertTrue(
            hierarchy.expandedCheckpointIDs.contains(
                "checkpoint.qwen.qwen3-asr-0.6b"
            )
        )
        XCTAssertEqual(
            hierarchy.focusedRowID,
            .exactArtifact("qwen3-asr-0.6b-mlx-8bit")
        )
        XCTAssertEqual(
            hierarchy.scrollAnchorID,
            .checkpoint("checkpoint.qwen.qwen3-asr-0.6b")
        )
    }

    @MainActor
    func testInstalledActionsRemainAvailableAcrossCatalogTrustAndConnectivityStates() async throws {
        let trustedManifest = try manifest(revision: "2026-07-24T00:00:00Z")
        let update = try manifest(revision: "2026-07-25T00:00:00Z")
        let rollback = try manifest(revision: "2026-07-23T00:00:00Z")
        let installedModel = try XCTUnwrap(
            trustedManifest.models.first {
                $0.id == "qwen3-asr-0.6b-mlx-8bit"
            }
        )
        let installedRecord = InstalledModelRecord(
            model: installedModel,
            installedAt: "2026-07-24T00:00:00Z",
            localFilesByManifestFilename: [:]
        )

        let untrusted = ModelCatalogCoordinator {
            throw ModelCatalogRefreshError.unavailable
        }
        let trusted = ModelCatalogCoordinator(
            initialManifest: trustedManifest,
            loadOperation: { trustedManifest }
        )
        let offline = ModelCatalogCoordinator(
            initialManifest: trustedManifest,
            loadOperation: {
                throw ModelCatalogRefreshError.unavailable
            }
        )
        let staged = ModelCatalogCoordinator(
            initialManifest: trustedManifest,
            loadOperation: { update }
        )
        staged.destinationOpened(.transcription)
        let rejected = ModelCatalogCoordinator(
            initialManifest: trustedManifest,
            loadOperation: { rollback }
        )
        let future = ModelCatalogCoordinator(
            initialManifest: trustedManifest,
            loadOperation: {
                throw ModelCatalogRefreshError.requiresNewerTextify(
                    manifestVersion: 4
                )
            }
        )

        let scenarios = [
            ("untrusted", untrusted),
            ("trusted", trusted),
            ("offline", offline),
            ("staged", staged),
            ("rejected", rejected),
            ("future", future),
        ]
        for (_, coordinator) in scenarios {
            await coordinator.refresh()
        }

        XCTAssertNil(untrusted.manifest)
        XCTAssertEqual(trusted.status, .trusted)
        XCTAssertEqual(offline.status, .offline)
        XCTAssertEqual(staged.status, .updateAvailable)
        XCTAssertEqual(rejected.status, .securityFailure(.rollback))
        XCTAssertEqual(
            future.status,
            .requiresNewerTextify(manifestVersion: 4)
        )

        for (name, coordinator) in scenarios {
            let experience = ModelCatalogExperience(
                trustedManifest: coordinator.manifest,
                installedRecords: [installedRecord],
                activePreferences: ModelCatalogActivePreferences(),
                transferState: nil,
                managedReadinessByModelID: [installedModel.id: .ready]
            )
            let row = try XCTUnwrap(
                experience.rows.first { $0.id == installedModel.id },
                "Missing installed row in \(name) catalog state"
            )
            XCTAssertTrue(
                row.actions.contains(.use),
                "Activate must remain available in \(name) catalog state"
            )
            XCTAssertTrue(
                row.actions.contains(.delete),
                "Delete must remain available in \(name) catalog state"
            )
        }
    }

    @MainActor
    func testStagedUpdateAppliesOnlyAfterBothModelsDestinationsClose() async throws {
        let initial = try manifest(revision: "2026-07-24T00:00:00Z")
        let update = try manifest(revision: "2026-07-25T00:00:00Z")
        let coordinator = ModelCatalogCoordinator(
            initialManifest: initial,
            loadOperation: { update }
        )
        coordinator.destinationOpened(.transcription)
        await coordinator.refresh()

        coordinator.destinationChanged(
            from: .transcription,
            to: .voiceCleaning
        )
        XCTAssertEqual(coordinator.manifest, initial)

        coordinator.destinationClosed(.voiceCleaning)
        XCTAssertEqual(coordinator.manifest, update)
        XCTAssertNil(coordinator.stagedRevision)
    }

    @MainActor
    func testRepeatedMatchingRefreshKeepsAcceptedUpdateStaged() async throws {
        let initial = try manifest(revision: "2026-07-24T00:00:00Z")
        let update = try manifest(revision: "2026-07-25T00:00:00Z")
        let coordinator = ModelCatalogCoordinator(
            initialManifest: initial,
            loadOperation: { update }
        )
        coordinator.destinationOpened(.transcription)

        await coordinator.refresh()
        await coordinator.refresh()

        XCTAssertEqual(coordinator.manifest, initial)
        XCTAssertEqual(coordinator.stagedRevision, update.generatedAt)
        XCTAssertEqual(coordinator.status, .updateAvailable)
    }

    @MainActor
    func testOfflineRefreshKeepsAcceptedUpdateAvailable() async throws {
        let initial = try manifest(revision: "2026-07-24T00:00:00Z")
        let update = try manifest(revision: "2026-07-25T00:00:00Z")
        let refreshes = CatalogRefreshScript(
            steps: [.manifest(update), .unavailable]
        )
        let coordinator = ModelCatalogCoordinator(
            initialManifest: initial,
            loadOperation: { try await refreshes.next() }
        )
        coordinator.destinationOpened(.transcription)

        await coordinator.refresh()
        await coordinator.refresh()

        XCTAssertEqual(coordinator.manifest, initial)
        XCTAssertEqual(coordinator.stagedRevision, update.generatedAt)
        XCTAssertEqual(coordinator.status, .updateAvailable)
    }

    @MainActor
    func testRollbackRejectsCandidateWithoutAdvancingAcceptedOrPresentedRevision() async throws {
        let initial = try manifest(revision: "2026-07-24T00:00:00Z")
        let rollback = try manifest(revision: "2026-07-23T00:00:00Z")
        var diagnostics: [TrustedCatalogSecurityIssue] = []
        let coordinator = ModelCatalogCoordinator(
            initialManifest: initial,
            loadOperation: { rollback },
            diagnosticOperation: { diagnostics.append($0) }
        )

        await coordinator.refresh()

        XCTAssertEqual(coordinator.manifest, initial)
        XCTAssertEqual(
            coordinator.highestAcceptedRevision,
            initial.generatedAt
        )
        XCTAssertEqual(coordinator.presentedRevision, initial.generatedAt)
        XCTAssertNil(coordinator.stagedRevision)
        XCTAssertEqual(
            coordinator.status,
            .securityFailure(.rollback)
        )
        XCTAssertEqual(diagnostics.map(\.reason), [.rollback])
    }

    @MainActor
    func testUnsupportedFutureSchemaRequiresNewerTextifyWithoutSecurityFailure() async {
        var diagnostics: [TrustedCatalogSecurityIssue] = []
        let coordinator = ModelCatalogCoordinator(
            loadOperation: {
                throw ModelCatalogRefreshError.requiresNewerTextify(
                    manifestVersion: 4
                )
            },
            diagnosticOperation: { diagnostics.append($0) }
        )

        await coordinator.refresh()

        XCTAssertEqual(
            coordinator.status,
            .requiresNewerTextify(manifestVersion: 4)
        )
        XCTAssertTrue(diagnostics.isEmpty)
        XCTAssertNil(coordinator.highestAcceptedRevision)
        XCTAssertNil(coordinator.presentedRevision)
    }

    @MainActor
    func testInvalidSignatureKeepsTrustedCatalogAndPersistsHighSeverityState() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let initial = try signedSnapshot(
            revision: "2026-07-24T00:00:00Z",
            privateKey: privateKey
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogCoordinatorSecurity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrustedCatalogStore(
            fileURL: directory.appendingPathComponent("catalog-state.json"),
            verifier: verifier(for: privateKey)
        )
        try store.save(
            TrustedCatalogStoredState(
                highestAcceptedRevision: initial.revision,
                presentedSnapshot: initial
            )
        )
        var diagnostics: [TrustedCatalogSecurityIssue] = []
        let coordinator = ModelCatalogCoordinator(
            storedState: try store.load(),
            bundledSnapshot: nil,
            snapshotLoadOperation: {
                throw ManifestVerificationError.signatureRejected
            },
            saveOperation: { try store.save($0) },
            diagnosticOperation: { diagnostics.append($0) }
        )

        await coordinator.refresh()

        XCTAssertEqual(coordinator.manifest, initial.manifest)
        XCTAssertEqual(
            coordinator.status,
            .securityFailure(.invalidSignature)
        )
        XCTAssertEqual(coordinator.securityIssue?.severity, .high)
        XCTAssertEqual(diagnostics.map(\.reason), [.invalidSignature])
        XCTAssertEqual(
            try store.load().securityIssue?.reason,
            .invalidSignature
        )
    }

    @MainActor
    func testAcceptedStagedSnapshotSurvivesRelaunchAndPresentsBeforeNetwork() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let initial = try signedSnapshot(
            revision: "2026-07-24T00:00:00Z",
            privateKey: privateKey
        )
        let update = try signedSnapshot(
            revision: "2026-07-25T00:00:00Z",
            privateKey: privateKey
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogCoordinatorRelaunch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let verifier = verifier(for: privateKey)
        let store = TrustedCatalogStore(
            fileURL: directory.appendingPathComponent("catalog-state.json"),
            verifier: verifier
        )
        try store.save(
            TrustedCatalogStoredState(
                highestAcceptedRevision: initial.revision,
                presentedSnapshot: initial
            )
        )
        let coordinator = ModelCatalogCoordinator(
            storedState: try store.load(),
            bundledSnapshot: nil,
            snapshotLoadOperation: { update },
            saveOperation: { try store.save($0) }
        )
        coordinator.destinationOpened(.transcription)

        await coordinator.refresh()

        let stagedState = try store.load()
        XCTAssertEqual(
            stagedState.highestAcceptedRevision,
            update.revision
        )
        XCTAssertEqual(
            stagedState.presentedSnapshot?.revision,
            initial.revision
        )
        XCTAssertEqual(
            stagedState.stagedSnapshot?.revision,
            update.revision
        )

        let relaunched = ModelCatalogCoordinator(
            storedState: stagedState,
            bundledSnapshot: nil,
            snapshotLoadOperation: {
                throw ModelCatalogRefreshError.unavailable
            },
            saveOperation: { try store.save($0) }
        )

        XCTAssertEqual(relaunched.manifest, update.manifest)
        XCTAssertEqual(relaunched.presentedRevision, update.revision)
        XCTAssertNil(relaunched.stagedRevision)
        let relaunchedState = try store.load()
        XCTAssertEqual(
            relaunchedState.presentedSnapshot?.revision,
            update.revision
        )
        XCTAssertNil(relaunchedState.stagedSnapshot)
    }

    @MainActor
    func testBundledSnapshotIsNotPresentedBeforeItsWatermarkPersists() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let bundled = try signedSnapshot(
            revision: "2026-07-24T00:00:00Z",
            privateKey: privateKey
        )

        let coordinator = ModelCatalogCoordinator(
            storedState: TrustedCatalogStoredState(),
            bundledSnapshot: bundled,
            snapshotLoadOperation: {
                throw ModelCatalogRefreshError.unavailable
            },
            saveOperation: { _ in
                throw CatalogPersistenceTestError.writeFailed
            }
        )

        XCTAssertNil(coordinator.manifest)
        XCTAssertNil(coordinator.highestAcceptedRevision)
        XCTAssertEqual(coordinator.status, .checking)
    }

    @MainActor
    func testRemoteSnapshotDoesNotAdvanceWhenItsWatermarkCannotPersist() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let initial = try signedSnapshot(
            revision: "2026-07-24T00:00:00Z",
            privateKey: privateKey
        )
        let update = try signedSnapshot(
            revision: "2026-07-25T00:00:00Z",
            privateKey: privateKey
        )
        let coordinator = ModelCatalogCoordinator(
            storedState: TrustedCatalogStoredState(
                highestAcceptedRevision: initial.revision,
                presentedSnapshot: initial
            ),
            bundledSnapshot: nil,
            snapshotLoadOperation: { update },
            saveOperation: { _ in
                throw CatalogPersistenceTestError.writeFailed
            }
        )

        await coordinator.refresh()

        XCTAssertEqual(coordinator.manifest, initial.manifest)
        XCTAssertEqual(
            coordinator.highestAcceptedRevision,
            initial.revision
        )
        XCTAssertEqual(coordinator.presentedRevision, initial.revision)
        XCTAssertNil(coordinator.stagedRevision)
        XCTAssertEqual(coordinator.status, .offline)
    }

    @MainActor
    func testRevocationAppliesBeforeUnsupportedCatalogPresentationDecoding() async throws {
        let manifest = try manifest(revision: "2026-07-24T00:00:00Z")
        let model = try XCTUnwrap(manifest.models.first)
        let privateKey = Curve25519.Signing.PrivateKey()
        let revocation = try ModelRevocationTestFixture.snapshot(
            revision: "2026-07-24T01:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "security-advisory",
                    exactArtifactID: model.id
                ),
            ],
            privateKey: privateKey,
            keyID: "catalog-test-key"
        )
        var persisted: TrustedModelRevocationState?
        var revocationChangeCount = 0
        let coordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: {
                throw ModelCatalogRefreshError.requiresNewerTextify(
                    manifestVersion: 4
                )
            },
            revocationLoadOperation: { revocation },
            revocationSaveOperation: { persisted = $0 }
        )
        coordinator.setRevocationStateDidChange {
            revocationChangeCount += 1
        }

        await coordinator.refresh()

        XCTAssertTrue(
            coordinator.revocationOverlay.isRevoked(
                model: model,
                trustedManifest: manifest
            )
        )
        XCTAssertEqual(
            persisted?.highestAcceptedRevision,
            revocation.revision
        )
        XCTAssertEqual(revocationChangeCount, 2)
        XCTAssertEqual(
            coordinator.status,
            .requiresNewerTextify(manifestVersion: 4)
        )
    }

    func testCatalogEmptyPresentationsKeepLoadingTrustAndAvailabilityDistinct() {
        XCTAssertEqual(
            ModelCatalogEmptyPresentation.checking.title,
            "Checking signed catalog"
        )
        XCTAssertNil(ModelCatalogEmptyPresentation.checking.actionTitle)
        XCTAssertEqual(
            ModelCatalogEmptyPresentation
                .securityFailure(.transcription).title,
            "Catalog security check failed"
        )
        XCTAssertEqual(
            ModelCatalogEmptyPresentation
                .unavailable(.transcription).title,
            "Transcription catalog unavailable"
        )
        XCTAssertEqual(
            ModelCatalogEmptyPresentation
                .requiresNewerTextify(manifestVersion: 4).title,
            "Update Textify to view this catalog"
        )
        XCTAssertEqual(
            ModelCatalogEmptyPresentation
                .purpose(.voiceCleaning).title,
            "No voice-cleaning models are available"
        )
    }

    private func manifest(revision: String) throws -> ModelManifest {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let production = try ModelManifest.decode(
            Data(
                contentsOf: repositoryRoot
                    .appendingPathComponent("models/manifest.json")
            )
        )
        return ModelManifest(
            manifestVersion: production.manifestVersion,
            generatedAt: revision,
            models: production.models,
            presentationGraph: production.presentationGraph
        )
    }

    private func signedSnapshot(
        revision: String,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> TrustedCatalogSnapshot {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: repositoryRoot
                        .appendingPathComponent("models/manifest.json")
                )
            ) as? [String: Any]
        )
        object["generatedAt"] = revision
        let manifestData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        let contentSHA256 = SHA256.hash(data: manifestData)
            .map { String(format: "%02x", $0) }
            .joined()
        let contentType = ManifestVerifier.contentTypeV3
        let canonicalPayload = Data("""
        TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1
        signatureVersion=1
        signatureType=io.github.Player0109.Textify.model-manifest
        algorithm=Ed25519
        keyId=catalog-test-key
        manifestFile=manifest.json
        contentType=\(contentType)
        contentSHA256=\(contentSHA256)

        """.utf8)
        let signature = try privateKey.signature(for: canonicalPayload)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let signatureData = Data("""
        {
          "signatureVersion": 1,
          "signatureType": "io.github.Player0109.Textify.model-manifest",
          "algorithm": "Ed25519",
          "keyId": "catalog-test-key",
          "manifestFile": "manifest.json",
          "contentType": "\(contentType)",
          "contentSHA256": "\(contentSHA256)",
          "signature": "\(signature)"
        }
        """.utf8)
        return try TrustedCatalogSnapshot(
            manifestData: manifestData,
            signatureData: signatureData,
            verifier: verifier(for: privateKey)
        )
    }

    private func verifier(
        for privateKey: Curve25519.Signing.PrivateKey
    ) -> ManifestVerifier {
        ManifestVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "catalog-test-key",
                    publicKeyBase64: privateKey.publicKey.rawRepresentation
                        .base64EncodedString()
                ),
            ]
        )
    }
}

private actor CatalogRefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private enum CatalogPersistenceTestError: Error {
    case writeFailed
}

private actor CatalogRefreshCallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor CatalogRefreshScript {
    enum Step: Sendable {
        case manifest(ModelManifest)
        case unavailable
    }

    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func next() throws -> ModelManifest {
        guard !steps.isEmpty else {
            throw ModelCatalogRefreshError.unavailable
        }
        switch steps.removeFirst() {
        case let .manifest(manifest):
            return manifest
        case .unavailable:
            throw ModelCatalogRefreshError.unavailable
        }
    }
}
