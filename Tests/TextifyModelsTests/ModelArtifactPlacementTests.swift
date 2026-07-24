import Foundation
import TextifyModels
import XCTest

final class ModelArtifactPlacementTests: XCTestCase {
    func testCuratedArtifactBecomesNoLongerCuratedWithoutRegressingToLegacy() throws {
        let model = try fixtureModel()
        let record = InstalledModelRecord(
            model: model,
            installedAt: "2026-07-24T00:00:00Z",
            localFilesByManifestFilename: [
                model.files[0].filename: "/Models/\(model.id)/\(model.files[0].filename)",
            ]
        )
        let resolver = ModelArtifactPlacementResolver()

        let curated = resolver.reconcile(
            records: [record],
            trustedManifest: ModelManifest(
                manifestVersion: 1,
                generatedAt: "2026-07-24T00:00:00Z",
                models: [model]
            )
        )
        XCTAssertEqual(curated.placement(forArtifactID: model.id), .curated)
        XCTAssertTrue(try XCTUnwrap(curated.records.first).identityHistory.wasCurated)

        let removed = resolver.reconcile(
            records: curated.records,
            trustedManifest: ModelManifest(
                manifestVersion: 1,
                generatedAt: "2026-07-25T00:00:00Z",
                models: []
            )
        )
        XCTAssertEqual(
            removed.placement(forArtifactID: model.id),
            .noLongerCurated
        )
    }

    func testUniqueSignedDigestCanonicalizesCustomArtifactAndPreservesLocalHistory() throws {
        let signedModel = try fixtureModel()
        let customID = "custom-sha256-\(signedModel.files[0].sha256)"
        let localModel = copy(
            signedModel,
            id: customID,
            displayName: "My Local Rename"
        )
        let record = InstalledModelRecord(
            model: localModel,
            installedAt: "2026-07-24T00:00:00Z",
            localFilesByManifestFilename: [
                localModel.files[0].filename: "/Models/\(customID)/model.bin",
            ],
            identityHistory: InstalledModelIdentityHistory(
                customImport: CustomModelImportHistory(
                    contentDigest: ModelArtifactTypedDigest(
                        type: .singleFileSHA256,
                        value: signedModel.files[0].sha256
                    ),
                    localNames: ["My Local Rename"],
                    sourceFilenames: ["renamed.ggml"]
                )
            )
        )

        let snapshot = ModelArtifactPlacementResolver().reconcile(
            records: [record],
            trustedManifest: ModelManifest(
                manifestVersion: 1,
                generatedAt: "2026-07-25T00:00:00Z",
                models: [signedModel]
            )
        )

        let canonical = try XCTUnwrap(snapshot.records.first)
        XCTAssertEqual(canonical.model, signedModel)
        XCTAssertEqual(canonical.storageModelID, customID)
        XCTAssertEqual(
            canonical.identityHistory.customImport?.localNames,
            ["My Local Rename"]
        )
        XCTAssertEqual(
            snapshot.placement(forArtifactID: signedModel.id),
            .curated
        )
    }

    func testUniqueSignedDigestCanonicalizesLegacyArtifactWithoutCustomHistory() throws {
        let signedModel = try fixtureModel()
        let legacyID = "legacy-local-copy"
        let record = InstalledModelRecord(
            model: copy(
                signedModel,
                id: legacyID,
                displayName: "Imported Before Identity Tracking"
            ),
            installedAt: "2026-07-20T00:00:00Z",
            localFilesByManifestFilename: [
                signedModel.files[0].filename: "/Models/\(legacyID)/model.bin",
            ]
        )

        let snapshot = ModelArtifactPlacementResolver().reconcile(
            records: [record],
            trustedManifest: ModelManifest(
                manifestVersion: 1,
                generatedAt: "2026-07-25T00:00:00Z",
                models: [signedModel]
            )
        )

        let canonical = try XCTUnwrap(snapshot.records.first)
        XCTAssertEqual(canonical.model, signedModel)
        XCTAssertEqual(canonical.storageModelID, legacyID)
        XCTAssertEqual(
            canonical.identityHistory.customImport?.localNames,
            ["Imported Before Identity Tracking"]
        )
        XCTAssertEqual(
            canonical.identityHistory.customImport?.sourceFilenames,
            [record.model.provenance.sourceFile]
        )
        XCTAssertEqual(
            snapshot.placement(forArtifactID: signedModel.id),
            .curated
        )
    }

