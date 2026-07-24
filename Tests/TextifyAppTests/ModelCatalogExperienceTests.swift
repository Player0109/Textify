import Foundation
import Observation
import XCTest
@testable import Textify
import TextifyModels

final class ModelCatalogExperienceTests: XCTestCase {
    func testStateTokensPreserveInstalledReadyActiveAndNeedsRepairDimensions() throws {
        let active = model(id: "active")
        let installedOnly = model(id: "installed-only")
        let needsRepair = model(id: "needs-repair")
        let experience = ModelCatalogExperience(
            trustedModels: [active, installedOnly, needsRepair],
            installedRecords: [
                installed(active),
                installed(installedOnly),
                installed(needsRepair),
            ],
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID: active.id,
                voiceCleaningModelID: nil
            ),
            transferState: nil,
            managedReadinessByModelID: [
                active.id: .ready,
                installedOnly.id: .installed,
                needsRepair.id: .needsRepair,
            ]
        )

        XCTAssertEqual(
            experience.rows.first { $0.id == active.id }?.stateTokens,
            [.installed, .ready, .active]
        )
        XCTAssertEqual(
            experience.rows.first { $0.id == installedOnly.id }?.stateTokens,
            [.installed]
        )
        XCTAssertEqual(
            experience.rows.first { $0.id == needsRepair.id }?.stateTokens,
            [.installed, .needsRepair]
        )
        XCTAssertFalse(
            try XCTUnwrap(
                experience.rows.first { $0.id == installedOnly.id }
            ).actions.contains(.use)
        )
        XCTAssertFalse(
            try XCTUnwrap(
                experience.rows.first { $0.id == needsRepair.id }
            ).actions.contains(.use)
        )
        let onboarding = OnboardingModelCatalog(
            experience: experience,
            selectedModelID: needsRepair.id
        )
        XCTAssertEqual(onboarding.action(for: needsRepair.id), .reinstall)
    }

    func testInstalledIncompatibleArtifactKeepsReadinessAndCompatibilityTokens() throws {
        let manifest = try v3FixtureManifest(
            recommendedMinimumMemoryBytes: 17_179_869_184
        )
        let resolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_589_934_592
            )
        )
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            compatibilityResolver: resolver,
            installedRecords: [installed(model)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            managedReadinessByModelID: [model.id: .ready]
        )

        let row = try XCTUnwrap(experience.rows.first { $0.id == model.id })
        XCTAssertEqual(
            row.stateTokens,
            [.installed, .ready, .incompatible]
        )
        XCTAssertTrue(row.actions.contains(.use))
        XCTAssertFalse(row.compatibility.allowsModelOperations)
    }

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

    func testPurposeQueryFiltersRowsAndSignedHierarchyWithoutInferringFromNames() throws {
        let manifest = try productionManifest()

        let transcription = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(purpose: .transcription)
        )
        let cleaning = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(purpose: .voiceCleaning)
        )

        XCTAssertFalse(transcription.rows.isEmpty)
        XCTAssertTrue(transcription.rows.allSatisfy { $0.model.purpose == .transcription })
        XCTAssertTrue(transcription.families.allSatisfy { $0.metadata.purpose == .transcription })
        XCTAssertEqual(
            Set(cleaning.rows.map(\.id)),
            [
                "mossformer2-se-fp32",
                "mossformer2-se-fp16",
                "mossformer2-se-int8",
            ]
        )
        XCTAssertTrue(cleaning.rows.allSatisfy { $0.model.purpose == .voiceCleaning })
        XCTAssertTrue(cleaning.families.allSatisfy { $0.metadata.purpose == .voiceCleaning })
    }

    func testCompatibilityResolverUsesSignedRequirementsForSettingsAndOnboarding() throws {
        let manifest = try productionManifest()
        let resolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_589_934_592
            )
        )
        let compatibleIDs = try XCTUnwrap(resolver.compatibleModelIDs(in: manifest))

        XCTAssertTrue(compatibleIDs.contains("ggml-small.en-q5_1"))
        XCTAssertFalse(compatibleIDs.contains("parakeet-tdt-0.6b-v3"))
        XCTAssertFalse(compatibleIDs.contains("parakeet-rnnt-1.1b"))

        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(
                purpose: .transcription,
                compatibleModelIDs: compatibleIDs
            )
        )
        let onboarding = OnboardingModelCatalog(experience: experience)

        XCTAssertEqual(Set(experience.rows.map(\.id)), Set(onboarding.choices.map(\.id)))
        XCTAssertFalse(onboarding.choices.contains { $0.id == "parakeet-rnnt-1.1b" })
    }

    func testIncompatibleRecommendationStaysVisibleAndDisclosesExactSignedFallback() throws {
        let manifest = try v3FixtureManifest(
            recommendedMinimumMemoryBytes: 16_000_000_000
        )
        let resolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_000_000_000
            )
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            compatibilityResolver: resolver,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            experience.families.first?.checkpoints.first
        )
        let recommended = try XCTUnwrap(
            checkpoint.artifacts.first { $0.id == "whisper-small-q5_1" }
        )
        let fallback = try XCTUnwrap(
            checkpoint.artifacts.first { $0.id == "whisper-small-q8_0" }
        )

        XCTAssertEqual(
            checkpoint.artifacts.map(\.id),
            ["whisper-small-q5_1", "whisper-small-q8_0"],
            "Fallback order must not replace signed presentation order."
        )
        XCTAssertEqual(
            recommended.row.compatibility,
            .incompatible(
                .insufficientMemory(
                    requiredBytes: 16_000_000_000,
                    availableBytes: 8_000_000_000
                )
            )
        )
        XCTAssertFalse(recommended.row.compatibility.allowsModelOperations)
        XCTAssertTrue(recommended.row.actions.contains(.install))
        XCTAssertEqual(fallback.row.compatibility, .compatible)
        XCTAssertEqual(
            checkpoint.defaultInstallArtifact?.id,
            "whisper-small-q8_0"
        )
        XCTAssertEqual(
            checkpoint.resolution?.fallback?.fallbackArtifactID,
            "whisper-small-q8_0"
        )
        let comparisons = checkpoint.variantComparisons
        XCTAssertEqual(
            comparisons.first { $0.id == recommended.id }?.isActionable,
            false
        )
        XCTAssertEqual(
            comparisons.first { $0.id == fallback.id }?.isFallback,
            true
        )

        let inspector = try XCTUnwrap(
            experience.inspectorPresentation(
                for: .checkpoint("checkpoint.whisper.small")
            )
        )
        guard case let .checkpoint(checkpointInspector) = inspector else {
            return XCTFail("Checkpoint selection must disclose fallback resolution.")
        }
        XCTAssertEqual(checkpointInspector.referenceCompatibility, "Incompatible")
        XCTAssertEqual(
            checkpointInspector.defaultInstallArtifactID,
            "whisper-small-q8_0"
        )
        XCTAssertEqual(checkpointInspector.defaultInstallArtifactName, "Q8_0")

        let onboarding = OnboardingModelCatalog(experience: experience)
        XCTAssertEqual(onboarding.selectedModelID, "whisper-small-q8_0")
        XCTAssertEqual(onboarding.action(for: "whisper-small-q8_0"), .install)
        XCTAssertEqual(
            onboarding.action(for: "whisper-small-q5_1"),
            .unavailable
        )
        XCTAssertTrue(
            onboarding.selectionNotice?.contains("whisper-small-q5_1") == true
        )
        XCTAssertTrue(
            onboarding.selectionNotice?.contains("whisper-small-q8_0") == true
        )
        XCTAssertTrue(
            onboarding.selectionNotice?.contains("Whisper.cpp with GPU via Metal")
                == true
        )
    }

    func testOnboardingUsesSignedRecommendationThenRequiresExplicitActivation() throws {
        let manifest = try productionManifest()
        let recommendedID = try XCTUnwrap(
            manifest.presentationGraph?.families
                .first { $0.purpose == .transcription }?
                .checkpointIDs.first
        )
        let recommendedArtifactID = try XCTUnwrap(
            manifest.presentationGraph?.checkpoints
                .first { $0.id == recommendedID }?
                .recommendedArtifactID
        )
        let recommendedModel = try XCTUnwrap(
            manifest.models.first { $0.id == recommendedArtifactID }
        )
        let uninstalledExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(purpose: .transcription)
        )
        let uninstalledCatalog = OnboardingModelCatalog(
            experience: uninstalledExperience
        )

        XCTAssertEqual(uninstalledCatalog.selectedModelID, recommendedArtifactID)
        XCTAssertEqual(
            uninstalledCatalog.action(for: recommendedArtifactID),
            .install
        )

        let installedExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(recommendedModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(purpose: .transcription)
        )
        let installedCatalog = OnboardingModelCatalog(
            experience: installedExperience,
            selectedModelID: recommendedArtifactID
        )

        XCTAssertEqual(
            installedCatalog.action(for: recommendedArtifactID),
            .activate
        )

        let activeExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(recommendedModel)],
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID: recommendedArtifactID
            ),
            transferState: nil,
            query: ModelCatalogQuery(purpose: .transcription)
        )
        let activeCatalog = OnboardingModelCatalog(
            experience: activeExperience,
            selectedModelID: recommendedArtifactID
        )

        XCTAssertEqual(activeCatalog.action(for: recommendedArtifactID), .active)
    }

    func testOnboardingScopesTransferRecoveryToTheSelectedExactArtifact() {
        let failed = model(id: "failed")
        let other = model(id: "other")
        let experience = ModelCatalogExperience(
            trustedModels: [failed, other],
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: DownloadState(
                modelID: failed.id,
                phase: .failed,
                message: "Network unavailable"
            )
        )
        let onboarding = OnboardingModelCatalog(
            experience: experience,
            selectedModelID: other.id
        )

        XCTAssertEqual(onboarding.action(for: failed.id), .retryInstall)
        XCTAssertEqual(onboarding.action(for: other.id), .install)
        XCTAssertEqual(onboarding.selectedModelID, other.id)
        XCTAssertNil(onboarding.transferState(for: onboarding.selectedModelID))
        XCTAssertEqual(
            onboarding.transferState(for: failed.id),
            experience.rows.first { $0.id == failed.id }?.installState
        )
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

    func testDoesNotInventCatalogChoicesWhenTrustedModelsAreUnavailable() {
        let experience = ModelCatalogExperience(
            trustedModels: [],
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )

        XCTAssertTrue(experience.rows.isEmpty)
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
        let manifest = try signedV3FixtureManifest()
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

    func testCollapsedHierarchyShowsNonselectableFamilyMultiVariantCheckpointAndSingleLeaf() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let state = ModelCatalogHierarchyState()

        let rows = state.visibleRows(in: experience)

        XCTAssertEqual(
            rows.map(\.id),
            [
                .family("family.whisper"),
                .checkpoint("checkpoint.whisper.small"),
                .exactArtifact("whisper-tiny-f16"),
            ]
        )
        guard case .family = rows[0].content else {
            return XCTFail("The first row should be a nonselectable family heading.")
        }
        guard case .checkpoint = rows[1].content else {
            return XCTFail("The multi-variant checkpoint should remain a parent row.")
        }
        guard case let .exactArtifact(_, artifact, isSingleVariant) = rows[2].content else {
            return XCTFail("The single-variant checkpoint should render as an exact leaf.")
        }
        XCTAssertTrue(isSingleVariant)
        XCTAssertEqual(artifact.row.actions, [.install, .details])
    }

    func testDisclosureDoesNotSelectAndExpandedChildrenExposeExactSelection() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(experience.families.first?.checkpoints.first)
        var state = ModelCatalogHierarchyState()
        state.select(.checkpoint(checkpoint.id))

        state.toggleExpansion(of: checkpoint)

        XCTAssertEqual(state.selection, .checkpoint(checkpoint.id))
        XCTAssertEqual(
            state.visibleRows(in: experience).map(\.id),
            [
                .family("family.whisper"),
                .checkpoint("checkpoint.whisper.small"),
                .exactArtifact("whisper-small-q5_1"),
                .exactArtifact("whisper-small-q8_0"),
                .exactArtifact("whisper-tiny-f16"),
            ]
        )
    }

    func testFilteringToOneVisibleArtifactKeepsAnIntrinsicallyMultiVariantCheckpoint() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(precision: .fiveBit)
        )
        let checkpoint = try XCTUnwrap(experience.families.first?.checkpoints.first)
        var state = ModelCatalogHierarchyState()

        XCTAssertEqual(checkpoint.metadata.artifactIDs.count, 2)
        XCTAssertEqual(checkpoint.artifacts.map(\.id), ["whisper-small-q5_1"])
        XCTAssertEqual(
            state.visibleRows(in: experience).map(\.id),
            [
                .family("family.whisper"),
                .checkpoint("checkpoint.whisper.small"),
            ]
        )

        state.toggleExpansion(of: checkpoint)

        XCTAssertEqual(
            state.visibleRows(in: experience).map(\.id),
            [
                .family("family.whisper"),
                .checkpoint("checkpoint.whisper.small"),
                .exactArtifact("whisper-small-q5_1"),
            ]
        )
    }

    func testCollapsingSelectedChildPromotesSelectionToCheckpoint() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(experience.families.first?.checkpoints.first)
        var state = ModelCatalogHierarchyState()
        state.toggleExpansion(of: checkpoint)
        state.select(.exactArtifact("whisper-small-q8_0"))

        state.toggleExpansion(of: checkpoint)

        XCTAssertEqual(state.selection, .checkpoint(checkpoint.id))
        XCTAssertFalse(
            state.visibleRows(in: experience)
                .contains { $0.id == .exactArtifact("whisper-small-q8_0") }
        )
    }

    func testSelectionIsSingleAndSurvivesOrdinaryArtifactStateUpdates() throws {
        let manifest = try signedV3FixtureManifest()
        let initialExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            initialExperience.families.first?.checkpoints.first
        )
        var state = ModelCatalogHierarchyState()
        state.toggleExpansion(of: checkpoint)
        state.select(.checkpoint(checkpoint.id))
        state.select(.exactArtifact("whisper-small-q5_1"))

        let installedModel = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let updatedExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        state.reconcile(with: updatedExperience)

        XCTAssertEqual(state.selection, .exactArtifact("whisper-small-q5_1"))
        XCTAssertTrue(state.expandedCheckpointIDs.contains(checkpoint.id))
        let installedRow = try XCTUnwrap(
            state.visibleRows(in: updatedExperience)
                .first { $0.id == .exactArtifact("whisper-small-q5_1") }
        )
        guard case let .exactArtifact(_, artifact, _) = installedRow.content else {
            return XCTFail("The selected exact artifact row should remain visible.")
        }
        XCTAssertTrue(artifact.row.isInstalled)
    }

    func testCheckpointInspectorShowsAggregateTruthAndReferenceEvidence() throws {
        let manifest = try signedV3FixtureManifest()
        let installedModel = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID: installedModel.id
            ),
            transferState: nil
        )

        let inspector = try XCTUnwrap(
            experience.inspectorPresentation(
                for: .checkpoint("checkpoint.whisper.small")
            )
        )
        guard case let .checkpoint(checkpoint) = inspector else {
            return XCTFail("Checkpoint selection must publish checkpoint truth.")
        }

        XCTAssertEqual(checkpoint.id, "checkpoint.whisper.small")
        XCTAssertEqual(checkpoint.displayName, "Whisper Small")
        XCTAssertEqual(checkpoint.description, "Balanced English speech recognition.")
        XCTAssertEqual(checkpoint.referenceArtifactID, "whisper-small-q5_1")
        XCTAssertEqual(checkpoint.referenceArtifactName, "Q5_1")
        XCTAssertEqual(checkpoint.referenceQuality, "Unrated")
        XCTAssertEqual(checkpoint.referenceSpeed, "Unrated")
        XCTAssertEqual(checkpoint.aggregateState, "1 of 2 variants installed • Q5_1 active")
        XCTAssertEqual(checkpoint.languages, "English")
        XCTAssertEqual(checkpoint.capabilities, "Speech recognition")
    }

    func testCheckpointInspectorAggregatesSignedLanguageCodesAcrossVariants() throws {
        let manifest = try ModelManifest.decode(
            Data(contentsOf: repositoryRoot.appendingPathComponent("models/manifest.json"))
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )

        let inspector = try XCTUnwrap(
            experience.inspectorPresentation(
                for: .checkpoint("checkpoint.openai.whisper-large-v3-turbo")
            )
        )
        guard case let .checkpoint(checkpoint) = inspector else {
            return XCTFail("The production checkpoint must expose aggregate truth.")
        }

        XCTAssertEqual(checkpoint.languages, "English, Hindi")
    }

    func testCheckpointInspectorReportsTerminalTransferStateTruthfully() throws {
        let manifest = try signedV3FixtureManifest()
        let cases: [(DownloadPhase, String)] = [
            (.failed, "No variants installed • Install failed"),
            (.cancelled, "No variants installed • Install cancelled"),
            (.interrupted, "No variants installed • Download interrupted"),
        ]

        for (phase, expectedState) in cases {
            let experience = ModelCatalogExperience(
                trustedManifest: manifest,
                installedRecords: [],
                activePreferences: ModelCatalogActivePreferences(),
                transferState: DownloadState(
                    modelID: "whisper-small-q5_1",
                    phase: phase
                )
            )

            let inspector = try XCTUnwrap(
                experience.inspectorPresentation(
                    for: .checkpoint("checkpoint.whisper.small")
                )
            )
            guard case let .checkpoint(checkpoint) = inspector else {
                return XCTFail("Checkpoint selection must publish checkpoint truth.")
            }
            XCTAssertEqual(checkpoint.aggregateState, expectedState)
        }
    }

    func testExactArtifactInspectorShowsOperationalSignedAndLocalTruth() throws {
        let manifest = try signedV3FixtureManifest()
        let installedModel = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID: installedModel.id
            ),
            transferState: DownloadState(
                modelID: installedModel.id,
                phase: .downloading,
                bytesDownloaded: 10,
                totalBytes: 100
            )
        )

        let inspector = try XCTUnwrap(
            experience.inspectorPresentation(
                for: .exactArtifact(installedModel.id)
            )
        )
        guard case let .exactArtifact(artifact) = inspector else {
            return XCTFail("Exact Artifact selection must publish operational truth.")
        }

        XCTAssertEqual(artifact.id, "whisper-small-q5_1")
        XCTAssertEqual(artifact.checkpointName, "Whisper Small")
        XCTAssertEqual(artifact.displayName, "Q5_1")
        XCTAssertEqual(artifact.artifactFormat, "GGML")
        XCTAssertEqual(artifact.numericFormat, "Q5_1")
        XCTAssertEqual(artifact.runtime, "Whisper.cpp")
        XCTAssertEqual(artifact.computeRoute, "GPU via Metal")
        XCTAssertEqual(
            artifact.compatibility,
            "Textify 1.1.0+ • macOS 14.0.0+ • arm64 • 1 GB memory"
        )
        XCTAssertEqual(artifact.transferSize, "33 bytes")
        XCTAssertEqual(
            artifact.localState,
            "Installed • Ready • Active • Downloading model"
        )
        let comparison = try XCTUnwrap(
            experience.families
                .flatMap(\.checkpoints)
                .flatMap(\.variantComparisons)
                .first(where: { $0.id == installedModel.id })
        )
        XCTAssertEqual(
            comparison.state,
            "Installed • Ready • Active • Downloading model"
        )
        XCTAssertEqual(artifact.qualityEvidence, "Unrated")
        XCTAssertEqual(artifact.speedEvidence, "Unrated")
        XCTAssertEqual(
            artifact.provenance,
            "Fixture • Whisper Small • revision 1234567890ab • model.bin"
        )
        XCTAssertEqual(artifact.license, "MIT — MIT License (model)")
        XCTAssertTrue(artifact.canVerify)
        XCTAssertEqual(
            artifact.localInspectionRequest?.expectedFiles.map(\.relativePath),
            ["model.bin"]
        )
    }

    func testSingleVariantSelectionOpensExactArtifactInspector() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )

        let inspector = try XCTUnwrap(
            experience.inspectorPresentation(
                for: .exactArtifact("whisper-tiny-f16")
            )
        )
        guard case let .exactArtifact(artifact) = inspector else {
            return XCTFail("A single-variant leaf must inspect its exact artifact.")
        }

        XCTAssertEqual(artifact.checkpointName, "Whisper Tiny")
        XCTAssertEqual(artifact.displayName, "F16")
        XCTAssertEqual(artifact.numericFormat, "F16")
    }

    func testVariantComparisonRetainsExactSignedTerminology() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try productionManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            experience.families
                .flatMap(\.checkpoints)
                .first { $0.id == "checkpoint.qwen.qwen3-asr-1.7b" }
        )
        let variants = checkpoint.variantComparisons

        XCTAssertEqual(
            variants.map(\.numericFormat),
            ["8bit", "BF16", "Q8_0", "Q5_K_M"]
        )
        XCTAssertEqual(
            variants.map(\.artifactFormat),
            ["MLX", "GGUF", "GGUF", "GGUF"]
        )
        XCTAssertEqual(
            variants.map(\.runtime),
            ["MLX Audio", "transcribe.cpp", "transcribe.cpp", "transcribe.cpp"]
        )
        XCTAssertEqual(
            Set(variants.map(\.computeRoute)),
            ["GPU via Metal"]
        )
        XCTAssertFalse(variants.map(\.numericFormat).contains("FP16"))
    }

    func testVariantComparisonUsesOnlyMatchingSignedEvidenceGroups() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try productionManifest(
                comparisonGroupOverride: (
                    artifactID: "qwen3-asr-1.7b-q5-k-m",
                    groupID: "different-evidence-group"
                )
            ),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            experience.families
                .flatMap(\.checkpoints)
                .first { $0.id == "checkpoint.qwen.qwen3-asr-1.7b" }
        )
        let reference = try XCTUnwrap(
            checkpoint.variantComparisons.first {
                $0.id == checkpoint.metadata.recommendedArtifactID
            }
        )
        XCTAssertEqual(reference.quality, .reference(label: "High"))
        XCTAssertEqual(reference.speed, .reference(label: "Balanced"))

        let comparable = try XCTUnwrap(
            checkpoint.variantComparisons.first {
                $0.id == "qwen3-asr-1.7b-bf16"
            }
        )
        XCTAssertEqual(
            comparable.quality,
            .compared(label: "Highest", scoreDelta: 7)
        )
        XCTAssertEqual(
            comparable.speed,
            .compared(label: "Measured", scoreDelta: -14)
        )

        let differentGroup = try XCTUnwrap(
            checkpoint.variantComparisons.first {
                $0.id == "qwen3-asr-1.7b-q5-k-m"
            }
        )
        XCTAssertEqual(differentGroup.quality, .notComparable)
        XCTAssertEqual(differentGroup.speed, .notComparable)

        let inspector = try XCTUnwrap(
            experience.inspectorPresentation(
                for: .exactArtifact(differentGroup.id)
            )
        )
        guard case let .exactArtifact(artifact) = inspector else {
            return XCTFail("Raw signed evidence must remain inspectable.")
        }
        XCTAssertNotEqual(artifact.qualityEvidence, "Unrated")
        XCTAssertNotEqual(artifact.speedEvidence, "Unrated")
    }

    func testUnratedReferenceProducesNoInventedComparisonBaseline() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            experience.families.first?.checkpoints.first
        )

        XCTAssertEqual(
            checkpoint.variantComparisons.map(\.quality),
            [.noBaseline, .noBaseline]
        )
        XCTAssertEqual(
            checkpoint.variantComparisons.map(\.speed),
            [.noBaseline, .noBaseline]
        )
    }

    func testFilteredVariantStillComparesWithItsHiddenSignedReference() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try productionManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(precision: .sixteenBit)
        )
        let checkpoint = try XCTUnwrap(
            experience.families
                .flatMap(\.checkpoints)
                .first { $0.id == "checkpoint.qwen.qwen3-asr-1.7b" }
        )

        XCTAssertEqual(
            checkpoint.artifacts.map(\.id),
            ["qwen3-asr-1.7b-bf16"]
        )
        XCTAssertEqual(
            checkpoint.variantComparisons.map(\.quality),
            [.compared(label: "Highest", scoreDelta: 7)]
        )
    }

    func testVariantComparisonLayoutProgressivelyLabelsSecondaryFields() {
        XCTAssertTrue(ModelCatalogVariantComparisonLayout.wide.showsInlineState)
        XCTAssertTrue(ModelCatalogVariantComparisonLayout.medium.showsInlineState)
        XCTAssertFalse(ModelCatalogVariantComparisonLayout.narrow.showsInlineState)
        XCTAssertEqual(ModelCatalogVariantComparisonLayout.wide.labeledFields, [])
        XCTAssertEqual(
            ModelCatalogVariantComparisonLayout.medium.labeledFields,
            [
                .artifactFormat,
                .numericFormat,
                .quality,
                .speed,
                .size,
                .computeRoute,
            ]
        )
        XCTAssertTrue(
            ModelCatalogVariantComparisonLayout.narrow.labeledFields
                .contains(.state)
        )
    }

    func testAboutModelVariantsDefinesCanonicalTermsAndTradeoffs() {
        XCTAssertTrue(
            ModelCatalogVariantTerminology.artifactFormatExplanation
                .contains("packaging")
        )
        XCTAssertTrue(
            ModelCatalogVariantTerminology.numericFormatExplanation
                .contains("weight representation")
        )
        for effect in ["storage", "memory", "speed", "accuracy"] {
            XCTAssertTrue(
                ModelCatalogVariantTerminology.tradeoffExplanation
                    .contains(effect)
            )
        }
    }

    @MainActor
    func testInspectorCancelsAndRejectsStaleLocalDetailsAfterSelectionChanges() async throws {
        let manifest = try signedV3FixtureManifest()
        let installedModels = try [
            XCTUnwrap(manifest.models.first { $0.id == "whisper-small-q5_1" }),
            XCTUnwrap(manifest.models.first { $0.id == "whisper-small-q8_0" }),
        ]
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: installedModels.map(installed),
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let probe = InspectorDetailLoadProbe()
        let controller = ModelCatalogInspectorController(
            loadLocalDetails: { request in
                try await probe.load(request)
            }
        )

        controller.select(.exactArtifact("whisper-small-q5_1"), in: experience)
        XCTAssertEqual(
            controller.localDetailsState,
            .loading(artifactID: "whisper-small-q5_1")
        )
        await probe.waitUntilRequested("whisper-small-q5_1")

        controller.select(.exactArtifact("whisper-small-q8_0"), in: experience)
        XCTAssertEqual(
            controller.localDetailsState,
            .loading(artifactID: "whisper-small-q8_0")
        )
        await probe.waitUntilCancelled("whisper-small-q5_1")
        await probe.waitUntilRequested("whisper-small-q8_0")

        let expectedDetails = ModelCatalogArtifactLocalDetails(
            artifactID: "whisper-small-q8_0",
            allocatedBytes: 80,
            presentFileCount: 1,
            expectedFileCount: 1,
            missingRelativePaths: [],
            integrity: .notVerified
        )
        await probe.complete(
            artifactID: "whisper-small-q8_0",
            allocatedBytes: 80
        )
        await wait(
            for: .loaded(expectedDetails),
            from: controller
        )

        await probe.complete(
            artifactID: "whisper-small-q5_1",
            allocatedBytes: 50
        )

        XCTAssertEqual(
            controller.localDetailsState,
            .loaded(expectedDetails)
        )
        guard case let .exactArtifact(selected) = controller.presentation else {
            return XCTFail("The latest Exact Artifact must remain selected.")
        }
        XCTAssertEqual(selected.id, "whisper-small-q8_0")
    }

    @MainActor
    func testInspectorVerifiesOnlyAfterTheExplicitVerifyAction() async throws {
        let manifest = try signedV3FixtureManifest()
        let installedModel = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let verificationProbe = InspectorVerificationProbe()
        let controller = ModelCatalogInspectorController(
            loadLocalDetails: { request in
                ModelCatalogArtifactLocalDetails(
                    artifactID: request.artifactID,
                    allocatedBytes: 33,
                    presentFileCount: 1,
                    expectedFileCount: 1,
                    missingRelativePaths: [],
                    integrity: .notVerified
                )
            },
            verifyIntegrity: { request in
                await verificationProbe.verify(request)
            }
        )

        controller.select(.exactArtifact(installedModel.id), in: experience)
        let implicitVerificationCount = await verificationProbe.requestCount
        XCTAssertEqual(implicitVerificationCount, 0)
        XCTAssertEqual(
            controller.verificationState,
            .available(artifactID: installedModel.id)
        )

        controller.verifySelectedArtifact()
        await verificationProbe.waitUntilRequested()
        await wait(
            for: .verified(artifactID: installedModel.id),
            from: controller
        )

        let explicitVerificationCount = await verificationProbe.requestCount
        XCTAssertEqual(explicitVerificationCount, 1)
        XCTAssertEqual(
            controller.verificationState,
            .verified(artifactID: installedModel.id)
        )
    }

    func testLocalInventoryReadsMetadataWithoutClaimingFullVerification() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let artifactURL = temporaryDirectory.appendingPathComponent("model.bin")
        try Data([1, 2, 3]).write(to: artifactURL)

        let details = try await ModelCatalogArtifactInventoryReader.load(
            request: ModelCatalogArtifactInspectionRequest(
                artifactID: "fixture",
                expectedFiles: [
                    ModelCatalogArtifactInspectionRequest.ExpectedFile(
                        relativePath: "model.bin",
                        expectedSizeBytes: 3,
                        localPath: artifactURL.path
                    ),
                ]
            )
        )

        XCTAssertEqual(details.artifactID, "fixture")
        XCTAssertEqual(details.presentFileCount, 1)
        XCTAssertEqual(details.expectedFileCount, 1)
        XCTAssertGreaterThan(details.allocatedBytes, 0)
        XCTAssertEqual(details.missingRelativePaths, [])
        XCTAssertEqual(details.sizeMismatchRelativePaths, [])
        XCTAssertEqual(details.integrity, .notVerified)

        let verificationFile = ModelCatalogArtifactVerificationRequest.ExpectedFile(
            relativePath: "model.bin",
            expectedSizeBytes: 3,
            expectedSHA256: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
            localPath: artifactURL.path
        )
        try await ModelCatalogArtifactVerifier.verify(
            request: ModelCatalogArtifactVerificationRequest(
                artifactID: "fixture",
                expectedFiles: [verificationFile]
            )
        )

        do {
            try await ModelCatalogArtifactVerifier.verify(
                request: ModelCatalogArtifactVerificationRequest(
                    artifactID: "fixture",
                    expectedFiles: [
                        ModelCatalogArtifactVerificationRequest.ExpectedFile(
                            relativePath: verificationFile.relativePath,
                            expectedSizeBytes: verificationFile.expectedSizeBytes,
                            expectedSHA256: String(repeating: "0", count: 64),
                            localPath: verificationFile.localPath
                        ),
                    ]
                )
            )
            XCTFail("An explicit verification must reject a digest mismatch.")
        } catch let error as ModelCatalogArtifactVerifier.VerificationError {
            XCTAssertEqual(error, .digestMismatch)
        } catch {
            XCTFail("Expected digestMismatch, received \(error).")
        }
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

    private func signedV3FixtureManifest() throws -> ModelManifest {
        let fixtureDirectory = repositoryRoot
            .appendingPathComponent("Tests/TextifyModelsTests/Fixtures/Models")
        let publicKey = try String(
            contentsOf: fixtureDirectory
                .appendingPathComponent("manifest_v3.fixture-public-key.base64"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "fixture-v3-key",
                publicKeyBase64: publicKey
            ),
        ])
        return try verifier.verify(
            manifestData: Data(
                contentsOf: fixtureDirectory.appendingPathComponent("manifest_v3.json")
            ),
            signatureData: Data(
                contentsOf: fixtureDirectory.appendingPathComponent("manifest_v3.json.sig")
            )
        )
    }

    private func v3FixtureManifest(
        recommendedMinimumMemoryBytes: Int64
    ) throws -> ModelManifest {
        let fixtureURL = repositoryRoot
            .appendingPathComponent("Tests/TextifyModelsTests/Fixtures/Models")
            .appendingPathComponent("manifest_v3.json")
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL))
                as? [String: Any]
        )
        var graph = try XCTUnwrap(root["presentationGraph"] as? [String: Any])
        var artifacts = try XCTUnwrap(graph["artifacts"] as? [[String: Any]])
        let recommendedIndex = try XCTUnwrap(
            artifacts.firstIndex {
                $0["id"] as? String == "whisper-small-q5_1"
            }
        )
        var compatibility = try XCTUnwrap(
            artifacts[recommendedIndex]["compatibility"] as? [String: Any]
        )
        compatibility["minimumMemoryBytes"] = recommendedMinimumMemoryBytes
        artifacts[recommendedIndex]["compatibility"] = compatibility
        graph["artifacts"] = artifacts
        root["presentationGraph"] = graph
        return try ModelManifest.decode(
            JSONSerialization.data(withJSONObject: root)
        )
    }

    private func productionManifest(
        comparisonGroupOverride: (artifactID: String, groupID: String)? = nil
    ) throws -> ModelManifest {
        let manifestURL = repositoryRoot.appendingPathComponent("models/manifest.json")
        guard let comparisonGroupOverride else {
            return try ModelManifest.decode(Data(contentsOf: manifestURL))
        }

        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
                as? [String: Any]
        )
        var graph = try XCTUnwrap(root["presentationGraph"] as? [String: Any])
        var artifacts = try XCTUnwrap(graph["artifacts"] as? [[String: Any]])
        let index = try XCTUnwrap(
            artifacts.firstIndex {
                $0["id"] as? String == comparisonGroupOverride.artifactID
            }
        )
        var artifact = artifacts[index]
        var presentation = try XCTUnwrap(
            artifact["presentation"] as? [String: Any]
        )
        presentation["comparisonGroupID"] = comparisonGroupOverride.groupID
        artifact["presentation"] = presentation
        artifacts[index] = artifact
        graph["artifacts"] = artifacts
        root["presentationGraph"] = graph
        return try ModelManifest.decode(
            JSONSerialization.data(withJSONObject: root)
        )
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

    @MainActor
    private func wait(
        for expectedState: ModelCatalogInspectorLocalDetailsState,
        from controller: ModelCatalogInspectorController
    ) async {
        while controller.localDetailsState != expectedState {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = controller.localDetailsState
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func wait(
        for expectedState: ModelCatalogInspectorVerificationState,
        from controller: ModelCatalogInspectorController
    ) async {
        while controller.verificationState != expectedState {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = controller.verificationState
                } onChange: {
                    continuation.resume()
                }
            }
        }
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

private actor InspectorDetailLoadProbe {
    private var continuations: [
        String: CheckedContinuation<ModelCatalogArtifactLocalDetails, Error>
    ] = [:]
    private var requestedArtifactIDs: Set<String> = []
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var cancelledArtifactIDs: Set<String> = []
    private var cancellationWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func load(
        _ request: ModelCatalogArtifactInspectionRequest
    ) async throws -> ModelCatalogArtifactLocalDetails {
        requestedArtifactIDs.insert(request.artifactID)
        requestWaiters.removeValue(forKey: request.artifactID)?
            .forEach { $0.resume() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[request.artifactID] = continuation
            }
        } onCancel: {
            Task {
                await self.recordCancellation(of: request.artifactID)
            }
        }
    }

    func waitUntilRequested(_ artifactID: String) async {
        guard !requestedArtifactIDs.contains(artifactID) else {
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiters[artifactID, default: []].append(continuation)
        }
    }

    func waitUntilCancelled(_ artifactID: String) async {
        guard !cancelledArtifactIDs.contains(artifactID) else {
            return
        }
        await withCheckedContinuation { continuation in
            cancellationWaiters[artifactID, default: []].append(continuation)
        }
    }

    private func recordCancellation(of artifactID: String) {
        cancelledArtifactIDs.insert(artifactID)
        cancellationWaiters.removeValue(forKey: artifactID)?
            .forEach { $0.resume() }
    }

    func complete(artifactID: String, allocatedBytes: Int64) {
        continuations.removeValue(forKey: artifactID)?.resume(
            returning: ModelCatalogArtifactLocalDetails(
                artifactID: artifactID,
                allocatedBytes: allocatedBytes,
                presentFileCount: 1,
                expectedFileCount: 1,
                missingRelativePaths: [],
                integrity: .notVerified
            )
        )
    }
}

private actor InspectorVerificationProbe {
    private(set) var requestCount = 0
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    func verify(_ request: ModelCatalogArtifactVerificationRequest) {
        requestCount += 1
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
    }

    func waitUntilRequested() async {
        guard requestCount == 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }
}
