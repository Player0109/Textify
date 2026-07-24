import Foundation
import XCTest
@testable import Textify
import TextifyModels

final class ModelCatalogExperienceTests: XCTestCase {
    func testCombinesTrustedInstalledActiveAndTransferStateIntoRows() throws {
        let downloadable = model(id: "downloadable")
        let active = model(id: "active")
        let noLongerCurated = model(id: "no-longer-curated")
        let transfer = DownloadState(
            modelID: downloadable.id,
            phase: .downloading,
            bytesDownloaded: 25,
            totalBytes: 100
        )

        let experience = ModelCatalogExperience(
            trustedModels: [downloadable, active],
            installedRecords: [
                installed(active),
                installed(noLongerCurated),
            ],
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID: active.id,
                voiceCleaningModelID: nil
            ),
            transferState: transfer
        )

        XCTAssertEqual(experience.rows.map(\.id), [active.id, downloadable.id, noLongerCurated.id])

        let activeRow = try XCTUnwrap(experience.rows.first { $0.id == active.id })
        XCTAssertTrue(activeRow.isInstalled)
        XCTAssertTrue(activeRow.isActive)
        XCTAssertTrue(activeRow.model.isCurated)
        XCTAssertNil(activeRow.installState)
        XCTAssertEqual(activeRow.actions, [.reinstall, .delete, .details])

        let downloadingRow = try XCTUnwrap(experience.rows.first { $0.id == downloadable.id })
        XCTAssertFalse(downloadingRow.isInstalled)
        XCTAssertFalse(downloadingRow.isActive)
        XCTAssertEqual(downloadingRow.installState, transfer)
        XCTAssertEqual(downloadingRow.install?.title, "Downloading model")
        XCTAssertEqual(downloadingRow.install?.percentText, "25%")
        XCTAssertEqual(downloadingRow.install?.progressValue, 0.25)
        XCTAssertTrue(downloadingRow.install?.detailText.contains("25") == true)
        XCTAssertTrue(downloadingRow.install?.detailText.contains("100") == true)
        XCTAssertEqual(downloadingRow.actions, [.cancelInstall, .details])