    func testDuplicateLocalDigestFailsClosedWithoutOrphaningEitherStorageIdentity() throws {
        let signedModel = try fixtureModel()
        let digest = ModelArtifactTypedDigest(
            type: .singleFileSHA256,
            value: signedModel.files[0].sha256
        )
        let customID = "custom-sha256-\(digest.value)"
        let legacyID = "legacy-duplicate"
        let custom = InstalledModelRecord(
            model: copy(signedModel, id: customID, displayName: "Custom"),
            installedAt: "2026-07-20T00:00:00Z",
            localFilesByManifestFilename: [
                signedModel.files[0].filename: "/Models/\(customID)/model.bin",
            ],
            identityHistory: InstalledModelIdentityHistory(
                customImport: CustomModelImportHistory(
                    contentDigest: digest,
                    localNames: ["Custom"],
                    sourceFilenames: ["custom.ggml"]
                )
            )
        )
        let legacy = InstalledModelRecord(
            model: copy(signedModel, id: legacyID, displayName: "Legacy"),
            installedAt: "2026-07-21T00:00:00Z",
            localFilesByManifestFilename: [
                signedModel.files[0].filename: "/Models/\(legacyID)/model.bin",
            ]
        )

        let snapshot = ModelArtifactPlacementResolver().reconcile(
            records: [custom, legacy],
            trustedManifest: ModelManifest(
                manifestVersion: 1,
                generatedAt: "2026-07-25T00:00:00Z",
                models: [signedModel]
            )
        )

        XCTAssertEqual(
            Set(snapshot.records.map(\.model.id)),
            [customID, legacyID]
        )
        XCTAssertEqual(
            snapshot.placement(forArtifactID: customID),
            .custom
        )
        XCTAssertEqual(
            snapshot.placement(forArtifactID: legacyID),
            .legacy
        )
    }

    func testAmbiguousSignedDigestStaysCustomUnlessAliasNamesOneCanonicalArtifact() throws {
        let first = try fixtureModel()
        let second = copy(first, id: "duplicate-exact-artifact", displayName: "Duplicate")
        let customID = "custom-sha256-\(first.files[0].sha256)"
        let record = InstalledModelRecord(
            model: copy(first, id: customID, displayName: "Local"),
            installedAt: "2026-07-24T00:00:00Z",
            localFilesByManifestFilename: ["model.bin": "/Models/\(customID)/model.bin"],
            identityHistory: InstalledModelIdentityHistory(
                customImport: CustomModelImportHistory(
                    contentDigest: ModelArtifactTypedDigest(
                        type: .singleFileSHA256,
                        value: first.files[0].sha256
                    ),
                    localNames: ["Local"],
                    sourceFilenames: ["local.ggml"]
                )
            )
        )
        let unresolved = ModelArtifactPlacementResolver().reconcile(
            records: [record],
            trustedManifest: ModelManifest(
                manifestVersion: 3,
                generatedAt: "2026-07-25T00:00:00Z",
                models: [first, second],
                presentationGraph: try fixtureV3PresentationGraph()
            )
        )
        XCTAssertEqual(unresolved.records.first?.model.id, customID)
        XCTAssertEqual(
            unresolved.placement(forArtifactID: customID),
            .custom
        )

        let resolved = ModelArtifactPlacementResolver().reconcile(
            records: [record],
            trustedManifest: ModelManifest(
                manifestVersion: 3,
                generatedAt: "2026-07-25T00:00:00Z",
                models: [first, second],
                presentationGraph: try fixtureV3PresentationGraph(),
                artifactAliases: [
                    ModelArtifactAlias(
                        aliasArtifactID: second.id,
                        canonicalArtifactID: first.id
                    ),
                ]
            )
        )
        XCTAssertEqual(resolved.records.first?.model.id, first.id)
        XCTAssertEqual(
            resolved.placement(forArtifactID: first.id),
            .curated
        )
    }

