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

    func testRevokedArtifactKeepsPlacementAndDiagnosticsButSuppressesOperationsAndRecommendation() throws {
        let manifest = try v3FixtureManifest(
            recommendedMinimumMemoryBytes: 8_000_000_000
        )
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(model)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            revocationOverlay: ModelRevocationOverlay(
                records: [
                    ModelRevocationRecord(
                        recordID: "security-advisory",
                        exactArtifactID: model.id
                    ),
                ]
            ),
            managedReadinessByModelID: [model.id: .ready]
        )

        let row = try XCTUnwrap(
            experience.rows.first { $0.id == model.id }
        )
        XCTAssertTrue(row.isRevoked)
        XCTAssertEqual(row.placement, .curated)
        XCTAssertEqual(
            row.stateTokens,
            [.revoked, .installed, .ready]
        )
        XCTAssertEqual(row.actions, [.delete, .details])
        XCTAssertEqual(row.compatibility, .compatible)

        let checkpoint = try XCTUnwrap(
            experience.families
                .flatMap(\.checkpoints)
                .first { checkpoint in
                    checkpoint.artifacts.contains { $0.id == model.id }
                }
        )
        XCTAssertEqual(checkpoint.referenceArtifact?.id, model.id)
        XCTAssertNil(checkpoint.defaultInstallArtifact)
        let comparison = try XCTUnwrap(
            checkpoint.variantComparisons.first { $0.id == model.id }
        )
        XCTAssertFalse(comparison.isRecommended)
        XCTAssertFalse(comparison.isActionable)
        guard case let .exactArtifact(inspector)? =
            experience.inspectorPresentation(
                for: .exactArtifact(model.id)
            )
        else {
            return XCTFail("Revoked artifact must remain inspectable.")
        }
        XCTAssertTrue(inspector.localState.hasPrefix("Revoked"))
        XCTAssertTrue(inspector.canVerify)
        XCTAssertEqual(
            OnboardingModelCatalog(experience: experience)
                .action(for: model.id),
            .unavailable
        )
    }

    func testNewArtifactRevocationProducesOneConciseAnnouncement() throws {
        let manifest = try v3FixtureManifest(
            recommendedMinimumMemoryBytes: 8_000_000_000
        )
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let ordinary = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(model)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let revoked = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(model)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            revocationOverlay: ModelRevocationOverlay(
                records: [
                    ModelRevocationRecord(
                        recordID: "security-advisory",
                        exactArtifactID: model.id
                    ),
                ]
            )
        )
        var tracker = ModelCatalogAnnouncementTracker()

        XCTAssertEqual(tracker.update(rows: ordinary.rows), [])
        XCTAssertEqual(
            tracker.update(rows: revoked.rows),
            ["\(model.displayName) was revoked."]
        )
        XCTAssertEqual(tracker.update(rows: revoked.rows), [])
    }

    func testFilteringRevokedArtifactDoesNotRepeatAnnouncement() throws {
        let manifest = try v3FixtureManifest(
            recommendedMinimumMemoryBytes: 8_000_000_000
        )
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let ordinary = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(model)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let revoked = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(model)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            revocationOverlay: ModelRevocationOverlay(
                records: [
                    ModelRevocationRecord(
                        recordID: "security-advisory",
                        exactArtifactID: model.id
                    ),
                ]
            )
        )
        var tracker = ModelCatalogAnnouncementTracker()

        XCTAssertEqual(tracker.update(rows: ordinary.rows), [])
        XCTAssertEqual(
            tracker.update(rows: revoked.rows),
            ["\(model.displayName) was revoked."]
        )
        XCTAssertEqual(tracker.update(rows: []), [])
        XCTAssertEqual(tracker.update(rows: revoked.rows), [])
        XCTAssertEqual(tracker.update(rows: ordinary.rows), [])
        XCTAssertEqual(
            tracker.update(rows: revoked.rows),
            ["\(model.displayName) was revoked."]
        )
    }

    func testAttemptAndCatalogRevocationShareOneArtifactAnnouncement() throws {
        let manifest = try v3FixtureManifest(
            recommendedMinimumMemoryBytes: 8_000_000_000
        )
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let ordinary = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(model)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let revoked = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(model)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            revocationOverlay: ModelRevocationOverlay(
                records: [
                    ModelRevocationRecord(
                        recordID: "security-advisory",
                        exactArtifactID: model.id
                    ),
                ]
            )
        )
        let activeAttempt = ModelInstallQueueAttempt(
            id: "attempt-1",
            artifactID: model.id,
            purpose: .transcription,
            action: .install,
            createdAt: "2026-07-24T10:00:00Z",
            state: DownloadState(
                modelID: model.id,
                phase: .downloading
            )
        )
        let revokedAttempt = ModelInstallQueueAttempt(
            id: activeAttempt.id,
            artifactID: activeAttempt.artifactID,
            purpose: activeAttempt.purpose,
            action: activeAttempt.action,
            createdAt: activeAttempt.createdAt,
            state: DownloadState(
                modelID: model.id,
                phase: .revoked
            )
        )
        var tracker = ModelCatalogAnnouncementTracker()

        XCTAssertEqual(tracker.update(rows: ordinary.rows), [])
        XCTAssertEqual(tracker.update(attempts: [activeAttempt]), [])
        XCTAssertEqual(
            tracker.update(attempts: [revokedAttempt]),
            ["\(model.id) installation revoked."]
        )
        XCTAssertEqual(tracker.update(rows: revoked.rows), [])
    }

    func testRestoredArtifactOffersFreshInstallWithoutRetryingRevokedAttempt() throws {
        let restored = model(id: "restored")
        let revokedHistory = DownloadState(
            modelID: restored.id,
            phase: .revoked,
            attemptID: "revoked-attempt"
        )
        let uninstalled = ModelCatalogExperience(
            trustedModels: [restored],
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: revokedHistory
        )
        let installedExperience = ModelCatalogExperience(
            trustedModels: [restored],
            installedRecords: [installed(restored)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: revokedHistory,
            managedReadinessByModelID: [restored.id: .ready]
        )
        let uninstalledRow = try XCTUnwrap(
            uninstalled.rows.first { $0.id == restored.id }
        )
        let installedRow = try XCTUnwrap(
            installedExperience.rows.first { $0.id == restored.id }
        )

        XCTAssertTrue(uninstalledRow.actions.contains(.install))
        XCTAssertFalse(uninstalledRow.actions.contains(.retryInstall))
        XCTAssertTrue(installedRow.actions.contains(.reinstall))
        XCTAssertFalse(installedRow.actions.contains(.retryInstall))
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

        XCTAssertEqual(
            experience.rows.map(\.id),
            [downloadable.id, active.id, noLongerCurated.id]
        )

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

    func testInstalledRowsExposeExclusiveCuratedCustomLegacyAndFormerlyCuratedPlacement() throws {
        let curatedModel = model(id: "curated", sha256: String(repeating: "a", count: 64))
        let customDigest = String(repeating: "b", count: 64)
        let customModel = model(
            id: "custom-sha256-\(customDigest)",
            sha256: customDigest
        )
        let legacyModel = model(id: "legacy", sha256: String(repeating: "c", count: 64))
        let removedModel = model(id: "removed", sha256: String(repeating: "d", count: 64))
        let custom = InstalledModelRecord(
            model: customModel,
            installedAt: "2026-07-24T00:00:00Z",
            localFilesByManifestFilename: [
                customModel.files[0].filename: "/Models/custom/model.bin",
            ],
            identityHistory: InstalledModelIdentityHistory(
                customImport: CustomModelImportHistory(
                    contentDigest: ModelArtifactTypedDigest(
                        type: .singleFileSHA256,
                        value: customDigest
                    ),
                    localNames: ["Local Name"],
                    sourceFilenames: ["local.ggml"]
                )
            )
        )
        let removed = InstalledModelRecord(
            model: removedModel,
            installedAt: "2026-07-24T00:00:00Z",
            localFilesByManifestFilename: [
                removedModel.files[0].filename: "/Models/removed/model.bin",
            ],
            identityHistory: InstalledModelIdentityHistory(wasCurated: true)
        )

        let experience = ModelCatalogExperience(
            trustedModels: [curatedModel],
            installedRecords: [
                installed(curatedModel),
                custom,
                installed(legacyModel),
                removed,
            ],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(scope: .installed)
        )

        XCTAssertEqual(
            Set(experience.rows.map(\.id)),
            [curatedModel.id, customModel.id, legacyModel.id, removedModel.id]
        )
        let placements: [String: ModelArtifactPlacement] = Dictionary(
            uniqueKeysWithValues: experience.rows.compactMap { row in
                row.placement.map { (row.id, $0) }
            }
        )
        XCTAssertEqual(
            placements,
            [
                curatedModel.id: .curated,
                customModel.id: .custom,
                legacyModel.id: .legacy,
                removedModel.id: .noLongerCurated,
            ]
        )
        let customPresentation = try XCTUnwrap(
            experience.rows.first { $0.id == customModel.id }
        )
        XCTAssertEqual(customPresentation.model.qualityLabel, "Unrated")
        XCTAssertEqual(customPresentation.model.speedLabel, "Unrated")
        guard case let .exactArtifact(inspector) = experience.inspectorPresentation(
            for: .exactArtifact(customModel.id)
        ) else {
            return XCTFail("Expected Custom artifact inspector.")
        }
        XCTAssertEqual(inspector.id, customModel.id)
        XCTAssertNotNil(inspector.verificationRequest)
    }

    func testQueueProjectionUpdatesOnlyAffectedArtifactsAndCheckpointRollups() throws {
        let manifest = try signedV3FixtureManifest()
        let unrelated = model(id: "unrelated-local")
        let downloading = DownloadState(
            modelID: "whisper-small-q5_1",
            phase: .downloading,
            bytesDownloaded: 25,
            totalBytes: 100,
            attemptID: "attempt-1"
        )
        let queued = DownloadState(
            modelID: "whisper-small-q8_0",
            phase: .queued,
            attemptID: "attempt-2"
        )

        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(unrelated)],
            activePreferences: ModelCatalogActivePreferences(),
            transferStatesByModelID: [
                downloading.modelID: downloading,
                queued.modelID: queued,
            ]
        )

        XCTAssertEqual(
            experience.rows.first {
                $0.id == downloading.modelID
            }?.installState,
            downloading
        )
        XCTAssertEqual(
            experience.rows.first {
                $0.id == queued.modelID
            }?.installState,
            queued
        )
        XCTAssertNil(
            experience.rows.first {
                $0.id == unrelated.id
            }?.installState
        )

        let affectedCheckpoint = try XCTUnwrap(
            experience.inspectorPresentation(
                for: .checkpoint("checkpoint.whisper.small")
            )
        )
        guard case let .checkpoint(checkpoint) = affectedCheckpoint else {
            return XCTFail("Expected affected checkpoint inspector.")
        }
        XCTAssertEqual(
            checkpoint.aggregateState,
            "No variants installed • Downloading model"
        )
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

        XCTAssertEqual(experience.rows.map(\.id), [cleaner.id, transcription.id])

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

    func testInstalledScopeKeepsOnlyInstalledArtifactsAndTheirParents() throws {
        let manifest = try productionManifest()
        let installedIDs = [
            "parakeet-tdt-0.6b-v3-q5-k-m",
            "qwen3-asr-0.6b-q8-0",
        ]
        let records = try installedIDs.map { modelID in
            installed(try XCTUnwrap(manifest.models.first { $0.id == modelID }))
        }

        let all = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: records,
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(
                scope: .all,
                purpose: .transcription
            )
        )
        let installedOnly = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: records,
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(
                scope: .installed,
                purpose: .transcription
            )
        )

        XCTAssertGreaterThan(all.rows.count, installedOnly.rows.count)
        XCTAssertEqual(Set(installedOnly.rows.map(\.id)), Set(installedIDs))
        XCTAssertEqual(
            Set(installedOnly.families.map(\.id)),
            ["family.nvidia.parakeet", "family.qwen.qwen3-asr"]
        )
        XCTAssertEqual(
            installedOnly.families
                .flatMap(\.checkpoints)
                .flatMap(\.artifacts)
                .map(\.id),
            installedIDs
        )
    }

    func testSearchMatchesSignedHierarchyProviderLanguageFormatNumericFormatAndRuntime() throws {
        let manifest = try productionManifest()

        func resultIDs(searchText: String) -> Set<String> {
            Set(ModelCatalogExperience(
                trustedManifest: manifest,
                installedRecords: [],
                activePreferences: ModelCatalogActivePreferences(),
                transferState: nil,
                query: ModelCatalogQuery(
                    searchText: searchText,
                    purpose: .transcription
                )
            ).rows.map(\.id))
        }

        XCTAssertTrue(resultIDs(searchText: "NVIDIA").contains("parakeet-tdt-0.6b-v3"))
        XCTAssertEqual(
            resultIDs(searchText: "Whisper small.en"),
            ["ggml-small.en-q5_1"]
        )
        XCTAssertTrue(resultIDs(searchText: "Japanese").contains("parakeet-ja"))
        XCTAssertTrue(resultIDs(searchText: "GGUF").contains("qwen3-asr-0.6b-q8-0"))
        XCTAssertTrue(resultIDs(searchText: "Q5_K_M").contains("qwen3-asr-1.7b-q5-k-m"))
        XCTAssertTrue(resultIDs(searchText: "transcribe.cpp").contains("parakeet-tdt-0.6b-v3-f16"))
    }

    func testStructuredFiltersUseSignedExactArtifactAndLocalStateTruth() throws {
        let manifest = try productionManifest()
        let installedID = "qwen3-asr-0.6b-q8-0"
        let activeID = "qwen3-asr-1.7b-q5-k-m"
        let installedModels = try [installedID, activeID].map { modelID in
            installed(try XCTUnwrap(manifest.models.first { $0.id == modelID }))
        }
        let resolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_000_000_000,
                supportedRuntimes: [.whisperCpp]
            )
        )

        func experience(
            _ configure: (inout ModelCatalogQuery) -> Void
        ) -> ModelCatalogExperience {
            var query = ModelCatalogQuery(purpose: .transcription)
            configure(&query)
            return ModelCatalogExperience(
                trustedManifest: manifest,
                compatibilityResolver: resolver,
                installedRecords: installedModels,
                activePreferences: ModelCatalogActivePreferences(
                    transcriptionModelID: activeID
                ),
                transferState: nil,
                managedReadinessByModelID: [
                    installedID: .needsRepair,
                    activeID: .ready,
                ],
                query: query
            )
        }

        XCTAssertTrue(experience {
            $0.artifactFormats = [.gguf]
        }.families.flatMap(\.checkpoints).flatMap(\.artifacts).allSatisfy {
            $0.metadata.artifactFormat == .gguf
        })
        XCTAssertTrue(experience {
            $0.numericFormats = [.q5_k_m]
        }.families.flatMap(\.checkpoints).flatMap(\.artifacts).allSatisfy {
            $0.metadata.numericFormat == .q5_k_m
        })
        XCTAssertTrue(experience {
            $0.runtimes = [.mlxAudio]
        }.families.flatMap(\.checkpoints).flatMap(\.artifacts).allSatisfy {
            $0.metadata.runtime == .mlxAudio
        })
        XCTAssertTrue(experience {
            $0.computeRoutes = [.cpuOnly]
        }.families.flatMap(\.checkpoints).flatMap(\.artifacts).allSatisfy {
            $0.metadata.computeRoute == .cpuOnly
        })
        XCTAssertTrue(experience {
            $0.languages = ["ja"]
        }.rows.allSatisfy {
            $0.operationalModel?.capabilities.languages.contains("ja") == true
                || $0.operationalModel?.capabilities.languages.contains("*") == true
        })
        XCTAssertTrue(experience {
            $0.evidence = [.qualityAndSpeed]
        }.rows.allSatisfy {
            $0.model.qualityScore != nil && $0.model.speedScore != nil
        })
        XCTAssertEqual(
            experience { $0.states = [.needsRepair] }.rows.map(\.id),
            [installedID]
        )
        XCTAssertEqual(
            experience { $0.states = [.active] }.rows.map(\.id),
            [activeID]
        )
        XCTAssertTrue(experience {
            $0.compatibility = [.incompatible]
        }.rows.allSatisfy {
            if case .incompatible = $0.compatibility {
                return true
            }
            return false
        })
    }

    func testAppliedFilterTokensAreIndividuallyRemovable() throws {
        var query = ModelCatalogQuery(
            searchText: "parakeet",
            artifactFormats: [.gguf],
            numericFormats: [.q5_k_m],
            runtimes: [.transcribeCpp],
            computeRoutes: [.cpuOnly],
            languages: ["en"],
            compatibility: [.compatible],
            states: [.installed],
            evidence: [.qualityAndSpeed]
        )

        let originalTokens = query.appliedFilterTokens
        XCTAssertEqual(originalTokens.count, 8)
        let formatToken = originalTokens.first {
            $0.id == .artifactFormat(.gguf)
        }
        XCTAssertNotNil(formatToken)

        query.removeFilter(try XCTUnwrap(formatToken))

        XCTAssertTrue(query.artifactFormats.isEmpty)
        XCTAssertEqual(query.searchText, "parakeet")
        XCTAssertEqual(query.appliedFilterTokens.count, 7)
    }

    func testCatalogSortUsesSignedCuratedRankAtEveryHierarchyLevel() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try reversedCatalogArraysManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(
                sort: .catalog,
                purpose: .transcription
            )
        )

        XCTAssertEqual(
            experience.families.map(\.metadata.presentation.curatedRank),
            experience.families
                .map(\.metadata.presentation.curatedRank)
                .sorted()
        )
        for family in experience.families {
            XCTAssertEqual(
                family.checkpoints.map(\.metadata.presentation.curatedRank),
                family.checkpoints
                    .map(\.metadata.presentation.curatedRank)
                    .sorted()
            )
            for checkpoint in family.checkpoints {
                XCTAssertEqual(
                    checkpoint.artifacts.map(\.metadata.presentation.curatedRank),
                    checkpoint.artifacts
                        .map(\.metadata.presentation.curatedRank)
                        .sorted()
                )
            }
        }
    }

    func testCheckpointSortingUsesSignedReferenceAndKeepsUnknownLastBothDirections() throws {
        let manifest = try productionManifest()

        func parakeetCheckpointIDs(
            sort: ModelCatalogSort,
            direction: ModelCatalogSortDirection
        ) throws -> [String] {
            let experience = ModelCatalogExperience(
                trustedManifest: manifest,
                installedRecords: [],
                activePreferences: ModelCatalogActivePreferences(),
                transferState: nil,
                query: ModelCatalogQuery(
                    scope: .all,
                    sort: sort,
                    sortDirection: direction,
                    purpose: .transcription
                )
            )
            return try XCTUnwrap(
                experience.families.first {
                    $0.id == "family.nvidia.parakeet"
                }
            ).checkpoints.map(\.id)
        }

        let descending = try parakeetCheckpointIDs(
            sort: .quality,
            direction: .descending
        )
        XCTAssertEqual(
            Array(descending.prefix(2)),
            [
                "checkpoint.nvidia.parakeet-tdt-0.6b-v3",
                "checkpoint.nvidia.parakeet-tdt-0.6b-v2",
            ],
            "Equal signed reference scores keep signed catalog order."
        )
        XCTAssertEqual(
            descending.last,
            "checkpoint.nvidia.parakeet-tdt-ctc-0.6b-ja"
        )
        XCTAssertEqual(
            try parakeetCheckpointIDs(sort: .quality, direction: .ascending).last,
            "checkpoint.nvidia.parakeet-tdt-ctc-0.6b-ja"
        )
    }

    func testInstalledSizeSortUsesLocalBytesAndKeepsUnknownLast() throws {
        let manifest = try productionManifest()
        let smallID = "qwen3-asr-0.6b-q8-0"
        let largeID = "qwen3-asr-1.7b-q8-0"
        let unknownID = "ggml-small.en-q5_1"
        let records = try [smallID, largeID, unknownID].map { modelID in
            installed(try XCTUnwrap(manifest.models.first { $0.id == modelID }))
        }

        func rowIDs(_ direction: ModelCatalogSortDirection) -> [String] {
            ModelCatalogExperience(
                trustedManifest: manifest,
                installedRecords: records,
                activePreferences: ModelCatalogActivePreferences(),
                transferState: nil,
                onDiskBytesByModelID: [
                    smallID: 100,
                    largeID: 300,
                ],
                query: ModelCatalogQuery(
                    scope: .installed,
                    sort: .installedSize,
                    sortDirection: direction,
                    purpose: .transcription
                )
            ).rows.map(\.id)
        }

        XCTAssertEqual(rowIDs(.ascending), [smallID, largeID, unknownID])
        XCTAssertEqual(rowIDs(.descending), [largeID, smallID, unknownID])
    }

    func testSizeSemanticsDistinguishSignedDownloadFromMeasuredOnDiskBytes() throws {
        let manifest = try signedV3FixtureManifest()
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let record = installed(model)

        let all = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [record],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            installedSizeStatus: .calculating,
            query: ModelCatalogQuery(scope: .all, purpose: .transcription)
        )
        let calculating = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [record],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            installedSizeStatus: .calculating,
            query: ModelCatalogQuery(scope: .installed, purpose: .transcription)
        )
        let measured = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [record],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            onDiskBytesByModelID: [model.id: 4_096],
            installedSizeStatus: .measured,
            query: ModelCatalogQuery(scope: .installed, purpose: .transcription)
        )
        let unavailable = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [record],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            installedSizeStatus: .unavailable,
            query: ModelCatalogQuery(scope: .installed, purpose: .transcription)
        )

        XCTAssertEqual(try XCTUnwrap(all.rows.first).sizeLabel, "Download Size")
        XCTAssertNotEqual(try XCTUnwrap(all.rows.first).sizeDescription, "Calculating")
        XCTAssertEqual(try XCTUnwrap(calculating.rows.first).sizeLabel, "On Disk")
        XCTAssertEqual(try XCTUnwrap(calculating.rows.first).sizeDescription, "Calculating")
        XCTAssertEqual(try XCTUnwrap(measured.rows.first).sizeLabel, "On Disk")
        XCTAssertTrue(
            try XCTUnwrap(measured.rows.first).sizeDescription.hasPrefix("About ")
        )
        XCTAssertEqual(
            try XCTUnwrap(unavailable.rows.first).sizeDescription,
            "Size Unavailable"
        )
    }

    func testCheckpointOnDiskAggregateIncludesOnlyInstalledExactArtifacts() throws {
        let manifest = try signedV3FixtureManifest()
        let installedModel = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            onDiskBytesByModelID: [installedModel.id: 7_777],
            installedSizeStatus: .measured,
            query: ModelCatalogQuery(
                scope: .installed,
                sort: .installedSize,
                purpose: .transcription
            )
        )
        let checkpoint = try XCTUnwrap(
            experience.families
                .flatMap(\.checkpoints)
                .first { checkpoint in
                    checkpoint.artifacts.contains {
                        $0.id == installedModel.id
                    }
                }
        )

        XCTAssertEqual(checkpoint.artifacts.map(\.id), [installedModel.id])
        XCTAssertEqual(checkpoint.installedOnDiskBytes, 7_777)
    }

    func testDuplicateInstalledReceiptsProduceOneOffCatalogRow() throws {
        let model = try XCTUnwrap(
            signedV3FixtureManifest().models.first {
                $0.id == "whisper-small-q5_1"
            }
        )
        let record = installed(model)
        let experience = ModelCatalogExperience(
            trustedModels: [],
            installedRecords: [record, record],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(scope: .installed)
        )

        XCTAssertEqual(experience.rows.map(\.id), [model.id])
    }

    func testInstalledCheckpointSortingUsesExactArtifactOnDiskAggregate() throws {
        let manifest = try productionManifest()
        let smallIDs = [
            "qwen3-asr-0.6b-q8-0",
            "qwen3-asr-0.6b-q5-k-m",
        ]
        let largeID = "qwen3-asr-1.7b-q8-0"
        let records = try (smallIDs + [largeID]).map { modelID in
            installed(try XCTUnwrap(
                manifest.models.first { $0.id == modelID }
            ))
        }

        func checkpoints(
            direction: ModelCatalogSortDirection,
            numericFormats: [ModelNumericFormat] = []
        ) throws -> [ModelCatalogCheckpointPresentation] {
            let experience = ModelCatalogExperience(
                trustedManifest: manifest,
                installedRecords: records,
                activePreferences: ModelCatalogActivePreferences(),
                transferState: nil,
                onDiskBytesByModelID: [
                    smallIDs[0]: 100,
                    smallIDs[1]: 50,
                    largeID: 300,
                ],
                query: ModelCatalogQuery(
                    scope: .installed,
                    sort: .installedSize,
                    sortDirection: direction,
                    numericFormats: numericFormats,
                    purpose: .transcription
                )
            )
            return try XCTUnwrap(
                experience.families.first {
                    $0.id == "family.qwen.qwen3-asr"
                }
            ).checkpoints
        }

        let ascending = try checkpoints(direction: .ascending)
        XCTAssertEqual(
            ascending.map(\.id),
            [
                "checkpoint.qwen.qwen3-asr-0.6b",
                "checkpoint.qwen.qwen3-asr-1.7b",
            ]
        )
        XCTAssertEqual(ascending.first?.installedOnDiskBytes, 150)
        let filtered = try checkpoints(
            direction: .ascending,
            numericFormats: [.q8_0]
        )
        XCTAssertEqual(filtered.first?.artifacts.map(\.id), [smallIDs[0]])
        XCTAssertEqual(filtered.first?.installedOnDiskBytes, 150)
        XCTAssertEqual(
            try checkpoints(direction: .descending).map(\.id),
            Array(ascending.map(\.id).reversed())
        )
    }

    func testInstalledStorageSummaryReportsEveryRequiredCategory() {
        let snapshot = ModelStorageInventorySnapshot(
            artifacts: [],
            summary: ModelStorageInventorySummary(
                installedArtifactCount: 2,
                installedModelStorageBytes: 10,
                downloadStorageBytes: 20,
                otherModelDataBytes: 30,
                totalManagedStorageBytes: 60,
                availableSpaceBytes: 1_000
            )
        )
        let presentation = ModelCatalogStorageSummaryPresentation(
            state: .available(generation: 4, snapshot: snapshot),
            installedCount: 2
        )

        XCTAssertEqual(
            presentation.facts.map(\.label),
            [
                "Installed",
                "Installed Model Storage",
                "Download Storage",
                "Other Model Data",
                "Total Managed Storage",
                "Available Space",
            ]
        )
        XCTAssertEqual(presentation.facts.first?.value, "2")
        XCTAssertTrue(
            presentation.facts.dropFirst().allSatisfy {
                $0.value != "Calculating" && $0.value != "Size Unavailable"
            }
        )
    }

    func testInstalledStorageSummaryKeepsMissingMeasurementsExplicit() {
        let calculating = ModelCatalogStorageSummaryPresentation(
            state: .calculating,
            installedCount: 3
        )
        let unavailable = ModelCatalogStorageSummaryPresentation(
            state: .unavailable(generation: 8),
            installedCount: 3
        )

        XCTAssertEqual(calculating.facts.first?.value, "3")
        XCTAssertTrue(
            calculating.facts.dropFirst().allSatisfy {
                $0.value == "Calculating"
            }
        )
        XCTAssertTrue(
            unavailable.facts.dropFirst().allSatisfy {
                $0.value == "Size Unavailable"
            }
        )
    }

    func testPinnedRevealDoesNotMutateOrdinaryQueryAndCanBeDismissed() throws {
        let manifest = try productionManifest()
        let installedModel = try XCTUnwrap(
            manifest.models.first { $0.id == "ggml-small.en-q5_1" }
        )
        var query = ModelCatalogQuery(
            scope: .installed,
            searchText: "no ordinary result",
            artifactFormats: [.gguf],
            purpose: .transcription
        )
        let queryBeforeReveal = query
        query.reveal(artifactID: "qwen3-asr-0.6b-q8-0")

        let revealed = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: query
        )

        XCTAssertTrue(revealed.rows.isEmpty)
        XCTAssertEqual(
            revealed.pinnedReveal?.artifactID,
            "qwen3-asr-0.6b-q8-0"
        )
        XCTAssertEqual(query.ordinaryQuery, queryBeforeReveal)

        query.dismissReveal()

        XCTAssertNil(query.revealedArtifactID)
        XCTAssertEqual(query, queryBeforeReveal)
    }

    func testPinnedRevealRetainsOffCatalogAndUnavailableArtifactIdentity() throws {
        let manifest = try productionManifest()
        let offCatalogModel = model(id: "retired-installed-artifact")
        var installedQuery = ModelCatalogQuery(purpose: .transcription)
        installedQuery.reveal(artifactID: offCatalogModel.id)

        let installedReveal = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(offCatalogModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: installedQuery
        )

        XCTAssertEqual(
            installedReveal.pinnedReveal,
            .standaloneArtifact(
                try XCTUnwrap(
                    installedReveal.rows.first {
                        $0.id == offCatalogModel.id
                    }
                )
            )
        )

        var unavailableQuery = ModelCatalogQuery(purpose: .transcription)
        unavailableQuery.reveal(artifactID: "revoked-history-artifact")
        let unavailableReveal = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: unavailableQuery
        )

        XCTAssertEqual(
            unavailableReveal.pinnedReveal,
            .unavailableArtifact("revoked-history-artifact")
        )
    }

    @MainActor
    func testModelDeepLinkRoutesToPurposeAndRetainsExactRevealIdentity() {
        let router = SettingsRouter()

        router.revealModelArtifact(
            id: "mossformer2-se-fp16",
            purpose: .voiceCleaning
        )

        XCTAssertEqual(router.selectedPane, .voiceCleaning)
        XCTAssertEqual(
            router.modelReveal,
            ModelCatalogRevealRequest(
                artifactID: "mossformer2-se-fp16",
                purpose: .voiceCleaning
            )
        )

        router.dismissModelReveal()

        XCTAssertNil(router.modelReveal)
        XCTAssertEqual(router.selectedPane, .voiceCleaning)
    }

    func testQueryEmptyStatesHaveDistinctRecoverySemantics() {
        XCTAssertEqual(
            ModelCatalogQuery(scope: .installed).emptyState,
            .installed
        )
        XCTAssertEqual(
            ModelCatalogQuery(searchText: "qwen").emptyState,
            .search
        )
        XCTAssertEqual(
            ModelCatalogQuery(artifactFormats: [.gguf]).emptyState,
            .filters
        )
        XCTAssertEqual(
            ModelCatalogQuery(
                searchText: "qwen",
                artifactFormats: [.gguf]
            ).emptyState,
            .combined
        )
        XCTAssertEqual(ModelCatalogQuery().emptyState, .validCatalog)
        XCTAssertNil(
            ModelCatalogQueryEmptyState.validCatalog.actionTitle
        )
        XCTAssertEqual(
            Set([
                ModelCatalogQueryEmptyState.installed.actionTitle,
                ModelCatalogQueryEmptyState.search.actionTitle,
                ModelCatalogQueryEmptyState.filters.actionTitle,
                ModelCatalogQueryEmptyState.combined.actionTitle,
            ].compactMap { $0 }).count,
            4
        )
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
            compatibilityResolver: resolver,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(
                compatibility: [.compatible],
                purpose: .transcription
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
            query: ModelCatalogQuery(runtimes: [.transcribeCpp])
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

    func testRemovalConfirmationRequiresOneSelectedInstalledExactArtifact() throws {
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
            transferState: nil,
            onDiskBytesByModelID: [installedModel.id: 4_096]
        )
        var state = ModelCatalogHierarchyState()
        state.select(.checkpoint("checkpoint.whisper.small"))

        XCTAssertNil(
            experience.removalConfirmation(for: state.selection)
        )

        state.select(.exactArtifact(installedModel.id))
        let confirmation = try XCTUnwrap(
            experience.removalConfirmation(for: state.selection)
        )

        XCTAssertEqual(confirmation.artifactID, installedModel.id)
        XCTAssertEqual(confirmation.exactArtifactName, "Q5_1")
        XCTAssertEqual(confirmation.checkpointName, "Whisper Small")
        XCTAssertEqual(
            confirmation.measuredLocalSize,
            ByteCountFormatter.string(
                fromByteCount: 4_096,
                countStyle: .file
            )
        )
        XCTAssertEqual(
            confirmation.activeConsequence,
            .disableDictation
        )
    }

    func testDeleteActionOnlyAppearsForTheSelectedExactArtifact() throws {
        let manifest = try signedV3FixtureManifest()
        let installedModel = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            onDiskBytesByModelID: [installedModel.id: 4_096]
        )
        let row = try XCTUnwrap(
            experience.rows.first { $0.id == installedModel.id }
        )

        XCTAssertFalse(row.visibleActions(for: nil).contains(.delete))
        XCTAssertFalse(
            row.visibleActions(
                for: .exactArtifact("another-artifact")
            ).contains(.delete)
        )
        XCTAssertTrue(
            row.visibleActions(
                for: .exactArtifact(installedModel.id)
            ).contains(.delete)
        )
    }

    func testDeletionWaitsForACompletedLocalSizeMeasurement() throws {
        let manifest = try signedV3FixtureManifest()
        let installedModel = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )
        let calculating = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            installedSizeStatus: .calculating
        )
        let calculatingRow = try XCTUnwrap(
            calculating.rows.first { $0.id == installedModel.id }
        )

        XCTAssertFalse(
            calculatingRow.visibleActions(
                for: .exactArtifact(installedModel.id)
            ).contains(.delete)
        )
        XCTAssertNil(
            calculating.removalConfirmation(
                for: .exactArtifact(installedModel.id)
            )
        )

        let measuredMissingDirectory = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            onDiskBytesByModelID: [installedModel.id: 0],
            installedSizeStatus: .measured
        )
        let confirmation = try XCTUnwrap(
            measuredMissingDirectory.removalConfirmation(
                for: .exactArtifact(installedModel.id)
            )
        )

        XCTAssertEqual(
            confirmation.measuredLocalSize,
            ByteCountFormatter.string(
                fromByteCount: 0,
                countStyle: .file
            )
        )
    }

    func testSingleVariantSemanticRowResolvesToExactDeletionTarget() throws {
        let manifest = try signedV3FixtureManifest()
        let installedModel = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-tiny-f16" }
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(installedModel)],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            onDiskBytesByModelID: [installedModel.id: 2_048]
        )
        var state = ModelCatalogHierarchyState()
        state.select(.exactArtifact(installedModel.id))

        let confirmation = try XCTUnwrap(
            experience.removalConfirmation(for: state.selection)
        )

        XCTAssertEqual(confirmation.artifactID, installedModel.id)
        XCTAssertEqual(confirmation.checkpointName, "Whisper Tiny")
        XCTAssertEqual(confirmation.activeConsequence, .none)
    }

    func testUninstalledExactArtifactHasNoDeletionConfirmation() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )

        XCTAssertNil(
            experience.removalConfirmation(
                for: .exactArtifact("whisper-small-q5_1")
            )
        )
    }

    func testActiveCleanerConfirmationNamesVoiceCleaningConsequence() throws {
        let cleaner = model(
            id: "cleaner",
            purpose: .voiceCleaning,
            engine: .mlxAudio
        )
        let experience = ModelCatalogExperience(
            trustedModels: [cleaner],
            installedRecords: [installed(cleaner)],
            activePreferences: ModelCatalogActivePreferences(
                voiceCleaningModelID: cleaner.id
            ),
            transferState: nil,
            onDiskBytesByModelID: [cleaner.id: 8_192]
        )

        let confirmation = try XCTUnwrap(
            experience.removalConfirmation(
                for: .exactArtifact(cleaner.id)
            )
        )

        XCTAssertEqual(
            confirmation.activeConsequence,
            .disableVoiceCleaning
        )
        XCTAssertTrue(confirmation.message.contains(cleaner.id))
        XCTAssertTrue(
            confirmation.message.contains("Measured local size")
        )
        XCTAssertEqual(
            confirmation.destructiveActionTitle,
            "Disable Voice Cleaning & Delete"
        )
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
            query: ModelCatalogQuery(numericFormats: [.q5_1])
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

    func testHierarchyReconcilePreservesSurvivingViewportAnchorsAndMovesRemovedFocusDeterministically() throws {
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
        var state = ModelCatalogHierarchyState(
            expandedCheckpointIDs: [checkpoint.id],
            focusedRowID: .exactArtifact("whisper-small-q5_1"),
            scrollAnchorID: .checkpoint(checkpoint.id)
        )

        state.reconcile(with: initialExperience)

        XCTAssertEqual(
            state.focusedRowID,
            .exactArtifact("whisper-small-q5_1")
        )
        XCTAssertEqual(
            state.scrollAnchorID,
            .checkpoint(checkpoint.id)
        )

        let filteredExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(searchText: "tiny")
        )
        let recovery = state.reconcile(
            from: initialExperience,
            to: filteredExperience
        )

        XCTAssertEqual(
            state.focusedRowID,
            .exactArtifact("whisper-tiny-f16")
        )
        XCTAssertEqual(
            state.scrollAnchorID,
            .exactArtifact("whisper-tiny-f16")
        )
        XCTAssertNil(recovery)
    }

    func testRoutinePublicationPreservesExplicitSemanticScrollAnchor() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            experience.families.first?.checkpoints.first
        )
        var state = ModelCatalogHierarchyState(
            scrollAnchorID: .checkpoint(checkpoint.id)
        )

        state.reconcile(from: experience, to: experience)

        XCTAssertEqual(
            state.scrollAnchorID,
            .checkpoint(checkpoint.id)
        )
    }

    func testRoutineQueryPublicationPreservesHiddenExpansionIDs() throws {
        let manifest = try signedV3FixtureManifest()
        let initialExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            initialExperience.families
                .flatMap(\.checkpoints)
                .first { $0.metadata.artifactIDs.count > 1 }
        )
        var state = ModelCatalogHierarchyState(
            expandedCheckpointIDs: [checkpoint.id]
        )
        let filteredExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(searchText: "no matching artifact")
        )

        state.reconcile(
            from: initialExperience,
            to: filteredExperience
        )
        state.reconcile(
            from: filteredExperience,
            to: initialExperience
        )

        XCTAssertTrue(
            state.visibleRows(in: initialExperience).contains {
                $0.id == .exactArtifact(checkpoint.artifacts[0].id)
            }
        )
    }

    func testRemovedSelectionMovesToTheNextSurvivingSelectableRowAndAnnouncesIt() throws {
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
        var state = ModelCatalogHierarchyState(
            selection: .exactArtifact("whisper-small-q5_1"),
            expandedCheckpointIDs: [checkpoint.id],
            focusedRowID: .exactArtifact("whisper-small-q5_1"),
            scrollAnchorID: .exactArtifact("whisper-small-q5_1")
        )
        let filteredExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(searchText: "tiny")
        )

        let recovery = state.reconcile(
            from: initialExperience,
            to: filteredExperience
        )

        XCTAssertEqual(
            state.selection,
            .exactArtifact("whisper-tiny-f16")
        )
        XCTAssertEqual(
            state.focusedRowID,
            .exactArtifact("whisper-tiny-f16")
        )
        XCTAssertEqual(
            recovery,
            ModelCatalogSelectionRecovery(
                selection: .exactArtifact("whisper-tiny-f16"),
                announcement: "Selection moved to Whisper Tiny, row 2 of 2."
            )
        )
    }

    func testRemovedArtifactSelectionFallsBackToItsSurvivingCheckpointFirst() throws {
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
        let selectedArtifact = try XCTUnwrap(
            checkpoint.artifacts.first {
                $0.id != checkpoint.metadata.recommendedArtifactID
            }
        )
        let survivingArtifact = try XCTUnwrap(
            checkpoint.artifacts.first {
                $0.id != selectedArtifact.id
            }
        )
        var state = ModelCatalogHierarchyState(
            selection: .exactArtifact(selectedArtifact.id),
            expandedCheckpointIDs: [checkpoint.id],
            focusedRowID: .exactArtifact(selectedArtifact.id),
            scrollAnchorID: .exactArtifact(selectedArtifact.id)
        )
        let filteredExperience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: ModelCatalogQuery(searchText: survivingArtifact.id)
        )

        _ = state.reconcile(
            from: initialExperience,
            to: filteredExperience
        )

        XCTAssertEqual(state.selection, .checkpoint(checkpoint.id))
        XCTAssertEqual(state.focusedRowID, .checkpoint(checkpoint.id))
        XCTAssertEqual(state.scrollAnchorID, .checkpoint(checkpoint.id))
    }

    func testKeyboardNavigationMovesAcrossOffscreenRowsAndKeepsFocusScrollAndSelectionTogether() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            experience.families.first?.checkpoints.first
        )
        var state = ModelCatalogHierarchyState(
            expandedCheckpointIDs: [checkpoint.id],
            focusedRowID: .family("family.whisper")
        )

        XCTAssertEqual(
            state.handleKeyboardCommand(
                .pageDown,
                in: experience,
                pageSize: 3
            ),
            .none
        )
        XCTAssertEqual(
            state.focusedRowID,
            .exactArtifact("whisper-small-q8_0")
        )
        XCTAssertEqual(
            state.scrollAnchorID,
            .exactArtifact("whisper-small-q8_0")
        )

        XCTAssertEqual(
            state.handleKeyboardCommand(.activate, in: experience),
            .selectionChanged(.exactArtifact("whisper-small-q8_0"))
        )
        XCTAssertEqual(
            state.selection,
            .exactArtifact("whisper-small-q8_0")
        )

        _ = state.handleKeyboardCommand(.end, in: experience)
        XCTAssertEqual(
            state.focusedRowID,
            .exactArtifact("whisper-tiny-f16")
        )
        _ = state.handleKeyboardCommand(.home, in: experience)
        XCTAssertEqual(state.focusedRowID, .family("family.whisper"))
        _ = state.handleKeyboardCommand(.moveDown, in: experience)
        _ = state.handleKeyboardCommand(.moveUp, in: experience)
        XCTAssertEqual(state.focusedRowID, .family("family.whisper"))
    }

    func testKeyboardDisclosureAndExactDeletionUseFocusedHierarchyState() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            experience.families.first?.checkpoints.first
        )
        var state = ModelCatalogHierarchyState(
            selection: .checkpoint(checkpoint.id),
            focusedRowID: .checkpoint(checkpoint.id)
        )

        XCTAssertEqual(
            state.handleKeyboardCommand(.expand, in: experience),
            .disclosureChanged(checkpointID: checkpoint.id, isExpanded: true)
        )
        XCTAssertTrue(state.expandedCheckpointIDs.contains(checkpoint.id))

        _ = state.handleKeyboardCommand(.moveDown, in: experience)
        XCTAssertEqual(
            state.handleKeyboardCommand(.activate, in: experience),
            .selectionChanged(.exactArtifact("whisper-small-q5_1"))
        )
        XCTAssertEqual(
            state.handleKeyboardCommand(.deleteSelection, in: experience),
            .requestDeletion
        )

        XCTAssertEqual(
            state.handleKeyboardCommand(.collapse, in: experience),
            .disclosureChanged(checkpointID: checkpoint.id, isExpanded: false)
        )
        XCTAssertEqual(state.focusedRowID, .checkpoint(checkpoint.id))
        XCTAssertEqual(state.selection, .checkpoint(checkpoint.id))
        XCTAssertEqual(
            state.handleKeyboardCommand(.deleteSelection, in: experience),
            .none
        )
    }

    func testPinnedRevealParticipatesInKeyboardOrderWhenItsArtifactIsFilteredOut() throws {
        var query = ModelCatalogQuery(searchText: "tiny")
        query.revealedArtifactID = "whisper-small-q5_1"
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            query: query
        )
        var state = ModelCatalogHierarchyState()

        _ = state.handleKeyboardCommand(.home, in: experience)

        XCTAssertEqual(
            state.focusedRowID,
            .exactArtifact("whisper-small-q5_1")
        )
        XCTAssertEqual(
            state.scrollAnchorID,
            .exactArtifact("whisper-small-q5_1")
        )
        XCTAssertEqual(
            state.handleKeyboardCommand(.activate, in: experience),
            .selectionChanged(.exactArtifact("whisper-small-q5_1"))
        )
    }

    func testCatalogAccessibilityRowsExposeHierarchyDisclosureAndLogicalPosition() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(
            experience.families.first?.checkpoints.first
        )
        let state = ModelCatalogHierarchyState(
            expandedCheckpointIDs: [checkpoint.id]
        )

        let rows = state.accessibilityRows(in: experience)

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].role, .familyHeading)
        XCTAssertEqual(rows[0].outlineLevel, 1)
        XCTAssertEqual(rows[0].logicalPosition, 1)
        XCTAssertEqual(rows[0].logicalCount, 5)
        XCTAssertEqual(rows[1].role, .checkpoint)
        XCTAssertEqual(rows[1].outlineLevel, 2)
        XCTAssertEqual(rows[1].disclosureState, .expanded)
        XCTAssertEqual(rows[1].disclosureState?.accessibilityLabel, "Expanded")
        XCTAssertEqual(
            ModelCatalogAccessibilityDisclosureState.collapsed
                .accessibilityLabel,
            "Collapsed"
        )
        XCTAssertEqual(rows[2].role, .exactArtifact)
        XCTAssertEqual(rows[2].outlineLevel, 3)
        XCTAssertEqual(rows[2].logicalPosition, 3)
        XCTAssertEqual(
            ModelCatalogAccessibilityTableHeader.allCases.map(\.label),
            ["Model", "Quality", "Speed", "Features", "State", "Action"]
        )
    }

    func testDownloadProgressIsQueryableWithoutAnnouncingTicks() {
        let initial = ModelInstallQueueAttempt(
            id: "attempt-1",
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            createdAt: "2026-07-24T10:00:00Z",
            state: DownloadState(
                modelID: "artifact-a",
                phase: .downloading,
                bytesDownloaded: 25,
                totalBytes: 100
            )
        )
        var tracker = ModelCatalogAnnouncementTracker()

        XCTAssertEqual(tracker.update(attempts: [initial]), [])

        let progressTick = ModelInstallQueueAttempt(
            id: initial.id,
            artifactID: initial.artifactID,
            purpose: initial.purpose,
            action: initial.action,
            createdAt: initial.createdAt,
            state: DownloadState(
                modelID: "artifact-a",
                phase: .downloading,
                bytesDownloaded: 50,
                totalBytes: 100
            )
        )
        XCTAssertEqual(tracker.update(attempts: [progressTick]), [])
        XCTAssertEqual(
            ModelCatalogInstallPresentation(
                state: progressTick.state
            ).accessibilityValue,
            "Downloading model, 50%. 50 bytes of 100 bytes"
        )

        let completed = ModelInstallQueueAttempt(
            id: initial.id,
            artifactID: initial.artifactID,
            purpose: initial.purpose,
            action: initial.action,
            createdAt: initial.createdAt,
            state: DownloadState(
                modelID: "artifact-a",
                phase: .installed,
                bytesDownloaded: 100,
                totalBytes: 100
            )
        )
        XCTAssertEqual(
            tracker.update(attempts: [completed]),
            ["artifact-a installation completed."]
        )
        XCTAssertEqual(tracker.update(attempts: [completed]), [])
    }

    func testTerminalDownloadAnnouncementsAreConciseAndDistinct() {
        let terminalPhases: [(DownloadPhase, String)] = [
            (.failed, "artifact-a installation failed."),
            (.cancelled, "artifact-a installation cancelled."),
            (.revoked, "artifact-a installation revoked."),
        ]

        for (phase, expected) in terminalPhases {
            var tracker = ModelCatalogAnnouncementTracker()
            let active = ModelInstallQueueAttempt(
                id: "attempt-\(phase.rawValue)",
                artifactID: "artifact-a",
                purpose: .transcription,
                action: .install,
                createdAt: "2026-07-24T10:00:00Z",
                state: DownloadState(
                    modelID: "artifact-a",
                    phase: .downloading
                )
            )
            _ = tracker.update(attempts: [active])
            let terminal = ModelInstallQueueAttempt(
                id: active.id,
                artifactID: active.artifactID,
                purpose: active.purpose,
                action: active.action,
                createdAt: active.createdAt,
                state: DownloadState(
                    modelID: active.artifactID,
                    phase: phase
                )
            )

            XCTAssertEqual(
                tracker.update(attempts: [terminal]),
                [expected]
            )
        }
    }

    func testCollapsingCheckpointPromotesChildViewportAnchors() throws {
        let experience = ModelCatalogExperience(
            trustedManifest: try signedV3FixtureManifest(),
            installedRecords: [],
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil
        )
        let checkpoint = try XCTUnwrap(experience.families.first?.checkpoints.first)
        var state = ModelCatalogHierarchyState(
            expandedCheckpointIDs: [checkpoint.id],
            focusedRowID: .exactArtifact("whisper-small-q8_0"),
            scrollAnchorID: .exactArtifact("whisper-small-q5_1")
        )

        state.toggleExpansion(of: checkpoint)

        XCTAssertEqual(state.focusedRowID, .checkpoint(checkpoint.id))
        XCTAssertEqual(state.scrollAnchorID, .checkpoint(checkpoint.id))
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
            ),
            storageInventoryByModelID: [
                installedModel.id: ModelStorageArtifactInventory(
                    artifactID: installedModel.id,
                    installationReceiptPresent: true,
                    onDiskBytes: 4_096,
                    presentExpectedFileCount: 1,
                    expectedFileCount: 1,
                    missingExpectedRelativePaths: [],
                    sizeMismatchRelativePaths: [],
                    unexpectedFileCount: 1,
                    condition: .complete
                ),
            ]
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
        let sourceAndLicense = try XCTUnwrap(artifact.sourceAndLicense)
        XCTAssertEqual(sourceAndLicense.sourceName, "Fixture")
        XCTAssertEqual(sourceAndLicense.originalModelName, "Whisper Small")
        XCTAssertEqual(sourceAndLicense.sourceRevision, "1234567890abcdef1234567890abcdef12345678")
        XCTAssertEqual(
            sourceAndLicense.files,
            [
                ModelSourceLicensePresentation.SignedFile(
                    filename: "model.bin",
                    relativePath: nil,
                    sha256: "66bd26882020db56790522008135dfc28268bac4ed7ebce49086c7179bd2f868",
                    sizeBytes: 33
                ),
            ]
        )
        XCTAssertEqual(
            sourceAndLicense.licenses,
            [
                ModelSourceLicensePresentation.License(
                    scope: "model",
                    spdxID: "MIT",
                    name: "MIT License",
                    licenseTextURL: "https://example.com/licenses/whisper-small-q5_1.txt"
                ),
            ]
        )
        XCTAssertTrue(artifact.canVerify)
        XCTAssertEqual(artifact.localDetails?.allocatedBytes, 4_096)
        XCTAssertEqual(artifact.localDetails?.unexpectedFileCount, 1)
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
            query: ModelCatalogQuery(numericFormats: [.bf16])
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

    func testPrimaryCatalogRowCompactLayoutLabelsEveryFormerColumn() {
        XCTAssertTrue(ModelCatalogPrimaryRowLayout.wide.showsTableHeader)
        XCTAssertFalse(ModelCatalogPrimaryRowLayout.compact.showsTableHeader)
    }

    func testAccessibilityDisplayPreferencesKeepSelectionNonColor() {
        let standard = ModelCatalogAccessibleAppearance()
        let accessible = ModelCatalogAccessibleAppearance(
            increaseContrast: true,
            differentiateWithoutColor: true
        )

        XCTAssertFalse(standard.requiresSelectionBorder)
        XCTAssertTrue(accessible.requiresSelectionBorder)
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
    func testInspectorUsesLatestImmutableLocalDetailsAfterSelectionChanges() throws {
        let manifest = try signedV3FixtureManifest()
        let installedModels = try [
            XCTUnwrap(manifest.models.first { $0.id == "whisper-small-q5_1" }),
            XCTUnwrap(manifest.models.first { $0.id == "whisper-small-q8_0" }),
        ]
        let inventories = Dictionary(
            uniqueKeysWithValues: installedModels.enumerated().map { index, model in
                (
                    model.id,
                    ModelStorageArtifactInventory(
                        artifactID: model.id,
                        installationReceiptPresent: true,
                        onDiskBytes: Int64((index + 1) * 40),
                        presentExpectedFileCount: 1,
                        expectedFileCount: 1,
                        missingExpectedRelativePaths: [],
                        sizeMismatchRelativePaths: [],
                        unexpectedFileCount: index,
                        condition: .complete
                    )
                )
            }
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: installedModels.map(installed),
            activePreferences: ModelCatalogActivePreferences(),
            transferState: nil,
            storageInventoryByModelID: inventories
        )
        let controller = ModelCatalogInspectorController()

        controller.select(.exactArtifact("whisper-small-q5_1"), in: experience)
        XCTAssertEqual(
            controller.localDetailsState,
            .loaded(ModelCatalogArtifactLocalDetails(
                inventory: try XCTUnwrap(inventories["whisper-small-q5_1"])
            ))
        )

        controller.select(.exactArtifact("whisper-small-q8_0"), in: experience)
        XCTAssertEqual(
            controller.localDetailsState,
            .loaded(ModelCatalogArtifactLocalDetails(
                inventory: try XCTUnwrap(inventories["whisper-small-q8_0"])
            ))
        )
        guard case let .exactArtifact(selected) = controller.presentation else {
            return XCTFail("The latest Exact Artifact must remain selected.")
        }
        XCTAssertEqual(selected.id, "whisper-small-q8_0")
    }

    @MainActor
    func testInstalledInspectorUsesExplicitMissingMeasurementStates() throws {
        let manifest = try signedV3FixtureManifest()
        let model = try XCTUnwrap(
            manifest.models.first { $0.id == "whisper-small-q5_1" }
        )

        for (status, expectedState) in [
            (
                ModelCatalogInstalledSizeStatus.calculating,
                ModelCatalogInspectorLocalDetailsState.loading(
                    artifactID: model.id
                )
            ),
            (
                ModelCatalogInstalledSizeStatus.unavailable,
                ModelCatalogInspectorLocalDetailsState.failed(
                    artifactID: model.id
                )
            ),
        ] {
            let experience = ModelCatalogExperience(
                trustedManifest: manifest,
                installedRecords: [installed(model)],
                activePreferences: ModelCatalogActivePreferences(),
                transferState: nil,
                installedSizeStatus: status
            )
            let controller = ModelCatalogInspectorController()

            controller.select(.exactArtifact(model.id), in: experience)

            XCTAssertEqual(controller.localDetailsState, expectedState)
        }
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

    func testSnapshotLocalDetailsDoNotClaimFullVerification() async throws {
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

        let details = ModelCatalogArtifactLocalDetails(
            inventory: ModelStorageArtifactInventory(
                artifactID: "fixture",
                installationReceiptPresent: true,
                onDiskBytes: 4_096,
                presentExpectedFileCount: 1,
                expectedFileCount: 1,
                missingExpectedRelativePaths: [],
                sizeMismatchRelativePaths: [],
                unexpectedFileCount: 0,
                condition: .complete
            )
        )

        XCTAssertEqual(details.artifactID, "fixture")
        XCTAssertEqual(details.presentFileCount, 1)
        XCTAssertEqual(details.expectedFileCount, 1)
        XCTAssertEqual(details.allocatedBytes, 4_096)
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

    private func reversedCatalogArraysManifest() throws -> ModelManifest {
        let manifestURL = repositoryRoot.appendingPathComponent("models/manifest.json")
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
                as? [String: Any]
        )
        var graph = try XCTUnwrap(root["presentationGraph"] as? [String: Any])
        var families = try XCTUnwrap(graph["families"] as? [[String: Any]])
        for index in families.indices {
            let checkpointIDs = try XCTUnwrap(
                families[index]["checkpointIDs"] as? [String]
            )
            families[index]["checkpointIDs"] = Array(checkpointIDs.reversed())
        }
        var checkpoints = try XCTUnwrap(graph["checkpoints"] as? [[String: Any]])
        for index in checkpoints.indices {
            let artifactIDs = try XCTUnwrap(
                checkpoints[index]["artifactIDs"] as? [String]
            )
            checkpoints[index]["artifactIDs"] = Array(artifactIDs.reversed())
        }
        graph["families"] = Array(families.reversed())
        graph["checkpoints"] = checkpoints
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
        engine: TranscriptionEngine = .whisperCpp,
        sha256: String = String(repeating: "a", count: 64)
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
                    sha256: sha256,
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