        let localRow = try XCTUnwrap(experience.rows.first { $0.id == noLongerCurated.id })
        XCTAssertTrue(localRow.isInstalled)
        XCTAssertFalse(localRow.isActive)
        XCTAssertFalse(localRow.model.isCurated)
        XCTAssertNil(localRow.installState)
        XCTAssertEqual(localRow.actions, [.use, .reinstall, .delete, .details])
    }

    func testUsesPurposeSpecificActivePreference() throws {
        let transcription = model(id: "transcription")
        let cleaner = model(id: "cleaner", purpose: .voiceCleaning)

        let experience = ModelCatalogExperience(
            trustedModels: [cleaner, transcription],
            installedRecords: [
                installed(cleaner),
                installed(transcription),
            ],
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID: transcription.id,
                voiceCleaningModelID: cleaner.id
            ),
            transferState: nil
        )

        XCTAssertEqual(experience.rows.map(\.id), [transcription.id, cleaner.id])

        let transcriptionRow = try XCTUnwrap(experience.rows.first { $0.id == transcription.id })
        XCTAssertTrue(transcriptionRow.isActive)
        XCTAssertFalse(transcriptionRow.actions.contains(.disable))

        let cleanerRow = try XCTUnwrap(experience.rows.first { $0.id == cleaner.id })
        XCTAssertTrue(cleanerRow.isActive)
        XCTAssertTrue(cleanerRow.actions.contains(.disable))
        XCTAssertFalse(cleanerRow.actions.contains(.use))
    }

    func testAppliesQueryAfterCombiningCatalogAndLocalState() {
        let mlx = model(id: "mlx", engine: .mlxAudio)
        let gguf = model(id: "gguf-q5", engine: .transcribeCpp)

        let experience = ModelCatalogExperience(
            trustedModels: [mlx, gguf],
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(format: .gguf, precision: .fiveBit)
        )

        XCTAssertEqual(experience.rows.map(\.id), [gguf.id])
    }

    func testPreservesCurrentFallbackWhenTrustedModelsAreUnavailable() {
        let experience = ModelCatalogExperience(
            trustedModels: [],
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )

        XCTAssertEqual(
            experience.rows.map(\.id),
            ProductionModelPresentation.visibleCatalog.map(\.id)
        )
    }

    func testFailedTransferOffersRetryOnlyOnItsExactRow() throws {
        let failed = model(id: "failed")
        let other = model(id: "other")
        let transfer = DownloadState(
            modelID: failed.id,
            phase: .failed,
            message: "Network unavailable"
        )

        let experience = ModelCatalogExperience(
            trustedModels: [failed, other],
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: transfer
        )

        let failedRow = try XCTUnwrap(experience.rows.first { $0.id == failed.id })
        XCTAssertEqual(failedRow.installState, transfer)
        XCTAssertEqual(failedRow.install?.title, "Install failed")
        XCTAssertEqual(failedRow.install?.detailText, "Network unavailable")
        XCTAssertEqual(failedRow.actions, [.retryInstall, .details])

        let otherRow = try XCTUnwrap(experience.rows.first { $0.id == other.id })
        XCTAssertNil(otherRow.installState)
        XCTAssertEqual(otherRow.actions, [.install, .details])
    }

    func testPreservesSignedBenchmarkRatingsInUserVisiblePresentation() throws {
        let manifest = try ModelManifest.decode(
            Data(contentsOf: repositoryRoot.appendingPathComponent("models/manifest.json"))
        )
        let measured = try XCTUnwrap(
            manifest.models.first {
                $0.benchmark?.speed != nil
            }
        )

        let experience = ModelCatalogExperience(
            trustedModels: [measured],
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )

        let row = try XCTUnwrap(experience.rows.first)
        XCTAssertEqual(row.model.qualityLabel, measured.benchmark?.quality.label)
        XCTAssertEqual(row.model.qualityScore, measured.benchmark?.quality.score)
        XCTAssertEqual(row.model.speedLabel, measured.benchmark?.speed?.label)
        XCTAssertEqual(row.model.speedScore, measured.benchmark?.speed?.score)
        XCTAssertNotNil(row.model.qualityEvidenceDescription)
        XCTAssertNotNil(row.model.speedEvidenceDescription)
    }

    @MainActor
    func testSignedV3FixtureReachesFamilyCheckpointAndExactArtifactPresentation() async throws {
        let fixtureDirectory = repositoryRoot
            .appendingPathComponent("Tests/TextifyModelsTests/Fixtures/Models")
        let manifestData = try Data(
            contentsOf: fixtureDirectory.appendingPathComponent("manifest_v3.json")
        )
        let publicKey = try String(
            contentsOf: fixtureDirectory
                .appendingPathComponent("manifest_v3.fixture-public-key.base64"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "fixture-v3-key",
                publicKeyBase64: publicKey
            )
        ])
        let manifest = try verifier.verify(
            manifestData: manifestData,
            signatureData: Data(
                contentsOf: fixtureDirectory.appendingPathComponent("manifest_v3.json.sig")
            )
        )
        try ProductionModelPolicy.validateProductionManifest(manifest)
        let coordinator = ModelCatalogCoordinator(loadOperation: { manifest })
        await coordinator.refresh()

        let experience = ModelCatalogExperience(
            trustedManifest: coordinator.manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )

        XCTAssertEqual(experience.families.map(\.id), ["family.whisper"])
        let family = try XCTUnwrap(experience.families.first)
        XCTAssertEqual(
            family.checkpoints.map(\.id),
            ["checkpoint.whisper.small", "checkpoint.whisper.tiny"]
        )
        XCTAssertEqual(family.checkpoints.map(\.artifacts.count), [2, 1])

        let multiVariant = family.checkpoints[0]
        XCTAssertEqual(
            multiVariant.artifacts.map(\.id),
            ["whisper-small-q5_1", "whisper-small-q8_0"]
        )
        XCTAssertEqual(multiVariant.artifacts[0].metadata.artifactFormat, .ggml)
        XCTAssertEqual(multiVariant.artifacts[0].metadata.numericFormat, .q5_1)
        XCTAssertEqual(multiVariant.artifacts[0].row.model.id, "whisper-small-q5_1")

        let singleVariant = family.checkpoints[1]
        XCTAssertEqual(singleVariant.artifacts.map(\.id), ["whisper-tiny-f16"])
        XCTAssertEqual(singleVariant.artifacts[0].metadata.numericFormat, .f16)
    }

    func testProductionV3ResolvesV2ReceiptAndActivePreferenceToSameExactArtifact() throws {
        let fixtures = repositoryRoot
            .appendingPathComponent("Tests/TextifyModelsTests/Fixtures/Models")
        let v2 = try ModelManifest.decode(
            Data(
                contentsOf: fixtures
                    .appendingPathComponent("manifest_v2.production-migration.json")
            )
        )
        let v3 = try ModelManifest.decode(
            Data(contentsOf: repositoryRoot.appendingPathComponent("models/manifest.json"))
        )
        let activeID = "qwen3-asr-1.7b-bf16"
        let previousModel = try XCTUnwrap(v2.models.first { $0.id == activeID })
        let record = InstalledModelRecord(
            model: previousModel,
            installedAt: "2026-07-23T00:00:00Z",
            localFilesByManifestFilename: Dictionary(
                uniqueKeysWithValues: previousModel.files.map {
                    ($0.filename, "/Models/\(activeID)/\($0.relativePath ?? $0.filename)")
                }
            )
        )

        let experience = ModelCatalogExperience(
            trustedManifest: v3,
            installedRecords: [record],
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID: activeID,
                voiceCleaningModelID: nil
            ),
            transferState: nil
        )

        let exactArtifact = try XCTUnwrap(
            experience.families
                .flatMap(\.checkpoints)
                .flatMap(\.artifacts)
                .first { $0.id == activeID }
        )
        XCTAssertEqual(exactArtifact.row.model.id, record.model.id)
        XCTAssertTrue(exactArtifact.row.isInstalled)
        XCTAssertTrue(exactArtifact.row.isActive)
        XCTAssertEqual(experience.rows.filter(\.isActive).map(\.id), [activeID])
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func installed(_ model: ModelEntry) -> InstalledModelRecord {
        InstalledModelRecord(
            model: model,
            installedAt: "2026-07-23T00:00:00Z",
            localFilesByManifestFilename: [
                model.files[0].filename: "/tmp/\(model.files[0].filename)",
            ]
        )
    }

    private func model(
        id: String,
        purpose: ModelPurpose = .transcription,
        engine: TranscriptionEngine = .whisperCpp
    ) -> ModelEntry {
        let filename = engine == .mlxAudio ? "weights.safetensors" : "\(id).gguf"
        return ModelEntry(
            id: id,
            displayName: id,
            tier: "experimental",
            description: "\(id) description",
            sizeBytes: 100,
            files: [
                ModelFile(
                    filename: filename,
                    url: "https://example.com/\(filename)",
                    sha256: String(repeating: "a", count: 64),
                    sizeBytes: 100
                ),
            ],
            licenses: [
                ModelLicense(
                    scope: "model",
                    spdxId: "MIT",
                    name: "MIT",
                    licenseTextUrl: "https://example.com/license"
                ),
            ],
            provenance: ModelProvenance(
                sourceName: "Fixture",
                sourceUrl: "https://example.com/source",
                sourceRevision: String(repeating: "b", count: 40),
                sourceFile: filename,
                originalModelName: id,
                originalModelUrl: "https://example.com/model",
                mirroredBy: "Fixture",
                mirroredAt: "2026-07-23T00:00:00Z"
            ),
            runtimeParameters: .legacyEnglishWhisper,
            hallucinationThresholds: HallucinationThresholds(
                noSpeechProbabilityMax: 0.6,
                avgLogProbabilityMin: -1,
                compressionRatioMax: 2.4
            ),
            minAppVersion: "1.0.0",
            runtime: ModelRuntimeDescriptor(
                engine: engine,
                variant: id,
                accelerator: .metalGPU,
                artifactLayout: engine == .mlxAudio ? .modelDirectory : .singleFile
            ),
            capabilities: .legacyEnglishWhisper,
            presentation: nil,
            purpose: purpose
        )
    }
}