    func testLegacyTruncatedCustomIdentityMigratesToFullDigestNamespace() throws {
        let source = try fixtureModel()
        let legacyID = "custom-whisper-\(source.files[0].sha256.prefix(16))"
        let record = InstalledModelRecord(
            model: copy(source, id: legacyID, displayName: "Imported Before V3"),
            installedAt: "2026-07-20T00:00:00Z",
            localFilesByManifestFilename: [
                "model.bin": "/Models/\(legacyID)/model.bin",
            ]
        )

        let snapshot = ModelArtifactPlacementResolver().reconcile(
            records: [record],
            trustedManifest: ModelManifest(
                manifestVersion: 3,
                generatedAt: "2026-07-25T00:00:00Z",
                models: [],
                presentationGraph: try fixtureV3PresentationGraph()
            )
        )

        let migrated = try XCTUnwrap(snapshot.records.first)
        let expectedID = "custom-sha256-\(source.files[0].sha256)"
        XCTAssertEqual(migrated.model.id, expectedID)
        XCTAssertEqual(migrated.storageModelID, legacyID)
        XCTAssertEqual(
            migrated.identityHistory.customImport?.localNames,
            ["Imported Before V3"]
        )
        XCTAssertEqual(
            snapshot.placement(forArtifactID: expectedID),
            .custom
        )
    }

    func testLegacyTruncatedMigrationDoesNotCollideWithInstalledFullDigestIdentity() throws {
        let source = try fixtureModel()
        let digest = try XCTUnwrap(source.artifactTypedDigests().first)
        let legacyID = "custom-whisper-\(digest.value.prefix(16))"
        let fullID = CustomWhisperModelImporter.importedModelIDPrefix
            + digest.value
        let legacy = InstalledModelRecord(
            model: copy(source, id: legacyID, displayName: "Legacy Import"),
            installedAt: "2026-07-20T00:00:00Z",
            localFilesByManifestFilename: [
                "model.bin": "/Models/\(legacyID)/model.bin",
            ]
        )
        let current = InstalledModelRecord(
            model: copy(source, id: fullID, displayName: "Current Import"),
            installedAt: "2026-07-21T00:00:00Z",
            localFilesByManifestFilename: [
                "model.bin": "/Models/\(fullID)/model.bin",
            ],
            identityHistory: InstalledModelIdentityHistory(
                customImport: CustomModelImportHistory(
                    contentDigest: digest,
                    localNames: ["Current Import"],
                    sourceFilenames: ["current.ggml"]
                )
            )
        )

        let snapshot = ModelArtifactPlacementResolver().reconcile(
            records: [legacy, current],
            trustedManifest: nil
        )

        XCTAssertEqual(
            Set(snapshot.records.map(\.model.id)),
            [legacyID, fullID]
        )
        XCTAssertEqual(
            snapshot.placement(forArtifactID: legacyID),
            .legacy
        )
        XCTAssertEqual(
            snapshot.placement(forArtifactID: fullID),
            .custom
        )
    }

    private func fixtureModel() throws -> ModelEntry {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "manifest.json",
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try XCTUnwrap(
            ModelManifest.decode(Data(contentsOf: url)).models.first
        )
    }

    private func copy(
        _ model: ModelEntry,
        id: String,
        displayName: String
    ) -> ModelEntry {
        ModelEntry(
            id: id,
            displayName: displayName,
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
            installationStorage: try! XCTUnwrap(model.installationStorage),
            benchmark: model.benchmark
        )
    }

    private func fixtureV3PresentationGraph() throws -> ModelCatalogPresentationGraph {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "manifest_v3.json",
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try XCTUnwrap(
            ModelManifest.decode(Data(contentsOf: url)).presentationGraph
        )
    }
}
