import CryptoKit
import XCTest
@testable import Textify
import TextifyAudio
import TextifyDiagnostics
@testable import TextifyHotkeys
import TextifyInsertion
import TextifyModels
import TextifyRuntime
import TextifySettings
import TextifyTranscription

final class AppCompositionTests: XCTestCase {
    func testAppDelegateActivationPolicyFollowsKeepInDockPreference() {
        var preferences = AppPreferences.defaults
        preferences.keepTextifyInDock = false
        XCTAssertEqual(AppDelegate.activationPolicy(preferences: preferences), .accessory)

        preferences.keepTextifyInDock = true
        XCTAssertEqual(AppDelegate.activationPolicy(preferences: preferences), .regular)
    }

    func testAppDelegateActivationPolicyFallsBackToRegularWhenSettingsPathFails() {
        let policy = AppDelegate.activationPolicy(
            pathFactory: { throw AppPathFixtureError.unavailable }
        )

        XCTAssertEqual(policy, .regular)
    }

    func testDockReopenPolicyUsesMainWindowVisibilityInsteadOfAnyVisibleOverlay() {
        XCTAssertEqual(AppReopenPolicy.action(isMainWindowVisible: false), .openMainWindow)
        XCTAssertEqual(AppReopenPolicy.action(isMainWindowVisible: true), .focusVisibleWindow)
    }

    @MainActor
    func testClosingMainWindowEndsCatalogPresentationSession() async throws {
        let services = try Self.makeServices()
        let feature = services.modelCatalogFeature(
            for: .transcription
        )
        await feature.waitUntilSettled()
        let retainedSnapshot = feature.snapshot
        feature.discoveryQuery.searchText = "whisper"
        feature.showsInspector = true
        feature.hierarchyState.scroll(
            to: .exactArtifact("retained-before-close")
        )
        let delegate = TextifyMainWindowSessionDelegate {
            services.resetModelCatalogPresentationSession()
        }

        delegate.windowWillClose(
            Notification(name: NSWindow.willCloseNotification)
        )

        let resetFeature = services.modelCatalogFeature(
            for: .transcription
        )
        XCTAssertFalse(feature === resetFeature)
        XCTAssertEqual(resetFeature.snapshot, retainedSnapshot)
        XCTAssertEqual(resetFeature.discoveryQuery.searchText, "")
        XCTAssertFalse(resetFeature.showsInspector)
        XCTAssertNil(resetFeature.hierarchyState.scrollAnchorID)
    }

    func testClosingLastWindowDoesNotTerminateTextify() {
        XCTAssertFalse(
            AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        )
    }

    @MainActor
    func testAppDelegateOpenMainWindowUsesConfiguredPresenter() {
        let previousOpener = AppDelegate.mainWindowOpener
        defer {
            AppDelegate.mainWindowOpener = previousOpener
        }
        var openCount = 0
        AppDelegate.mainWindowOpener = {
            openCount += 1
        }

        AppDelegate.openMainWindow()

        XCTAssertEqual(openCount, 1)
    }

    @MainActor
    func testBecomingActiveRequestsStorageInventoryRefresh() {
        let previousRefresh = AppDelegate.modelStorageRefreshProvider
        defer {
            AppDelegate.modelStorageRefreshProvider = previousRefresh
        }
        var refreshCount = 0
        AppDelegate.modelStorageRefreshProvider = {
            refreshCount += 1
        }

        AppDelegate().applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )

        XCTAssertEqual(refreshCount, 1)
    }

    @MainActor
    func testProductionCompositionBuildsRuntimeServices() throws {
        let paths = try Self.makeTemporaryPaths()
        let services = AppServices.production(
            pathFactory: { paths },
            launchAtLogin: FakeLaunchAtLoginManager(status: .disabled),
            launchAtLoginLocation: FixedLaunchAtLoginLocation(isSupported: true)
        )

        XCTAssertEqual(services.paths.settingsFileURL.lastPathComponent, "settings.json")
        XCTAssertEqual(services.preferences, services.settingsStore.load())
        XCTAssertEqual(services.dictation.status, DictationRuntimeStatus.idle)
    }

    func testRetiredOmnilingualCleanupPurgesManagedStateAndIsIdempotent() throws {
        let paths = try Self.makeTemporaryPaths()
        let layout = ModelStorageLayout(
            rootDirectory: paths.modelsDirectory
        )
        let retired = try Self.retiredOmnilingualModel()
        let retained = try Self.catalogModel(
            id: "ggml-small.en-q5_1"
        )
        _ = try Self.writeInstalledArtifacts(
            [retired, retained],
            to: paths
        )

        let settingsStore = SettingsStore(
            storage: .file(paths.settingsFileURL)
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = retired.id
        preferences.modelArtifactOverridesByPurposeCheckpoint = [
            "transcription|retired": retired.id,
            "transcription|retained": retained.id,
        ]
        settingsStore.save(preferences)

        var queue = ModelInstallQueue(
            attempts: [
                ModelInstallQueueAttempt(
                    id: "retired-attempt",
                    artifactID: retired.id,
                    authorizedArtifactIdentity:
                        ModelInstallArtifactIdentity(model: retired),
                    purpose: .transcription,
                    action: .install,
                    createdAt: "2026-07-28T00:00:00Z",
                    state: DownloadState(
                        modelID: retired.id,
                        phase: .downloading,
                        bytesDownloaded: 4,
                        totalBytes: retired.sizeBytes
                    ),
                    resumableData: ModelInstallResumableData(
                        sourceAttemptID: "retired-attempt",
                        associatedAttemptID: "retired-attempt",
                        validatedBytes: 4,
                        fileCount: 1,
                        filenames: retired.files.map(\.filename)
                    )
                ),
                ModelInstallQueueAttempt(
                    id: "retained-attempt",
                    artifactID: retained.id,
                    purpose: .transcription,
                    action: .install,
                    createdAt: "2026-07-28T00:01:00Z",
                    state: DownloadState(
                        modelID: retained.id,
                        phase: .cancelled
                    )
                ),
            ]
        )
        try ModelInstallQueueStore(
            fileURL: layout.installQueueURL
        ).save(queue)
        queue = try ModelInstallQueueStore(
            fileURL: layout.installQueueURL
        ).load()
        XCTAssertEqual(queue.attempts.count, 2)

        try FileManager.default.createDirectory(
            at: layout.downloadsDirectory,
            withIntermediateDirectories: true
        )
        for file in retired.files {
            try Data("partial".utf8).write(
                to: layout.temporaryDownloadURL(
                    modelID: retired.id,
                    filename: file.filename
                )
            )
            try Data("resume".utf8).write(
                to: layout.downloadResumeMetadataURL(
                    modelID: retired.id,
                    filename: file.filename
                )
            )
        }
        let stagingDirectory = layout.downloadsDirectory
            .appendingPathComponent(
                ".\(retired.id).installing-test",
                isDirectory: true
            )
        let retainedDirectory = layout.downloadsDirectory
            .appendingPathComponent(
                ".\(retired.id).retained-test",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: retainedDirectory,
            withIntermediateDirectories: true
        )

        try RetiredManagedModelCleanup.omnilingualASR300M.run(
            settingsStore: settingsStore,
            layout: layout
        )
        try RetiredManagedModelCleanup.omnilingualASR300M.run(
            settingsStore: settingsStore,
            layout: layout
        )

        let reloadedPreferences = settingsStore.load()
        XCTAssertNil(reloadedPreferences.activeModelID)
        XCTAssertEqual(
            reloadedPreferences
                .modelArtifactOverridesByPurposeCheckpoint,
            ["transcription|retained": retained.id]
        )
        let reloadedQueue = try ModelInstallQueueStore(
            fileURL: layout.installQueueURL
        ).load()
        XCTAssertEqual(
            reloadedQueue.attempts.map(\.id),
            ["retained-attempt"]
        )
        let installed = try InstalledModelsStorePersistence(
            fileURL: layout.installedStoreURL
        ).load()
        XCTAssertNil(installed.record(forModelID: retired.id))
        XCTAssertNotNil(installed.record(forModelID: retained.id))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: try layout.installedModelDirectory(
                    modelID: retired.id
                ).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try layout.installedModelDirectory(
                    modelID: retained.id
                ).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: stagingDirectory.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: retainedDirectory.path
            )
        )
        for file in retired.files {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: try layout.temporaryDownloadURL(
                        modelID: retired.id,
                        filename: file.filename
                    ).path
                )
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: try layout.downloadResumeMetadataURL(
                        modelID: retired.id,
                        filename: file.filename
                    ).path
                )
            )
        }
    }

    func testRetiredOmnilingualCleanupKeepsDataWhenActivePreferenceCannotPersist() throws {
        let paths = try Self.makeTemporaryPaths()
        let retired = try Self.retiredOmnilingualModel()
        let directories = try Self.writeInstalledArtifacts(
            [retired],
            to: paths
        )
        let writableStore = SettingsStore(
            storage: .file(paths.settingsFileURL)
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = retired.id
        writableStore.save(preferences)
        let failingFileManager = FailingSettingsSaveFileManager()
        let failingStore = SettingsStore(
            storage: .file(paths.settingsFileURL),
            fileManager: failingFileManager
        )

        XCTAssertThrowsError(
            try RetiredManagedModelCleanup.omnilingualASR300M.run(
                settingsStore: failingStore,
                layout: ModelStorageLayout(
                    rootDirectory: paths.modelsDirectory
                ),
                fileManager: failingFileManager
            )
        ) { error in
            XCTAssertEqual(
                error as? RetiredManagedModelCleanupError,
                .preferencePersistenceFailed
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(directories[retired.id]).path
            )
        )
        let installed = try InstalledModelsStorePersistence(
            fileURL: ModelStorageLayout(
                rootDirectory: paths.modelsDirectory
            ).installedStoreURL
        ).load()
        XCTAssertNotNil(installed.record(forModelID: retired.id))
    }

    @MainActor
    func testApplicationCompositionProvidesOnePurposeScopedCatalogExperience() async throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models/manifest.json")
        let manifest = try ModelManifest.decode(Data(contentsOf: manifestURL))
        let compatibilityResolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_589_934_592
            )
        )
        let services = try Self.makeServices(
            modelCatalogCompatibilityResolver: compatibilityResolver
        )
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            loadOperation: { manifest }
        )
        await services.modelCatalogCoordinator.refresh()

        let transcription = services.modelCatalogExperience(
            for: .transcription
        )
        let cleaning = services.modelCatalogExperience(
            for: .voiceCleaning
        )

        XCTAssertTrue(
            transcription.rows.allSatisfy { $0.model.purpose == .transcription }
        )
        XCTAssertTrue(
            cleaning.rows.allSatisfy { $0.model.purpose == .voiceCleaning }
        )
        XCTAssertFalse(cleaning.rows.isEmpty)
        let incompatible = try XCTUnwrap(
            transcription.rows.first { $0.id == "parakeet-rnnt-1.1b" }
        )
        XCTAssertEqual(
            incompatible.compatibility,
            .incompatible(
                .insufficientMemory(
                    requiredBytes: 17_179_869_184,
                    availableBytes: 8_589_934_592
                )
            )
        )
        XCTAssertFalse(incompatible.compatibility.allowsModelOperations)
        XCTAssertTrue(
            services.modelCatalogCompatibilityResolver === compatibilityResolver
        )
    }

    @MainActor
    func testCatalogExperienceUsesMeasuredOnDiskBytesWhenAvailable() async throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models/manifest.json")
        let manifest = try ModelManifest.decode(Data(contentsOf: manifestURL))
        let smallerID = "qwen3-asr-0.6b-q8-0"
        let largerID = "qwen3-asr-1.7b-q8-0"
        let installed = try [smallerID, largerID].map { modelID in
            try XCTUnwrap(manifest.models.first { $0.id == modelID })
        }
        let paths = try Self.makeTemporaryPaths()
        try Self.writeInstalledStore(models: installed, to: paths)
        let services = try Self.makeServices(paths: paths)
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            loadOperation: { manifest }
        )
        await services.modelCatalogCoordinator.refresh()

        let experience = services.modelCatalogExperience(
            for: .transcription,
            onDiskBytesByModelID: [
                smallerID: 300,
                largerID: 100,
            ],
            query: ModelCatalogQuery(
                scope: .installed,
                sort: .installedSize,
                sortDirection: .ascending
            )
        )

        XCTAssertEqual(experience.rows.map(\.id), [largerID, smallerID])
        XCTAssertEqual(experience.rows.map(\.onDiskBytes), [100, 300])
    }

    @MainActor
    func testCatalogExperienceConsumesTheLatestStorageInventorySnapshot() async throws {
        let model = try Self.catalogModel(id: "qwen3-asr-0.6b-q8-0")
        let paths = try Self.makeTemporaryPaths()
        let layout = ModelStorageLayout(rootDirectory: paths.modelsDirectory)
        let firstFile = try XCTUnwrap(model.files.first)
        let installedURL = try layout.installedArtifactURL(
            modelID: model.id,
            relativePath: firstFile.relativePath ?? firstFile.filename
        )
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 1, count: 8_192).write(to: installedURL)
        let record = InstalledModelRecord(
            model: model,
            installedAt: "2026-07-24T00:00:00Z",
            localFilesByManifestFilename: [
                firstFile.filename: installedURL.path,
            ]
        )
        try JSONEncoder().encode(
            InstalledModelsStore(records: [record])
        ).write(to: layout.installedStoreURL, options: .atomic)
        let services = try Self.makeServices(paths: paths)

        for _ in 0..<200 {
            if case .available = services.modelStorageInventory.state {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .available = services.modelStorageInventory.state else {
            return XCTFail("Expected the launch inventory refresh to finish.")
        }

        let experience = services.modelCatalogExperience(
            for: .transcription,
            query: ModelCatalogQuery(scope: .installed)
        )
        let row = try XCTUnwrap(experience.rows.first { $0.id == model.id })
        XCTAssertEqual(row.sizeLabel, "On Disk")
        XCTAssertNotNil(row.onDiskBytes)
        XCTAssertTrue(row.sizeDescription.hasPrefix("About "))
        XCTAssertTrue(row.stateTokens.contains(.needsRepair))
        XCTAssertEqual(row.storageInventory?.onDiskBytes, row.onDiskBytes)
        XCTAssertEqual(
            row.storageInventory?.missingExpectedRelativePaths,
            Array(model.files.dropFirst()).map {
                $0.relativePath ?? $0.filename
            }
        )
    }

    @MainActor
    func testPurposeCatalogKeepsInstalledModelsWhenTrustOrCompatibilityChanges() async throws {
        let paths = try Self.makeTemporaryPaths()
        let removedModel = try Self.catalogModel(id: "parakeet-rnnt-1.1b")
        let storeURL = ModelStorageLayout(rootDirectory: paths.modelsDirectory).installedStoreURL
        try JSONEncoder().encode(
            InstalledModelsStore(records: [
                InstalledModelRecord(
                    model: removedModel,
                    installedAt: "2026-07-24T00:00:00Z",
                    localFilesByManifestFilename: [:]
                ),
            ])
        ).write(to: storeURL, options: .atomic)
        let resolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_589_934_592
            )
        )
        let services = try Self.makeServices(
            paths: paths,
            modelCatalogCompatibilityResolver: resolver
        )
        await services.refreshManagedModelReadiness()

        let unavailableCatalog = services.modelCatalogExperience(for: .transcription)
        XCTAssertEqual(unavailableCatalog.rows.map(\.id), [removedModel.id])
        XCTAssertTrue(unavailableCatalog.rows[0].isInstalled)
        XCTAssertEqual(
            unavailableCatalog.rows[0].stateTokens,
            [.installed, .needsRepair]
        )
        XCTAssertFalse(unavailableCatalog.rows[0].actions.contains(.use))
        XCTAssertTrue(
            ModelCatalogHierarchyState()
                .visibleRows(in: unavailableCatalog)
                .contains { hierarchyRow in
                    guard case let .standaloneArtifact(row) = hierarchyRow.content else {
                        return false
                    }
                    return row.id == removedModel.id && row.isInstalled
                }
        )

        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models/manifest.json")
        let manifest = try ModelManifest.decode(Data(contentsOf: manifestURL))
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            loadOperation: { manifest }
        )
        await services.modelCatalogCoordinator.refresh()

        let incompatibleCatalog = services.modelCatalogExperience(for: .transcription)
        XCTAssertTrue(incompatibleCatalog.rows.contains { row in
            row.id == removedModel.id && row.isInstalled
        })
        XCTAssertTrue(
            ModelCatalogHierarchyState()
                .visibleRows(in: incompatibleCatalog)
                .contains { hierarchyRow in
                    guard case let .exactArtifact(_, artifact, _) = hierarchyRow.content else {
                        return false
                    }
                    return artifact.id == removedModel.id && artifact.row.isInstalled
                }
        )
    }

    @MainActor
    func testManagedReadinessRevalidatesChecksumFailureAcrossRelaunch() async throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(id: "whisper-large-v2-q5_0")
        try Self.writeInstalledStore(models: [model], to: paths)
        let failedReadiness = RuntimeModelReadiness.failed(
            modelID: model.id,
            reason: .checksumFailed
        )
        let runtimeModel = Self.runtimeModel(model)
        let services = try Self.makeServices(
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [runtimeModel],
                readinessByModelID: [model.id: failedReadiness]
            )
        )

        await services.refreshManagedModelReadiness()

        let firstRow = try XCTUnwrap(
            services.modelCatalogExperience(for: .transcription)
                .rows.first(where: { $0.id == model.id })
        )
        XCTAssertEqual(firstRow.stateTokens, [.installed, .needsRepair])
        XCTAssertFalse(firstRow.actions.contains(.use))

        let relaunched = try Self.makeServices(
            preferences: nil,
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [runtimeModel],
                readinessByModelID: [model.id: failedReadiness]
            )
        )
        await relaunched.refreshManagedModelReadiness()

        let relaunchedRow = try XCTUnwrap(
            relaunched.modelCatalogExperience(for: .transcription)
                .rows.first(where: { $0.id == model.id })
        )
        XCTAssertEqual(
            relaunchedRow.stateTokens,
            [.installed, .needsRepair]
        )
        XCTAssertFalse(relaunchedRow.actions.contains(.use))
    }

    @MainActor
    func testInstalledModelQueriesUseCachedStoreUntilExplicitRefresh() throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(id: ProductionModelPolicy.requiredModelID)
        let storeURL = ModelStorageLayout(rootDirectory: paths.modelsDirectory).installedStoreURL
        let installedStore = InstalledModelsStore(records: [
            InstalledModelRecord(
                model: model,
                installedAt: "2026-07-20T00:00:00Z",
                localFilesByManifestFilename: ["model.bin": "/tmp/model.bin"]
            ),
        ])
        try JSONEncoder().encode(installedStore).write(to: storeURL, options: .atomic)

        let services = try Self.makeServices(paths: paths)

        XCTAssertTrue(services.isModelInstalled(model.id))
        XCTAssertEqual(services.installedModels.map(\.id), [model.id])

        try JSONEncoder().encode(InstalledModelsStore()).write(to: storeURL, options: .atomic)

        XCTAssertTrue(services.isModelInstalled(model.id))
        services.refreshInstalledModels()
        XCTAssertFalse(services.isModelInstalled(model.id))
        XCTAssertTrue(services.installedModels.isEmpty)
    }

    @MainActor
    func testTrustedCatalogCanonicalizationPersistsRecordHistoryAndActivePreference() throws {
        let paths = try Self.makeTemporaryPaths()
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models/manifest.json")
        let manifest = try ModelManifest.decode(Data(contentsOf: manifestURL))
        let signed = try XCTUnwrap(
            manifest.models.first {
                $0.id == ProductionModelPolicy.requiredModelID
            }
        )
        let digest = try XCTUnwrap(signed.artifactTypedDigests().first)
        let customID = CustomWhisperModelImporter.importedModelIDPrefix + digest.value
        let custom = Self.copyModel(
            signed,
            id: customID,
            displayName: "My Imported Name"
        )
        let record = InstalledModelRecord(
            model: custom,
            installedAt: "2026-07-24T00:00:00Z",
            localFilesByManifestFilename: [
                signed.files[0].filename: "/tmp/\(customID)/model.bin",
            ],
            identityHistory: InstalledModelIdentityHistory(
                customImport: CustomModelImportHistory(
                    contentDigest: digest,
                    localNames: ["My Imported Name"],
                    sourceFilenames: ["renamed.ggml"]
                )
            )
        )
        let storeURL = ModelStorageLayout(
            rootDirectory: paths.modelsDirectory
        ).installedStoreURL
        try JSONEncoder().encode(
            InstalledModelsStore(records: [record])
        ).write(to: storeURL, options: .atomic)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = customID
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths
        )

        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest }
        )

        XCTAssertEqual(services.installedModelRecords.map(\.model.id), [signed.id])
        XCTAssertEqual(services.preferences.activeModelID, signed.id)
        let persisted = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: storeURL)
        )
        XCTAssertEqual(persisted.records.first?.model.id, signed.id)
        XCTAssertEqual(
            persisted.records.first?.identityHistory.customImport?.localNames,
            ["My Imported Name"]
        )
    }

    @MainActor
    func testFailedActivationRollsBackNewImmediatelyCanonicalizedImport() async throws {
        let paths = try Self.makeTemporaryPaths()
        let layout = ModelStorageLayout(rootDirectory: paths.modelsDirectory)
        var sourceData = Data(
            repeating: 0,
            count: Int(CustomWhisperModelImporter.minimumFileSizeBytes)
        )
        sourceData.replaceSubrange(0..<4, with: Data("GGUF".utf8))
        let digest = SHA256.hash(data: sourceData).map {
            String(format: "%02x", $0)
        }.joined()
        let sourceURL = paths.settingsFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("local-import.gguf")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sourceData.write(to: sourceURL)
        let sourceModel = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let signedModel = Self.copyModel(
            sourceModel,
            id: "signed-local-import",
            displayName: "Signed Local Match",
            sizeBytes: Int64(sourceData.count),
            files: [
                ModelFile(
                    filename: "canonical.gguf",
                    url: "https://example.com/canonical.gguf",
                    sha256: digest,
                    sizeBytes: Int64(sourceData.count)
                ),
            ]
        )
        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-24T00:00:00Z",
            models: [signedModel]
        )
        let services = try Self.makeServices(paths: paths)
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest }
        )

        do {
            _ = try await services.importCustomWhisperModel(
                from: sourceURL,
                displayName: "Local Import"
            )
            XCTFail("Expected activation to fail.")
        } catch ModelInstallCoordinatorError.modelPreparationFailed {
        } catch {
            XCTFail("Unexpected import error: \(error)")
        }

        let storageModelID =
            CustomWhisperModelImporter.importedModelIDPrefix + digest
        XCTAssertFalse(services.isModelInstalled(signedModel.id))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: try layout.installedModelDirectory(
                    modelID: storageModelID
                ).path
            )
        )
        let store = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertTrue(store.records.isEmpty)
    }

    @MainActor
    func testRevokedCustomReimportPreservesInstallAndNeverAutoActivates() async throws {
        let paths = try Self.makeTemporaryPaths()
        let layout = ModelStorageLayout(rootDirectory: paths.modelsDirectory)
        var sourceData = Data(
            repeating: 0,
            count: Int(CustomWhisperModelImporter.minimumFileSizeBytes)
        )
        sourceData.replaceSubrange(0..<4, with: Data("GGUF".utf8))
        let sourceDirectory = paths.settingsFileURL.deletingLastPathComponent()
        let originalURL = sourceDirectory.appendingPathComponent("original.gguf")
        let renamedURL = sourceDirectory.appendingPathComponent("renamed.gguf")
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try sourceData.write(to: originalURL)
        try sourceData.write(to: renamedURL)
        let firstRecord = try await CustomWhisperModelImporter(
            layout: layout,
            nowISO8601: { "2026-07-24T00:00:00Z" }
        ).importModel(
            from: originalURL,
            options: CustomWhisperImportOptions(
                displayName: "Original Local Name",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )
        let digest = try XCTUnwrap(
            firstRecord.identityHistory.customImport?.contentDigest.value
        )
        let transcriber = ActivationTranscriberSpy()
        let services = try Self.makeServices(
            paths: paths,
            transcriber: transcriber
        )
        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-24T00:00:00Z",
            models: []
        )
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest },
            initialRevocationState: try ModelRevocationTestFixture.state(
                records: [
                    ModelRevocationRecord(
                        recordID: "custom-digest-revocation",
                        contentDigest: ModelRevocationDigestTarget(
                            algorithm: .sha256,
                            value: digest,
                            scope: .singleFilePayload
                        )
                    ),
                ]
            )
        )

        do {
            _ = try await services.importCustomWhisperModel(
                from: renamedURL,
                displayName: "Renamed Local Model"
            )
            XCTFail("Expected revoked reimport activation to fail.")
        } catch ModelInstallCoordinatorError.modelPreparationFailed {
        } catch {
            XCTFail("Unexpected import error: \(error)")
        }

        let storedRecord = try XCTUnwrap(
            services.installedModelRecords.first
        )
        XCTAssertEqual(storedRecord.storageModelID, firstRecord.storageModelID)
        XCTAssertEqual(
            storedRecord.identityHistory.customImport?.localNames,
            ["Original Local Name", "Renamed Local Model"]
        )
        XCTAssertEqual(
            storedRecord.identityHistory.customImport?.sourceFilenames,
            ["original.gguf", "renamed.gguf"]
        )
        XCTAssertNil(services.preferences.activeModelID)
        let preparedModelIDs = await transcriber.preparedModelIDs()
        XCTAssertTrue(preparedModelIDs.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(
                    storedRecord.localFilesByManifestFilename.values.first
                )
            )
        )
    }

    @MainActor
    func testVoiceCleanerActivationDoesNotReplaceActiveTranscriptionModel() async throws {
        let paths = try Self.makeTemporaryPaths()
        let transcriptionModel = try Self.catalogModel(id: ProductionModelPolicy.requiredModelID)
        let cleaner = try Self.catalogModel(id: "mossformer2-se-fp16")
        let storeURL = ModelStorageLayout(rootDirectory: paths.modelsDirectory).installedStoreURL
        let installedStore = InstalledModelsStore(records: [
            InstalledModelRecord(
                model: transcriptionModel,
                installedAt: "2026-07-20T00:00:00Z",
                localFilesByManifestFilename: ["model.bin": "/tmp/model.bin"]
            ),
            InstalledModelRecord(
                model: cleaner,
                installedAt: "2026-07-20T00:00:00Z",
                localFilesByManifestFilename: [
                    "config.json": "/tmp/mossformer/config.json",
                    "model.safetensors": "/tmp/mossformer/model.safetensors",
                ]
            ),
        ])
        try JSONEncoder().encode(installedStore).write(to: storeURL, options: .atomic)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = transcriptionModel.id
        let resolver = CandidateRuntimeModelResolver(models: [
            Self.runtimeModel(transcriptionModel),
            Self.runtimeModel(cleaner),
        ])
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: resolver
        )

        let activated = await services.activateInstalledModel(cleaner.id)

        XCTAssertEqual(activated, .activated)
        XCTAssertEqual(services.preferences.activeModelID, transcriptionModel.id)
        XCTAssertEqual(services.preferences.activeVoiceCleaningModelID, cleaner.id)
        XCTAssertTrue(services.isModelActive(cleaner.id))
        await services.disableVoiceCleaning()
        XCTAssertNil(services.preferences.activeVoiceCleaningModelID)
        XCTAssertEqual(services.settingsStore.load().activeModelID, transcriptionModel.id)
    }

    @MainActor
    func testUseCommitsReadyTranscriptionArtifactAndPersistsAcrossRelaunch() async throws {
        let paths = try Self.makeTemporaryPaths()
        let previous = try Self.catalogModel(id: ProductionModelPolicy.requiredModelID)
        let candidate = try Self.catalogModel(id: "whisper-large-v2-q5_0")
        try Self.writeInstalledStore(
            models: [previous, candidate],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = previous.id
        let resolver = CandidateRuntimeModelResolver(models: [
            Self.runtimeModel(previous),
            Self.runtimeModel(candidate),
        ])
        let transcriber = ActivationTranscriberSpy()
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: resolver,
            transcriber: transcriber
        )

        let result = await services.activateInstalledModel(candidate.id)

        XCTAssertEqual(result, .activated)
        XCTAssertEqual(services.preferences.activeModelID, candidate.id)
        XCTAssertEqual(services.settingsStore.load().activeModelID, candidate.id)
        let relaunched = try Self.makeServices(
            preferences: nil,
            paths: paths
        )
        XCTAssertEqual(relaunched.preferences.activeModelID, candidate.id)
    }

    @MainActor
    func testActivationReportsPreparedThenPersistedDurableBoundaries() async throws {
        let paths = try Self.makeTemporaryPaths()
        let candidate = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        try Self.writeInstalledStore(models: [candidate], to: paths)
        let recorder = AppWorkflowBoundaryRecorder()
        let services = try Self.makeServices(
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(candidate)]
            ),
            transcriber: ActivationTranscriberSpy(),
            modelWorkflowDurabilityObserver: recorder.observer
        )

        let result = await services.activateInstalledModel(candidate.id)

        XCTAssertEqual(result, .activated)
        XCTAssertEqual(
            recorder.events.filter {
                [
                    ModelWorkflowDurableBoundary.activationPrepared,
                    .activationPreferencePersisted,
                ].contains($0.boundary)
            },
            [
                AppWorkflowBoundaryEvent(
                    boundary: .activationPrepared,
                    artifactID: candidate.id
                ),
                AppWorkflowBoundaryEvent(
                    boundary: .activationPreferencePersisted,
                    artifactID: candidate.id
                ),
            ]
        )
    }

    @MainActor
    func testActivationWaitsForTheCurrentSegmentBoundary() async throws {
        let paths = try Self.makeTemporaryPaths()
        let previous = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let candidate = try Self.catalogModel(id: "whisper-large-v2-q5_0")
        try Self.writeInstalledStore(
            models: [previous, candidate],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = previous.id
        let transcriber = ActivationTranscriberSpy()
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(models: [
                Self.runtimeModel(previous),
                Self.runtimeModel(candidate),
            ]),
            transcriber: transcriber
        )

        await services.dictation.handleTriggerAction(.beginRecording)
        let activation = Task { @MainActor in
            await services.activateInstalledModel(candidate.id)
        }
        for _ in 0..<100
        where services.dictation.allowsModelTransactions {
            await Task.yield()
        }

        XCTAssertFalse(services.dictation.allowsModelTransactions)
        XCTAssertEqual(services.preferences.activeModelID, previous.id)
        let preparedBeforeBoundary =
            await transcriber.preparedModelIDs()
        XCTAssertTrue(preparedBeforeBoundary.isEmpty)

        await services.dictation.handleTriggerAction(.finishRecording)
        let result = await activation.value

        XCTAssertEqual(result, .activated)
        XCTAssertEqual(services.preferences.activeModelID, candidate.id)
    }

    @MainActor
    func testFailedActivationPreferenceWriteRestoresPreviousIdentity() async throws {
        let paths = try Self.makeTemporaryPaths()
        let previous = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let candidate = try Self.catalogModel(id: "whisper-large-v2-q5_0")
        try Self.writeInstalledStore(
            models: [previous, candidate],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = previous.id
        SettingsStore(storage: .file(paths.settingsFileURL))
            .save(preferences)
        let transcriber = ActivationTranscriberSpy()
        let services = try Self.makeServices(
            preferences: nil,
            paths: paths,
            settingsStore: SettingsStore(
                storage: .file(paths.settingsFileURL),
                fileManager: FailingSettingsSaveFileManager()
            ),
            models: CandidateRuntimeModelResolver(models: [
                Self.runtimeModel(previous),
                Self.runtimeModel(candidate),
            ]),
            transcriber: transcriber
        )

        let result = await services.activateInstalledModel(candidate.id)

        XCTAssertEqual(result, .persistenceFailed)
        XCTAssertEqual(services.preferences.activeModelID, previous.id)
        XCTAssertEqual(
            SettingsStore(storage: .file(paths.settingsFileURL))
                .load().activeModelID,
            previous.id
        )
        let preparedModelIDs = await transcriber.preparedModelIDs()
        XCTAssertEqual(
            preparedModelIDs,
            [candidate.id, previous.id]
        )
    }

    @MainActor
    func testFailedUseKeepsPersistedIdentityAndRestoresPreviousRuntime() async throws {
        let paths = try Self.makeTemporaryPaths()
        let previous = try Self.catalogModel(id: ProductionModelPolicy.requiredModelID)
        let candidate = try Self.catalogModel(id: "whisper-large-v2-q5_0")
        try Self.writeInstalledStore(
            models: [previous, candidate],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = previous.id
        let resolver = CandidateRuntimeModelResolver(models: [
            Self.runtimeModel(previous),
            Self.runtimeModel(candidate),
        ])
        let transcriber = ActivationTranscriberSpy(failingModelIDs: [candidate.id])
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: resolver,
            transcriber: transcriber
        )

        let result = await services.activateInstalledModel(candidate.id)
        let preparedModelIDs = await transcriber.preparedModelIDs()

        XCTAssertEqual(result, .preparationFailed)
        XCTAssertEqual(services.preferences.activeModelID, previous.id)
        XCTAssertEqual(services.settingsStore.load().activeModelID, previous.id)
        XCTAssertEqual(preparedModelIDs, [candidate.id, previous.id])
    }

    @MainActor
    func testInactiveExactArtifactDeletionRemovesBytesBeforeReceipt() async throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let installedDirectory = try Self.writeInstalledArtifact(
            model,
            to: paths
        )
        let services = try Self.makeServices(
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(model)]
            )
        )

        try await services.removeInstalledModel(
            model.id,
            activeResolution: .requireInactive
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: installedDirectory.path)
        )
        XCTAssertFalse(services.isModelInstalled(model.id))
        let persisted = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(
                contentsOf: ModelStorageLayout(
                    rootDirectory: paths.modelsDirectory
                ).installedStoreURL
            )
        )
        XCTAssertNil(persisted.record(forModelID: model.id))
    }

    @MainActor
    func testActiveExactArtifactDeletionRequiresExplicitPurposeResolution() async throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let installedDirectory = try Self.writeInstalledArtifact(
            model,
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(model)]
            )
        )

        do {
            try await services.removeInstalledModel(
                model.id,
                activeResolution: .requireInactive
            )
            XCTFail("An active Exact Artifact needs an explicit user choice.")
        } catch {
            XCTAssertEqual(
                error as? AppModelRemovalError,
                .activePurposeResolutionRequired(.transcription)
            )
        }

        XCTAssertEqual(services.preferences.activeModelID, model.id)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: installedDirectory.path)
        )
        XCTAssertTrue(services.isModelInstalled(model.id))
    }

    @MainActor
    func testCancelledRemovalConfirmationMutatesNothing() async throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let installedDirectory = try Self.writeInstalledArtifact(
            model,
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id
        let transcriber = ActivationTranscriberSpy()
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(model)]
            ),
            transcriber: transcriber
        )
        let confirmation = try XCTUnwrap(
            services.modelCatalogExperience(
                for: .transcription,
                onDiskBytesByModelID: [model.id: 4_096]
            ).removalConfirmation(
                for: .exactArtifact(model.id)
            )
        )

        ModelsSettingsPane(
            destination: .transcription,
            featureModel: services.modelCatalogFeature(
                for: .transcription
            )
        )
            .resolveRemoval(confirmation, confirmed: false)

        XCTAssertEqual(services.preferences.activeModelID, model.id)
        XCTAssertEqual(
            services.settingsStore.load().activeModelID,
            model.id
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: installedDirectory.path)
        )
        XCTAssertTrue(services.isModelInstalled(model.id))
        let unloadCount = await transcriber.unloadCount()
        XCTAssertEqual(unloadCount, 0)
        XCTAssertNil(services.modelRemovalStatus)
    }

    @MainActor
    func testWarmModelPaneNavigationRetainsUsefulProjection() async throws {
        let services = try Self.makeServices()
        let model = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-27T00:00:00Z",
            models: [model]
        )
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest }
        )
        let feature = services.modelCatalogFeature(
            for: .transcription
        )
        await feature.waitUntilSettled()
        let initialSnapshot = try XCTUnwrap(feature.snapshot)
        let initialGeneration = feature.publishedGeneration
        XCTAssertFalse(initialSnapshot.experience.rows.isEmpty)
        let retainedRowID = ModelCatalogHierarchyRowID.exactArtifact(
            try XCTUnwrap(initialSnapshot.experience.rows.first?.id)
        )
        feature.discoveryQuery.searchText = "whisper"
        feature.hierarchyState.focus(retainedRowID)
        feature.hierarchyState.scroll(to: retainedRowID)
        feature.showsInspector = true
        let initialPresentation =
            ModelCatalogPaneLifecyclePresentation(
                featureModel: feature,
                coordinator: services.modelCatalogCoordinator
            )

        services.settingsRouter.selectedPane = .transcriptionModels
        services.settingsRouter.selectedPane = .general
        services.settingsRouter.selectedPane = .transcriptionModels
        let reenteredFeature = services.modelCatalogFeature(
            for: .transcription
        )
        let reenteredPresentation =
            ModelCatalogPaneLifecyclePresentation(
                featureModel: reenteredFeature,
                coordinator: services.modelCatalogCoordinator
            )

        XCTAssertTrue(feature === reenteredFeature)
        XCTAssertEqual(reenteredFeature.snapshot, initialSnapshot)
        XCTAssertEqual(reenteredFeature.publishedGeneration, initialGeneration)
        XCTAssertEqual(
            reenteredFeature.discoveryQuery.searchText,
            "whisper"
        )
        XCTAssertEqual(reenteredPresentation, initialPresentation)
        XCTAssertTrue(reenteredPresentation.hasUsefulProjection)
        XCTAssertFalse(
            reenteredPresentation.showsInitialLoadingPlaceholder
        )
        XCTAssertTrue(reenteredPresentation.showsInspector)
        XCTAssertEqual(
            reenteredPresentation.scrollAnchorID,
            retainedRowID
        )
    }

    @MainActor
    func testActiveDeletionStopsWhenPurposeDisableCannotPersist() async throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let installedDirectory = try Self.writeInstalledArtifact(
            model,
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id
        SettingsStore(storage: .file(paths.settingsFileURL))
            .save(preferences)
        let services = try Self.makeServices(
            preferences: nil,
            paths: paths,
            settingsStore: SettingsStore(
                storage: .file(paths.settingsFileURL),
                fileManager: FailingSettingsSaveFileManager()
            ),
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(model)]
            )
        )

        do {
            try await services.removeInstalledModel(
                model.id,
                activeResolution: .disablePurpose
            )
            XCTFail("Deletion must stop if purpose disablement is not durable.")
        } catch {
            XCTAssertEqual(
                error as? AppModelRemovalError,
                .purposeDisablePersistenceFailed(.transcription)
            )
        }

        XCTAssertEqual(services.preferences.activeModelID, model.id)
        XCTAssertEqual(
            SettingsStore(storage: .file(paths.settingsFileURL))
                .load().activeModelID,
            model.id
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: installedDirectory.path)
        )
        XCTAssertTrue(services.isModelInstalled(model.id))
    }

    @MainActor
    func testActiveDeletionWaitsForCurrentSegmentThenDisablesPurpose() async throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let installedDirectory = try Self.writeInstalledArtifact(
            model,
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id
        let transcriber = ActivationTranscriberSpy()
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(model)]
            ),
            transcriber: transcriber
        )

        await services.dictation.handleTriggerAction(.beginRecording)
        let removal = Task { @MainActor in
            try await services.removeInstalledModel(
                model.id,
                activeResolution: .disablePurpose
            )
        }
        for _ in 0..<100
        where services.modelRemovalStatus
            != AppModelRemovalStatus(
                artifactID: model.id,
                phase: .finishingCurrentDictation
            ) {
            await Task.yield()
        }

        XCTAssertEqual(
            services.modelRemovalStatus,
            AppModelRemovalStatus(
                artifactID: model.id,
                phase: .finishingCurrentDictation
            )
        )
        XCTAssertEqual(services.preferences.activeModelID, model.id)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: installedDirectory.path)
        )

        await services.dictation.handleTriggerAction(.finishRecording)
        try await removal.value

        XCTAssertNil(services.modelRemovalStatus)
        XCTAssertNil(services.preferences.activeModelID)
        XCTAssertNil(services.settingsStore.load().activeModelID)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: installedDirectory.path)
        )
        let unloadCount = await transcriber.unloadCount()
        XCTAssertEqual(unloadCount, 1)
    }

    @MainActor
    func testActiveCleanerDeletionDisablesOnlyVoiceCleaning() async throws {
        let paths = try Self.makeTemporaryPaths()
        let transcription = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let cleaner = try Self.catalogModel(id: "mossformer2-se-fp16")
        _ = try Self.writeInstalledArtifacts(
            [transcription, cleaner],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = transcription.id
        preferences.activeVoiceCleaningModelID = cleaner.id
        let voiceCleaner = ActivationVoiceCleanerSpy()
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(models: [
                Self.runtimeModel(transcription),
                Self.runtimeModel(cleaner),
            ]),
            voiceCleaner: voiceCleaner
        )

        try await services.removeInstalledModel(
            cleaner.id,
            activeResolution: .disablePurpose
        )

        XCTAssertEqual(services.preferences.activeModelID, transcription.id)
        XCTAssertNil(services.preferences.activeVoiceCleaningModelID)
        XCTAssertFalse(services.isModelInstalled(cleaner.id))
        let unloadCount = await voiceCleaner.unloadCount()
        XCTAssertEqual(unloadCount, 1)
    }

    @MainActor
    func testRevokedInstalledExactArtifactRemainsExplicitlyDeletable() async throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let installedDirectory = try Self.writeInstalledArtifact(
            model,
            to: paths
        )
        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-24T00:00:00Z",
            models: [model]
        )
        let services = try Self.makeServices(
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(model)]
            )
        )
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest },
            initialRevocationState: try ModelRevocationTestFixture.state(
                records: [
                    ModelRevocationRecord(
                        recordID: "delete-revoked-artifact",
                        exactArtifactID: model.id
                    ),
                ]
            )
        )

        try await services.removeInstalledModel(
            model.id,
            activeResolution: .requireInactive
        )

        XCTAssertFalse(services.isModelInstalled(model.id))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: installedDirectory.path)
        )
    }

    @MainActor
    func testFailedReplacementLeavesActiveArtifactProtectedFromDeletion() async throws {
        let paths = try Self.makeTemporaryPaths()
        let active = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let candidate = try Self.catalogModel(id: "whisper-large-v2-q5_0")
        let activeDirectory = try Self.writeInstalledArtifacts(
            [active, candidate],
            to: paths
        )[active.id]
        var preferences = AppPreferences.defaults
        preferences.activeModelID = active.id
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(models: [
                Self.runtimeModel(active),
                Self.runtimeModel(candidate),
            ]),
            transcriber: ActivationTranscriberSpy(
                failingModelIDs: [candidate.id]
            )
        )

        let activation = await services.activateInstalledModel(candidate.id)
        XCTAssertEqual(activation, .preparationFailed)
        do {
            try await services.removeInstalledModel(
                active.id,
                activeResolution: .requireInactive
            )
            XCTFail("A failed replacement must keep the active bytes protected.")
        } catch {
            XCTAssertEqual(
                error as? AppModelRemovalError,
                .activePurposeResolutionRequired(.transcription)
            )
        }

        XCTAssertEqual(services.preferences.activeModelID, active.id)
        XCTAssertTrue(
            activeDirectory.map {
                FileManager.default.fileExists(atPath: $0.path)
            } ?? false
        )
    }

    @MainActor
    func testUseRejectsInstalledArtifactWhenSignedCompatibilityIsNotCompatible() async throws {
        let paths = try Self.makeTemporaryPaths()
        let previous = try Self.catalogModel(id: ProductionModelPolicy.requiredModelID)
        let candidate = try Self.catalogModel(id: "parakeet-rnnt-1.1b")
        try Self.writeInstalledStore(
            models: [previous, candidate],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = previous.id
        let compatibilityResolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_589_934_592
            )
        )
        let transcriber = ActivationTranscriberSpy()
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            modelCatalogCompatibilityResolver: compatibilityResolver,
            models: CandidateRuntimeModelResolver(models: [
                Self.runtimeModel(previous),
                Self.runtimeModel(candidate),
            ]),
            transcriber: transcriber
        )
        let manifest = try ModelManifest.decode(
            Data(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("models/manifest.json")
            )
        )
        services.modelCatalogCoordinator = ModelCatalogCoordinator {
            manifest
        }
        await services.modelCatalogCoordinator.refresh()

        let result = await services.activateInstalledModel(candidate.id)
        let preparedModelIDs = await transcriber.preparedModelIDs()

        XCTAssertEqual(
            result,
            .incompatible(
                .incompatible(
                    .insufficientMemory(
                        requiredBytes: 17_179_869_184,
                        availableBytes: 8_589_934_592
                    )
                )
            )
        )
        XCTAssertEqual(services.preferences.activeModelID, previous.id)
        XCTAssertEqual(services.settingsStore.load().activeModelID, previous.id)
        XCTAssertTrue(preparedModelIDs.isEmpty)
    }

    @MainActor
    func testUseRejectsDigestRevokedInstalledArtifactBeforePreparation() async throws {
        let paths = try Self.makeTemporaryPaths()
        let previous = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let candidate = try Self.catalogModel(id: "whisper-large-v2-q5_0")
        try Self.writeInstalledStore(
            models: [previous, candidate],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = previous.id
        let transcriber = ActivationTranscriberSpy()
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(models: [
                Self.runtimeModel(previous),
                Self.runtimeModel(candidate),
            ]),
            transcriber: transcriber
        )
        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-24T00:00:00Z",
            models: [previous, candidate]
        )
        let digest = try XCTUnwrap(candidate.files.first?.sha256)
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest },
            initialRevocationState: try ModelRevocationTestFixture.state(
                records: [
                    ModelRevocationRecord(
                        recordID: "digest-revocation",
                        contentDigest: ModelRevocationDigestTarget(
                            algorithm: .sha256,
                            value: digest,
                            scope: .singleFilePayload
                        )
                    ),
                ]
            )
        )

        let result = await services.activateInstalledModel(candidate.id)
        let preparedModelIDs = await transcriber.preparedModelIDs()

        XCTAssertEqual(result, .revoked)
        XCTAssertEqual(services.preferences.activeModelID, previous.id)
        XCTAssertEqual(services.settingsStore.load().activeModelID, previous.id)
        XCTAssertTrue(preparedModelIDs.isEmpty)
    }

    @MainActor
    func testRevocationDisablesBothActivePurposesAndRequiresExplicitReplacement() async throws {
        let paths = try Self.makeTemporaryPaths()
        let transcription = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let fallback = try Self.catalogModel(id: "whisper-large-v2-q5_0")
        let cleaner = try Self.catalogModel(id: "mossformer2-se-fp16")
        try Self.writeInstalledStore(
            models: [transcription, fallback, cleaner],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = transcription.id
        preferences.activeVoiceCleaningModelID = cleaner.id
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            modelCatalogCompatibilityResolver:
                ModelCatalogCompatibilityResolver(
                    context: ModelCatalogCompatibilityContext(
                        appVersion: "1.1.0",
                        macOSVersion: "14.0.0",
                        architecture: .arm64,
                        physicalMemoryBytes: 17_179_869_184
                    )
                ),
            models: CandidateRuntimeModelResolver(models: [
                Self.runtimeModel(transcription),
                Self.runtimeModel(fallback),
                Self.runtimeModel(cleaner),
            ])
        )
        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-24T00:00:00Z",
            models: [transcription, fallback, cleaner]
        )
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest },
            initialRevocationState: try ModelRevocationTestFixture.state(
                records: [
                    ModelRevocationRecord(
                        recordID: "transcription-revocation",
                        exactArtifactID: transcription.id
                    ),
                    ModelRevocationRecord(
                        recordID: "cleaner-revocation",
                        exactArtifactID: cleaner.id
                    ),
                ]
            )
        )

        await services.enforceModelRevocations()

        XCTAssertNil(services.preferences.activeModelID)
        XCTAssertNil(services.preferences.activeVoiceCleaningModelID)
        XCTAssertNil(services.settingsStore.load().activeModelID)
        XCTAssertNil(
            services.settingsStore.load().activeVoiceCleaningModelID
        )
        XCTAssertEqual(
            services.revokedActiveTranscriptionModelID,
            transcription.id
        )
        XCTAssertEqual(
            services.revokedActiveVoiceCleaningModelID,
            cleaner.id
        )
        XCTAssertFalse(services.isModelActive(fallback.id))
        let revokedRow = try XCTUnwrap(
            services.modelCatalogExperience(
                for: .transcription
            ).rows.first { $0.id == transcription.id }
        )
        XCTAssertTrue(revokedRow.stateTokens.contains(.revoked))
        XCTAssertTrue(revokedRow.stateTokens.contains(.installed))
        XCTAssertFalse(
            revokedRow.stateTokens.contains(.needsRepair),
            "Revocation must not fabricate an independent integrity failure."
        )

        services.chooseReplacement(for: .transcription)

        XCTAssertEqual(
            services.settingsRouter.selectedPane,
            .transcriptionModels
        )
        XCTAssertEqual(
            services.settingsRouter.modelReplacementPurpose,
            .transcription
        )
        XCTAssertNil(services.settingsRouter.modelReveal)

        let failedReplacement = await services.activateInstalledModel(
            fallback.id
        )

        XCTAssertEqual(failedReplacement, .preparationFailed)
        XCTAssertNil(services.preferences.activeModelID)
        XCTAssertEqual(
            services.revokedActiveTranscriptionModelID,
            transcription.id
        )
        XCTAssertEqual(
            services.settingsRouter.modelReplacementPurpose,
            .transcription
        )
    }

    @MainActor
    func testMidSegmentRevocationFinishesCapturedIdentityThenDisablesDictation() async throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        try Self.writeInstalledStore(models: [model], to: paths)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(model)]
            ),
            transcriber: ActivationTranscriberSpy()
        )

        await services.dictation.handleTriggerAction(.beginRecording)
        XCTAssertEqual(
            services.dictation.currentSegment?
                .transcriptionArtifactID,
            model.id
        )

        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-24T00:00:00Z",
            models: [model]
        )
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest },
            initialRevocationState: try ModelRevocationTestFixture.state(
                records: [
                    ModelRevocationRecord(
                        recordID: "mid-segment-revocation",
                        exactArtifactID: model.id
                    ),
                ]
            )
        )
        await services.enforceModelRevocations()

        XCTAssertEqual(services.preferences.activeModelID, model.id)

        await services.dictation.handleTriggerAction(.finishRecording)
        for _ in 0..<20 where services.preferences.activeModelID != nil {
            await Task.yield()
        }

        XCTAssertEqual(
            services.dictation.status,
            .cancelled(.noSpeechDetected)
        )
        XCTAssertNil(services.dictation.currentSegment)
        XCTAssertNil(services.preferences.activeModelID)
        XCTAssertNil(services.settingsStore.load().activeModelID)
    }

    @MainActor
    func testRevocationEnforcementDrainsRequestAcceptedDuringFinalReadinessAwait() async throws {
        let paths = try Self.makeTemporaryPaths()
        let first = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let second = try Self.catalogModel(
            id: "whisper-large-v2-q5_0"
        )
        try Self.writeInstalledStore(models: [first, second], to: paths)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = second.id
        let resolver = CandidateRuntimeModelResolver(
            models: [
                Self.runtimeModel(first),
                Self.runtimeModel(second),
            ]
        )
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: resolver,
            transcriber: ActivationTranscriberSpy()
        )
        await services.refreshManagedModelReadiness()
        await resolver.suspendReadiness(for: second.id)
        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-24T00:00:00Z",
            models: [first, second]
        )
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest },
            initialRevocationState: try ModelRevocationTestFixture.state(
                records: [
                    ModelRevocationRecord(
                        recordID: "first-revocation",
                        exactArtifactID: first.id
                    ),
                ]
            )
        )
        for _ in 0..<2_000 {
            if await resolver.isReadinessSuspended() {
                break
            }
            await Task.yield()
        }
        let readinessIsSuspended =
            await resolver.isReadinessSuspended()
        XCTAssertTrue(readinessIsSuspended)

        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest },
            initialRevocationState: try ModelRevocationTestFixture.state(
                records: [
                    ModelRevocationRecord(
                        recordID: "first-revocation",
                        exactArtifactID: first.id
                    ),
                    ModelRevocationRecord(
                        recordID: "second-revocation",
                        exactArtifactID: second.id
                    ),
                ]
            )
        )
        await resolver.releaseReadiness()
        await services.enforceModelRevocations()

        XCTAssertNil(services.preferences.activeModelID)
        XCTAssertNil(services.settingsStore.load().activeModelID)
        XCTAssertEqual(
            services.revokedActiveTranscriptionModelID,
            second.id
        )
    }

    @MainActor
    func testRestoredSelectedArtifactIsDisabledUntilPersistedIntegrityVerification() async throws {
        let paths = try Self.makeTemporaryPaths()
        let model = try Self.catalogModel(id: "whisper-large-v2-q5_0")
        try Self.writeInstalledStore(models: [model], to: paths)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = model.id
        let transcriber = ActivationTranscriberSpy()
        let durabilityRecorder = AppWorkflowBoundaryRecorder()
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            modelCatalogCompatibilityResolver:
                ModelCatalogCompatibilityResolver(
                    context: ModelCatalogCompatibilityContext(
                        appVersion: "1.1.0",
                        macOSVersion: "14.0.0",
                        architecture: .arm64,
                        physicalMemoryBytes: 17_179_869_184
                    )
                ),
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(model)]
            ),
            transcriber: transcriber,
            modelWorkflowDurabilityObserver: durabilityRecorder.observer
        )
        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-24T00:00:00Z",
            models: [model]
        )
        let restorationID = "restore-\(model.id)"
        let restorationState =
            try ModelRevocationTestFixture.restoredState(
                record: ModelRevocationRecord(
                    recordID: "revoked-\(model.id)",
                    exactArtifactID: model.id
                ),
                restoration: ModelRestorationRecord(
                    restorationID: restorationID,
                    revocationRecordID: "revoked-\(model.id)",
                    exactArtifactID: model.id
                )
            )
        services.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest },
            initialRevocationState: restorationState
        )
        await services.enforceModelRevocations()

        let preparedModelIDs = await transcriber.preparedModelIDs()
        XCTAssertNil(services.preferences.activeModelID)
        XCTAssertNil(services.settingsStore.load().activeModelID)
        XCTAssertEqual(preparedModelIDs, [])

        let blocked = await services.activateInstalledModel(model.id)
        let blockedRow = try XCTUnwrap(
            services.modelCatalogExperience(
                for: .transcription
            ).rows.first { $0.id == model.id }
        )

        XCTAssertEqual(blocked, .integrityVerificationRequired)
        XCTAssertNil(services.preferences.activeModelID)
        XCTAssertTrue(
            blockedRow.stateTokens.contains(.verificationRequired)
        )
        XCTAssertFalse(blockedRow.actions.contains(.use))

        await services.acknowledgeRestoredModelIntegrity(
            model.id,
            expectedRestorationIDs: ["superseded-restoration"]
        )
        XCTAssertEqual(
            services.pendingRestorationVerificationIDs(
                for: try XCTUnwrap(
                    services.installedModelRecords.first {
                        $0.model.id == model.id
                    }
                )
            ),
            [restorationID]
        )
        await services.acknowledgeRestoredModelIntegrity(model.id)
        XCTAssertTrue(
            durabilityRecorder.events.contains(
                AppWorkflowBoundaryEvent(
                    boundary: .restorationIntegrityAcknowledged,
                    artifactID: model.id
                )
            )
        )
        XCTAssertNil(
            services.preferences.activeModelID,
            "Verification must not activate restored content."
        )
        let sameSessionActivation =
            await services.activateInstalledModel(model.id)
        XCTAssertEqual(sameSessionActivation, .activated)
        services.preferences.activeModelID = nil
        services.savePreferences()
        let storedRecord = try XCTUnwrap(
            JSONDecoder().decode(
                InstalledModelsStore.self,
                from: Data(
                    contentsOf: ModelStorageLayout(
                        rootDirectory: paths.modelsDirectory
                    ).installedStoreURL
                )
            ).record(forModelID: model.id)
        )
        let relaunched = try Self.makeServices(
            preferences: nil,
            paths: paths,
            modelCatalogCompatibilityResolver:
                ModelCatalogCompatibilityResolver(
                    context: ModelCatalogCompatibilityContext(
                        appVersion: "1.1.0",
                        macOSVersion: "14.0.0",
                        architecture: .arm64,
                        physicalMemoryBytes: 17_179_869_184
                    )
                ),
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(model)]
            ),
            transcriber: ActivationTranscriberSpy()
        )
        relaunched.modelCatalogCoordinator = ModelCatalogCoordinator(
            initialManifest: manifest,
            loadOperation: { manifest },
            initialRevocationState: restorationState
        )
        await relaunched.enforceModelRevocations()
        let activated = await relaunched.activateInstalledModel(model.id)

        XCTAssertEqual(
            storedRecord.verifiedRestorationIDs,
            [restorationID]
        )
        XCTAssertEqual(activated, .activated)
        XCTAssertEqual(relaunched.preferences.activeModelID, model.id)
    }

    @MainActor
    func testFailedEnableKeepsPreviousCleanerAndRestoresItsRuntime() async throws {
        let paths = try Self.makeTemporaryPaths()
        let previous = try Self.catalogModel(id: "mossformer2-se-fp16")
        let candidate = try Self.catalogModel(id: "mossformer2-se-int8")
        try Self.writeInstalledStore(
            models: [previous, candidate],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeVoiceCleaningModelID = previous.id
        let resolver = CandidateRuntimeModelResolver(models: [
            Self.runtimeModel(previous),
            Self.runtimeModel(candidate),
        ])
        let voiceCleaner = ActivationVoiceCleanerSpy(
            failingModelIDs: [candidate.id]
        )
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: resolver,
            voiceCleaner: voiceCleaner
        )

        let result = await services.activateInstalledModel(candidate.id)
        let preparedModelIDs = await voiceCleaner.preparedModelIDs()

        XCTAssertEqual(result, .preparationFailed)
        XCTAssertEqual(
            services.preferences.activeVoiceCleaningModelID,
            previous.id
        )
        XCTAssertEqual(
            services.settingsStore.load().activeVoiceCleaningModelID,
            previous.id
        )
        XCTAssertEqual(preparedModelIDs, [candidate.id, previous.id])
    }

    @MainActor
    func testDisableVoiceCleaningPersistsWithoutDeletingInstalledBytes() async throws {
        let paths = try Self.makeTemporaryPaths()
        let cleaner = try Self.catalogModel(id: "mossformer2-se-fp16")
        try Self.writeInstalledStore(models: [cleaner], to: paths)
        var preferences = AppPreferences.defaults
        preferences.activeVoiceCleaningModelID = cleaner.id
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(
                models: [Self.runtimeModel(cleaner)]
            )
        )

        await services.disableVoiceCleaning()

        XCTAssertNil(services.preferences.activeVoiceCleaningModelID)
        XCTAssertNil(services.settingsStore.load().activeVoiceCleaningModelID)
        XCTAssertTrue(services.isModelInstalled(cleaner.id))
        XCTAssertNotNil(
            InstalledModelsStore(
                records: services.installedModelRecords
            ).record(forModelID: cleaner.id)
        )
    }

    @MainActor
    func testDisableVoiceCleaningWaitsForTheCurrentSegmentBoundary() async throws {
        let paths = try Self.makeTemporaryPaths()
        let transcription = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let cleaner = try Self.catalogModel(id: "mossformer2-se-fp16")
        try Self.writeInstalledStore(
            models: [transcription, cleaner],
            to: paths
        )
        var preferences = AppPreferences.defaults
        preferences.activeModelID = transcription.id
        preferences.activeVoiceCleaningModelID = cleaner.id
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(models: [
                Self.runtimeModel(transcription),
                Self.runtimeModel(cleaner),
            ]),
            voiceCleaner: ActivationVoiceCleanerSpy()
        )

        await services.dictation.handleTriggerAction(.beginRecording)
        let disablement = Task { @MainActor in
            await services.disableVoiceCleaning()
        }
        for _ in 0..<100
        where services.dictation.allowsModelTransactions {
            await Task.yield()
        }

        XCTAssertFalse(services.dictation.allowsModelTransactions)
        XCTAssertEqual(
            services.preferences.activeVoiceCleaningModelID,
            cleaner.id
        )

        await services.dictation.handleTriggerAction(.finishRecording)
        let disabled = await disablement.value

        XCTAssertTrue(disabled)
        XCTAssertNil(services.preferences.activeVoiceCleaningModelID)
    }

    @MainActor
    func testSuccessfulAndFailedInstallTransactionsNeverChangeCommittedActiveIdentity() async throws {
        let paths = try Self.makeTemporaryPaths()
        let active = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let secondVariant = try Self.catalogModel(
            id: "whisper-large-v2-q5_0"
        )
        try Self.writeInstalledStore(models: [active], to: paths)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = active.id
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths
        )
        services.modelInstallCoordinator = ModelInstallCoordinator {
            [weak services] _, onStateChange in
            try Self.writeInstalledStore(
                models: [active, secondVariant],
                to: paths
            )
            guard let services else {
                throw ModelInstallCoordinatorError.modelPreparationFailed
            }
            try await services.completeModelInstall(
                secondVariant,
                onStateChange: onStateChange
            )
        }

        guard let successfulAttemptID = services.modelInstallCoordinator.start(
            modelID: secondVariant.id
        ) else {
            return XCTFail("Expected the successful install to be authorized.")
        }
        for _ in 0..<1_000 {
            if services.modelInstallCoordinator
                .attempt(id: successfulAttemptID)?
                .state.phase == .installed
            {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(
            services.modelInstallCoordinator
                .attempt(id: successfulAttemptID)?
                .state.phase,
            .installed
        )
        XCTAssertTrue(services.isModelInstalled(secondVariant.id))
        XCTAssertEqual(services.preferences.activeModelID, active.id)
        XCTAssertEqual(services.settingsStore.load().activeModelID, active.id)

        services.modelInstallCoordinator = ModelInstallCoordinator { _, _ in
            throw ModelInstallCoordinatorError.modelPreparationFailed
        }
        guard let failedAttemptID = services.modelInstallCoordinator.start(
            modelID: "failed-variant"
        ) else {
            return XCTFail("Expected the failed install to be authorized.")
        }
        for _ in 0..<1_000 {
            if services.modelInstallCoordinator
                .attempt(id: failedAttemptID)?
                .state.phase == .failed
            {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(
            services.modelInstallCoordinator
                .attempt(id: failedAttemptID)?
                .state.phase,
            .failed
        )
        XCTAssertEqual(services.preferences.activeModelID, active.id)
        XCTAssertEqual(services.settingsStore.load().activeModelID, active.id)
    }

    @MainActor
    func testExplicitUseInstallsVerifiesThenActivatesTheChosenArtifact() async throws {
        let paths = try Self.makeTemporaryPaths()
        let active = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        let candidate = try Self.catalogModel(
            id: "whisper-large-v2-q5_0"
        )
        try Self.writeInstalledStore(models: [active], to: paths)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = active.id
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths,
            models: CandidateRuntimeModelResolver(models: [
                Self.runtimeModel(active),
                Self.runtimeModel(candidate),
            ]),
            transcriber: ActivationTranscriberSpy()
        )
        services.modelInstallCoordinator = ModelInstallCoordinator(
            installOperation: { [weak services] _, onStateChange in
                try Self.writeInstalledStore(
                    models: [active, candidate],
                    to: paths
                )
                guard let services else {
                    throw ModelInstallCoordinatorError
                        .modelPreparationFailed
                }
                try await services.completeModelInstall(
                    candidate,
                    onStateChange: onStateChange
                )
            },
            lifecycleDidChange: { [weak services] in
                services?.refreshModelStorageInventory()
                services?.reconcilePendingModelUseIntents()
            }
        )

        let request = await services.useModel(
            candidate.id,
            purpose: .transcription
        )
        for _ in 0..<10_000
        where services.preferences.activeModelID != candidate.id {
            await Task.yield()
        }

        XCTAssertEqual(request, .installQueued)
        XCTAssertEqual(services.preferences.activeModelID, candidate.id)
        XCTAssertEqual(
            services.settingsStore.load().activeModelID,
            candidate.id
        )
        XCTAssertTrue(services.isModelInstalled(candidate.id))
    }

    @MainActor
    func testChoosingSignedRecommendedVersionClearsManualOverride()
        async throws
    {
        let services = try Self.makeServices()
        await services.modelCatalogCoordinator.refresh()
        let checkpointID =
            "checkpoint.openai.whisper-large-v3-turbo"
        let key = "transcription|\(checkpointID)"

        services.setModelArtifactOverride(
            checkpointID: checkpointID,
            artifactID: "whisper-large-v3-turbo-mlx",
            purpose: .transcription
        )
        XCTAssertEqual(
            services.preferences
                .modelArtifactOverridesByPurposeCheckpoint[key],
            "whisper-large-v3-turbo-mlx"
        )

        services.setModelArtifactOverride(
            checkpointID: checkpointID,
            artifactID: "whisper-large-v3-turbo-q5_0",
            purpose: .transcription,
            followsSignedRecommendation: true
        )
        XCTAssertNil(
            services.preferences
                .modelArtifactOverridesByPurposeCheckpoint[key]
        )
    }

    @MainActor
    func testArtifactOverrideReadIsPureAndInvalidCleanupIsExplicit()
        throws
    {
        let checkpointID = "missing-checkpoint"
        let artifactID = "missing-artifact"
        let key = "transcription|\(checkpointID)"
        var preferences = AppPreferences.defaults
        preferences.modelArtifactOverridesByPurposeCheckpoint[key] =
            artifactID
        let services = try Self.makeServices(preferences: preferences)

        XCTAssertEqual(
            services.modelArtifactOverrides(for: .transcription),
            [checkpointID: artifactID]
        )
        XCTAssertEqual(
            services.preferences
                .modelArtifactOverridesByPurposeCheckpoint[key],
            artifactID,
            "Reading render input must not schedule preference mutations."
        )

        services.removeInvalidModelArtifactOverrides(
            [checkpointID: artifactID],
            for: .transcription
        )

        XCTAssertNil(
            services.preferences
                .modelArtifactOverridesByPurposeCheckpoint[key]
        )
        XCTAssertNil(
            services.settingsStore.load()
                .modelArtifactOverridesByPurposeCheckpoint[key]
        )
    }

    @MainActor
    func testExplicitUseFailurePreservesThePreviousActiveModel() async throws {
        let paths = try Self.makeTemporaryPaths()
        let active = try Self.catalogModel(
            id: ProductionModelPolicy.requiredModelID
        )
        try Self.writeInstalledStore(models: [active], to: paths)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = active.id
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths
        )
        services.modelInstallCoordinator = ModelInstallCoordinator(
            installOperation: { _, _ in
                throw ModelInstallCoordinatorError.modelPreparationFailed
            },
            lifecycleDidChange: { [weak services] in
                services?.refreshModelStorageInventory()
                services?.reconcilePendingModelUseIntents()
            }
        )

        let request = await services.useModel(
            "whisper-large-v2-q5_0",
            purpose: .transcription
        )
        for _ in 0..<10_000
        where services.modelInstallCoordinator.hasNonterminalAttempts {
            await Task.yield()
        }

        XCTAssertEqual(request, .installQueued)
        XCTAssertEqual(services.preferences.activeModelID, active.id)
        XCTAssertEqual(
            services.settingsStore.load().activeModelID,
            active.id
        )
    }

    func testAppPathsFactoryUsesTextifySupportLocationsWithoutUserLibrarySideEffects() throws {
        let root = Self.temporaryDirectory()
        let paths = try AppPaths.make(
            applicationSupportBase: root.appendingPathComponent("Application Support", isDirectory: true),
            libraryDirectory: root.appendingPathComponent("Library", isDirectory: true)
        )

        XCTAssertEqual(paths.applicationSupportDirectory.lastPathComponent, "Textify")
        XCTAssertTrue(paths.applicationSupportDirectory.path.hasPrefix(root.path))
        XCTAssertEqual(paths.settingsFileURL.lastPathComponent, "settings.json")
        XCTAssertEqual(paths.modelsDirectory.lastPathComponent, "Models")
        XCTAssertEqual(
            paths.manifestCacheDirectory.lastPathComponent,
            "ManifestCache"
        )
        XCTAssertEqual(paths.logsDirectory.lastPathComponent, "Textify")
    }

    func testAppPathsFactoryThrowsWhenTextifySupportPathIsAFile() throws {
        let root = Self.temporaryDirectory()
        let supportBase = root.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: supportBase, withIntermediateDirectories: true)
        let collision = supportBase.appendingPathComponent("Textify", isDirectory: true)
        try Data("not a directory".utf8).write(to: collision)

        XCTAssertThrowsError(
            try AppPaths.make(
                applicationSupportBase: supportBase,
                libraryDirectory: root.appendingPathComponent("Library", isDirectory: true)
            )
        )
    }

    func testLaunchAtLoginStatusIsEquatable() {
        XCTAssertEqual(LaunchAtLoginStatus.enabled, .enabled)
        XCTAssertEqual(LaunchAtLoginStatus.unsupportedLocation, .unsupportedLocation)
        XCTAssertNotEqual(LaunchAtLoginStatus.failed("first"), .failed("second"))
    }

    func testLoginItemsSettingsURLUsesSystemSettingsLoginItemsPane() {
        XCTAssertEqual(
            LoginItemsSettingsOpener.loginItemsSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        )
    }

    func testLaunchAtLoginLocationCheckerAllowsOnlyApplicationsFolders() {
        let homeDirectory = URL(fileURLWithPath: "/Users/textify", isDirectory: true)

        XCTAssertTrue(LaunchAtLoginLocationChecker(
            bundleURL: URL(fileURLWithPath: "/Applications/Textify.app", isDirectory: true),
            homeDirectory: homeDirectory
        ).isSupported)
        XCTAssertTrue(LaunchAtLoginLocationChecker(
            bundleURL: URL(fileURLWithPath: "/Users/textify/Applications/Textify.app", isDirectory: true),
            homeDirectory: homeDirectory
        ).isSupported)
        XCTAssertFalse(LaunchAtLoginLocationChecker(
            bundleURL: URL(fileURLWithPath: "/Users/textify/Downloads/Textify.app", isDirectory: true),
            homeDirectory: homeDirectory
        ).isSupported)
        XCTAssertFalse(LaunchAtLoginLocationChecker(
            bundleURL: URL(fileURLWithPath: "/Volumes/Textify/Textify.app", isDirectory: true),
            homeDirectory: homeDirectory
        ).isSupported)
    }

    @MainActor
    func testLaunchAtLoginBridgeRefreshesStatusAndPersistsSuccessfulChanges() async throws {
        let launchAtLogin = FakeLaunchAtLoginManager(status: .disabled)
        let services = try Self.makeServices(launchAtLogin: launchAtLogin)

        XCTAssertEqual(services.launchAtLoginStatus, LaunchAtLoginStatus.disabled)

        launchAtLogin.currentStatus = .enabled
        XCTAssertEqual(services.refreshLaunchAtLoginStatus(), LaunchAtLoginStatus.enabled)

        launchAtLogin.setResult = .enabled
        let enabledStatus = await services.setLaunchAtLoginEnabled(true)
        XCTAssertEqual(enabledStatus, LaunchAtLoginStatus.enabled)
        XCTAssertTrue(services.preferences.launchAtLoginEnabled)
        XCTAssertTrue(services.settingsStore.load().launchAtLoginEnabled)

        launchAtLogin.setResult = .requiresApproval
        let approvalStatus = await services.setLaunchAtLoginEnabled(true)
        XCTAssertEqual(approvalStatus, LaunchAtLoginStatus.requiresApproval)
        XCTAssertFalse(services.preferences.launchAtLoginEnabled)
        XCTAssertFalse(services.settingsStore.load().launchAtLoginEnabled)
    }

    @MainActor
    func testLaunchAtLoginBridgeDoesNotPersistFailedChanges() async throws {
        let launchAtLogin = FakeLaunchAtLoginManager(status: .enabled)
        let services = try Self.makeServices(launchAtLogin: launchAtLogin)
        services.preferences.launchAtLoginEnabled = true
        services.savePreferences()

        launchAtLogin.setResult = .failed("fixture")
        launchAtLogin.liveStatusAfterSetFailure = .enabled
        let status = await services.setLaunchAtLoginEnabled(false)

        XCTAssertEqual(status, LaunchAtLoginStatus.failed("fixture"))
        XCTAssertEqual(services.launchAtLoginStatus, LaunchAtLoginStatus.enabled)
        XCTAssertEqual(services.launchAtLoginOperationError, "fixture")
        XCTAssertEqual(services.launchAtLoginFailedRequestedEnabled, false)
        XCTAssertTrue(services.preferences.launchAtLoginEnabled)
        XCTAssertTrue(services.settingsStore.load().launchAtLoginEnabled)
    }

    @MainActor
    func testLaunchAtLoginUnsupportedLocationOverridesLiveStatusAndPersistsOff() async throws {
        let launchAtLogin = FakeLaunchAtLoginManager(status: .enabled)
        let services = try Self.makeServices(
            launchAtLogin: launchAtLogin,
            launchAtLoginLocation: FixedLaunchAtLoginLocation(isSupported: false)
        )
        services.preferences.launchAtLoginEnabled = true
        services.savePreferences()

        XCTAssertEqual(services.refreshLaunchAtLoginStatus(), LaunchAtLoginStatus.unsupportedLocation)
        XCTAssertFalse(services.canChangeLaunchAtLogin)

        let status = await services.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(status, LaunchAtLoginStatus.unsupportedLocation)
        XCTAssertEqual(services.launchAtLoginStatus, LaunchAtLoginStatus.unsupportedLocation)
        XCTAssertEqual(launchAtLogin.requestedEnabledValues, [])
        XCTAssertFalse(services.preferences.launchAtLoginEnabled)
        XCTAssertFalse(services.settingsStore.load().launchAtLoginEnabled)
    }

    @MainActor
    func testStartRuntimeCanRetryAfterSynchronousHotkeyStartFailure() async throws {
        let tap = FakeCGEventTapClient()
        tap.startError = HotkeyMonitorError.eventTapCreationFailed
        let services = try Self.makeServices(
            hotkeyMonitor: GlobalHotkeyMonitor(
                eventTapClient: tap
            )
        )

        services.startRuntime()
        XCTAssertEqual(tap.startCount, 1)
        XCTAssertEqual(services.runtimeIssue, .hotkeyMonitorUnavailable)

        tap.startError = nil
        services.startRuntime()

        XCTAssertEqual(tap.startCount, 2)
        XCTAssertNil(services.runtimeIssue)
    }

    @MainActor
    func testStartRuntimeCanRetryAfterUserInputDisablesStartedMonitor() async throws {
        let tap = FakeCGEventTapClient()
        let services = try Self.makeServices(
            hotkeyMonitor: GlobalHotkeyMonitor(
                permissionClient: InputMonitoringPermissionClient(
                    status: { .granted },
                    requestAccess: { .granted }
                ),
                eventTapClient: tap
            )
        )

        services.startRuntime()
        XCTAssertEqual(tap.startCount, 1)

        tap.send(.tapDisabledByUserInput)

        for _ in 0..<10 where tap.startCount == 1 {
            await Task.yield()
            services.startRuntime()
        }

        XCTAssertEqual(tap.startCount, 2)
    }

    @MainActor
    func testAppLaunchCoordinatorShowsOnboardingFromLaunchLifecycle() async throws {
        var preferences = AppPreferences.defaults
        preferences.onboardingCompleted = false
        let runtimeTap = FakeCGEventTapClient()
        let services = try Self.makeServices(
            preferences: preferences,
            hotkeyMonitor: GlobalHotkeyMonitor(
                permissionClient: InputMonitoringPermissionClient(
                    status: { .granted },
                    requestAccess: { .granted }
                ),
                eventTapClient: runtimeTap
            )
        )
        var didShowOnboarding = false
        var didShowMainWindow = false
        let coordinator = AppLaunchCoordinator(
            services: services,
            showOnboarding: { didShowOnboarding = true },
            showMainWindow: { didShowMainWindow = true }
        )

        await coordinator.run()

        XCTAssertTrue(didShowOnboarding)
        XCTAssertFalse(didShowMainWindow)
        XCTAssertEqual(runtimeTap.startCount, 0)
        XCTAssertFalse(services.dictation.readiness.canDictate)
    }

    @MainActor
    func testAppLaunchCoordinatorRestoresQueueBeforeShowingFirstWindow() async throws {
        let paths = try Self.makeTemporaryPaths()
        let temporaryRoot = paths.applicationSupportDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let store = ModelInstallQueueStore(
            fileURL: ModelStorageLayout(
                rootDirectory: paths.modelsDirectory
            ).installQueueURL
        )
        var queue = ModelInstallQueue()
        _ = try queue.authorize(
            artifactID: "missing-artifact",
            purpose: .transcription,
            action: .install,
            attemptID: "persisted-attempt",
            createdAt: "2026-07-24T10:00:00Z"
        )
        try queue.transition(
            attemptID: "persisted-attempt",
            to: DownloadState(
                modelID: "missing-artifact",
                phase: .checkingSpace
            )
        )
        try queue.transition(
            attemptID: "persisted-attempt",
            to: DownloadState(
                modelID: "missing-artifact",
                phase: .downloading
            )
        )
        try store.save(queue)

        var preferences = AppPreferences.defaults
        preferences.onboardingCompleted = false
        let services = try Self.makeServices(
            preferences: preferences,
            paths: paths
        )
        var phaseWhenFirstWindowOpened: DownloadPhase?
        let coordinator = AppLaunchCoordinator(
            services: services,
            showOnboarding: {
                phaseWhenFirstWindowOpened = try? store.load()
                    .attempt(id: "persisted-attempt")?
                    .state
                    .phase
            },
            showMainWindow: {}
        )

        await coordinator.run()

        XCTAssertEqual(phaseWhenFirstWindowOpened, .queued)
        services.modelInstallCoordinator.cancel(
            attemptID: "persisted-attempt"
        )
        for _ in 0..<2_000 where services.modelInstallCoordinator.isActive {
            await Task.yield()
        }
        XCTAssertFalse(services.modelInstallCoordinator.isActive)
    }

    @MainActor
    func testAppLaunchCoordinatorStartsRuntimeFromLaunchLifecycle() async throws {
        var preferences = AppPreferences.defaults
        preferences.onboardingCompleted = true
        let runtimeTap = FakeCGEventTapClient()
        let services = try Self.makeServices(
            preferences: preferences,
            hotkeyMonitor: GlobalHotkeyMonitor(
                permissionClient: InputMonitoringPermissionClient(
                    status: { .granted },
                    requestAccess: { .granted }
                ),
                eventTapClient: runtimeTap
            )
        )
        var didShowOnboarding = false
        var mainWindowOpenCount = 0
        let coordinator = AppLaunchCoordinator(
            services: services,
            showOnboarding: { didShowOnboarding = true },
            showMainWindow: { mainWindowOpenCount += 1 }
        )

        await coordinator.run()
        await coordinator.run()

        XCTAssertFalse(didShowOnboarding)
        XCTAssertEqual(runtimeTap.startCount, 1)
        XCTAssertEqual(mainWindowOpenCount, 1)
    }

    @MainActor
    func testStopRuntimeSuspendsHotkeyMonitorAndAllowsRestart() async throws {
        let tap = FakeCGEventTapClient()
        let services = try Self.makeServices(
            hotkeyMonitor: GlobalHotkeyMonitor(
                permissionClient: InputMonitoringPermissionClient(
                    status: { .granted },
                    requestAccess: { .granted }
                ),
                eventTapClient: tap
            )
        )

        services.startRuntime()
        XCTAssertEqual(tap.startCount, 1)
        XCTAssertEqual(tap.stopCount, 0)

        services.stopRuntime()
        XCTAssertEqual(tap.stopCount, 1)

        services.startRuntime()
        XCTAssertEqual(tap.startCount, 2)
    }

    @MainActor
    func testRecordingStatusPresentsAndThenHidesOverlay() async throws {
        let overlay = OverlayPresenterSpy()
        let services = try Self.makeServices(
            models: ReadyRuntimeModelResolver(),
            overlayPresenter: overlay
        )

        await services.dictation.handleTriggerAction(.beginRecording)
        for _ in 0..<5 {
            await Task.yield()
        }

        XCTAssertEqual(services.overlayState, .recording(elapsedSeconds: 0))
        XCTAssertEqual(overlay.states.last, .recording(elapsedSeconds: 0))

        await services.dictation.cancelActiveSession(reason: .escapeKey)
        for _ in 0..<5 {
            await Task.yield()
        }

        XCTAssertEqual(services.overlayState, .hidden)
        XCTAssertEqual(overlay.states.last, .hidden)
    }

    @MainActor
    func testRecordingOverlayPreferencesPersistAndReachPresenter() throws {
        let overlay = OverlayPresenterSpy()
        let services = try Self.makeServices(overlayPresenter: overlay)
        let preferences = RecordingOverlayPreferences(
            xOffset: 120,
            yOffset: 180,
            scale: 1.25
        )

        services.setRecordingOverlayPreferences(preferences)
        services.updateOverlay(for: .recording(speechDetected: false))

        XCTAssertEqual(services.preferences.recordingOverlay, preferences)
        XCTAssertEqual(
            services.settingsStore.load().recordingOverlay,
            preferences
        )
        XCTAssertEqual(overlay.preferences.last, preferences)
    }

    @MainActor
    func testProcessingIndicatorAppearsOnlyAfterDelayAndHidesWhenProcessingEnds() async throws {
        let overlay = OverlayPresenterSpy()
        let delay = OverlayDelayGate()
        let services = try Self.makeServices(
            overlayPresenter: overlay,
            waitBeforeProcessingIndicator: { await delay.wait() }
        )

        services.updateOverlay(for: .processing)
        XCTAssertEqual(services.overlayState, .hidden)
        XCTAssertEqual(overlay.states.last, .hidden)

        for _ in 0..<20 where !(await delay.isWaiting()) {
            await Task.yield()
        }
        await delay.release()
        for _ in 0..<20 where services.overlayState != .processing {
            await Task.yield()
        }

        XCTAssertEqual(services.overlayState, .processing)
        services.updateOverlay(for: .idle)
        XCTAssertEqual(services.overlayState, .hidden)
        XCTAssertEqual(overlay.states.last, .hidden)
    }

    @MainActor
    func testLeavingProcessingBeforeDelayPreventsLateIndicator() async throws {
        let overlay = OverlayPresenterSpy()
        let delay = OverlayDelayGate()
        let services = try Self.makeServices(
            overlayPresenter: overlay,
            waitBeforeProcessingIndicator: { await delay.wait() }
        )

        services.updateOverlay(for: .processing)
        services.updateOverlay(for: .cancelled(.escapeKey))
        await delay.release()
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(services.overlayState, .hidden)
        XCTAssertFalse(overlay.states.contains(.processing))
    }

    @MainActor
    func testExcludedAppStatusShowsDisabledOverlayMessage() throws {
        let overlay = OverlayPresenterSpy()
        let services = try Self.makeServices(overlayPresenter: overlay)

        services.updateOverlay(for: .blocked(.excludedApp))

        XCTAssertEqual(
            overlay.states.last,
            .blocked("Textify disabled for this app.")
        )
    }

    @MainActor
    func testTriggerTestControllerSuspendsAndResumesProductionRuntimeWhenOnboarded() throws {
        let runtimeTap = FakeCGEventTapClient()
        var preferences = AppPreferences.defaults
        preferences.onboardingCompleted = true
        let services = try Self.makeServices(
            preferences: preferences,
            hotkeyMonitor: GlobalHotkeyMonitor(
                permissionClient: InputMonitoringPermissionClient(
                    status: { .granted },
                    requestAccess: { .granted }
                ),
                eventTapClient: runtimeTap
            )
        )
        let triggerTestTap = FakeCGEventTapClient()
        let controller = OnboardingTriggerTestController(
            makeMonitor: { _ in
                GlobalHotkeyMonitor(
                    permissionClient: InputMonitoringPermissionClient(
                        status: { .granted },
                        requestAccess: { .granted }
                    ),
                    eventTapClient: triggerTestTap,
                    trigger: .rightCommand
                )
            }
        )

        services.startRuntime()
        XCTAssertEqual(runtimeTap.startCount, 1)

        controller.start(suspending: services)

        XCTAssertEqual(runtimeTap.stopCount, 1)
        XCTAssertEqual(triggerTestTap.startCount, 1)

        controller.stop()

        XCTAssertEqual(triggerTestTap.stopCount, 1)
        XCTAssertEqual(runtimeTap.startCount, 2)
    }

    @MainActor
    func testTriggerTestControllerPassesAfterRecognizedHoldAndRelease() async throws {
        let runtimeTap = FakeCGEventTapClient()
        let services = try Self.makeServices(
            hotkeyMonitor: GlobalHotkeyMonitor(
                permissionClient: InputMonitoringPermissionClient(
                    status: { .granted },
                    requestAccess: { .granted }
                ),
                eventTapClient: runtimeTap
            )
        )
        let triggerTestTap = FakeCGEventTapClient()
        let controller = OnboardingTriggerTestController(
            activationDelayMilliseconds: 250,
            sleepMilliseconds: { _ in },
            makeMonitor: { _ in
                GlobalHotkeyMonitor(
                    permissionClient: InputMonitoringPermissionClient(
                        status: { .granted },
                        requestAccess: { .granted }
                    ),
                    eventTapClient: triggerTestTap,
                    trigger: .rightCommand
                )
            }
        )

        controller.start(suspending: services)
        triggerTestTap.send(.keyboardEvent(KeyboardEventSnapshot(
            type: .flagsChanged,
            keyCode: TriggerKeyMatcher.rightCommandKeyCode,
            flags: TriggerKeyMatcher.commandFlagMask,
            timestampMs: 1_000,
            isAutoRepeat: false
        )))
        triggerTestTap.send(.keyboardEvent(KeyboardEventSnapshot(
            type: .flagsChanged,
            keyCode: TriggerKeyMatcher.rightCommandKeyCode,
            flags: 0,
            timestampMs: 1_300,
            isAutoRepeat: false
        )))

        for _ in 0..<10 where !controller.result.passed {
            await Task.yield()
        }

        XCTAssertTrue(controller.result.passed)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(triggerTestTap.stopCount, 1)
    }

    @MainActor
    func testTriggerTestControllerResumesProductionRuntimeWhenTestMonitorFails() async throws {
        let runtimeTap = FakeCGEventTapClient()
        var preferences = AppPreferences.defaults
        preferences.onboardingCompleted = true
        let services = try Self.makeServices(
            preferences: preferences,
            hotkeyMonitor: GlobalHotkeyMonitor(
                permissionClient: InputMonitoringPermissionClient(
                    status: { .granted },
                    requestAccess: { .granted }
                ),
                eventTapClient: runtimeTap
            )
        )
        let triggerTestTap = FakeCGEventTapClient()
        let controller = OnboardingTriggerTestController(
            makeMonitor: { _ in
                GlobalHotkeyMonitor(
                    permissionClient: InputMonitoringPermissionClient(
                        status: { .granted },
                        requestAccess: { .granted }
                    ),
                    eventTapClient: triggerTestTap,
                    trigger: .rightCommand
                )
            }
        )

        services.startRuntime()
        controller.start(suspending: services)
        triggerTestTap.send(.tapDisabledByUserInput)

        for _ in 0..<10 where runtimeTap.startCount == 1 {
            await Task.yield()
        }

        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(runtimeTap.startCount, 2)
    }

    @MainActor
    func testTriggerTestControllerDoesNotResumeRuntimeWhenOnboardingIncomplete() throws {
        let runtimeTap = FakeCGEventTapClient()
        var preferences = AppPreferences.defaults
        preferences.onboardingCompleted = false
        let services = try Self.makeServices(
            preferences: preferences,
            hotkeyMonitor: GlobalHotkeyMonitor(
                permissionClient: InputMonitoringPermissionClient(
                    status: { .granted },
                    requestAccess: { .granted }
                ),
                eventTapClient: runtimeTap
            )
        )
        let triggerTestTap = FakeCGEventTapClient()
        let controller = OnboardingTriggerTestController(
            makeMonitor: { _ in
                GlobalHotkeyMonitor(
                    permissionClient: InputMonitoringPermissionClient(
                        status: { .granted },
                        requestAccess: { .granted }
                    ),
                    eventTapClient: triggerTestTap,
                    trigger: .rightCommand
                )
            }
        )

        controller.start(suspending: services)
        controller.stop()

        XCTAssertEqual(runtimeTap.startCount, 0)
    }

    @MainActor
    func testCompleteOnboardingUsesLaunchAtLoginBridgeAndNormalizesUnsupportedLocation() async throws {
        let launchAtLogin = FakeLaunchAtLoginManager(status: .enabled)
        let services = try Self.makeServices(
            launchAtLogin: launchAtLogin,
            launchAtLoginLocation: FixedLaunchAtLoginLocation(isSupported: false)
        )

        let status = await services.completeOnboarding(launchAtLogin: true)

        XCTAssertEqual(status, .unsupportedLocation)
        XCTAssertTrue(services.preferences.onboardingCompleted)
        XCTAssertFalse(services.preferences.launchAtLoginEnabled)
        XCTAssertEqual(launchAtLogin.requestedEnabledValues, [])
        let reloaded = services.settingsStore.load()
        XCTAssertTrue(reloaded.onboardingCompleted)
        XCTAssertFalse(reloaded.launchAtLoginEnabled)
    }

    @MainActor
    func testCompleteOnboardingUsesLaunchAtLoginBridgeAndNormalizesRequiresApproval() async throws {
        let launchAtLogin = FakeLaunchAtLoginManager(status: .disabled)
        launchAtLogin.setResult = .requiresApproval
        let services = try Self.makeServices(launchAtLogin: launchAtLogin)

        let status = await services.completeOnboarding(launchAtLogin: true)

        XCTAssertEqual(status, .requiresApproval)
        XCTAssertTrue(services.preferences.onboardingCompleted)
        XCTAssertFalse(services.preferences.launchAtLoginEnabled)
        XCTAssertEqual(launchAtLogin.requestedEnabledValues, [true])
        let reloaded = services.settingsStore.load()
        XCTAssertTrue(reloaded.onboardingCompleted)
        XCTAssertFalse(reloaded.launchAtLoginEnabled)
    }

    @MainActor
    func testProductionCompositionUsesStoredTriggerPreferenceForHotkeyAndDictation() throws {
        let paths = try Self.makeTemporaryPaths()
        var preferences = AppPreferences.defaults
        preferences.trigger = .rightOption
        SettingsStore(storage: .file(paths.settingsFileURL)).save(preferences)

        let services = AppServices.production(
            pathFactory: { paths },
            launchAtLogin: FakeLaunchAtLoginManager(status: .disabled),
            launchAtLoginLocation: FixedLaunchAtLoginLocation(isSupported: true)
        )

        XCTAssertEqual(services.hotkeyMonitor.configuredTrigger, TextifyHotkeys.TriggerPreference.rightOption)
        XCTAssertEqual(services.dictation.configuredTrigger, TextifyHotkeys.TriggerPreference.rightOption)
    }

    @MainActor
    func testChangingTriggerUpdatesRuntimeAndPersistsSelection() throws {
        let services = try Self.makeServices()

        services.setTrigger(.rightOption)

        XCTAssertEqual(services.preferences.trigger, .rightOption)
        XCTAssertEqual(services.settingsStore.load().trigger, .rightOption)
        XCTAssertEqual(services.hotkeyMonitor.configuredTrigger, .rightOption)
        XCTAssertEqual(services.dictation.configuredTrigger, .rightOption)
    }

    @MainActor
    func testModelInstallCoordinatorCancelsActiveOperation() async {
        let gate = SuspendedModelInstallGate()
        let coordinator = ModelInstallCoordinator { _ in
            await gate.wait()
            try Task.checkCancellation()
        }

        let attemptID = coordinator.start()
        for _ in 0..<100 where await gate.callCount() == 0 {
            await Task.yield()
        }

        let callCount = await gate.callCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(coordinator.isActive)
        guard let attemptID else {
            return XCTFail("Expected a stable queue-attempt identity.")
        }
        coordinator.cancel(attemptID: attemptID)
        await gate.release()
        for _ in 0..<100 where coordinator.isActive {
            await Task.yield()
        }

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(
            coordinator.attempt(id: attemptID)?.state.phase,
            .cancelled
        )
    }

    @MainActor
    func testProductionCompositionMigratesUnsupportedExplicitMicrophoneToSystemDefault() throws {
        let paths = try Self.makeTemporaryPaths()
        var preferences = AppPreferences.defaults
        preferences.microphoneSelection = .device(
            deviceUID: "legacy-device",
            lastSeenDisplayName: "Legacy Microphone"
        )
        SettingsStore(storage: .file(paths.settingsFileURL)).save(preferences)

        let services = AppServices.production(
            pathFactory: { paths },
            launchAtLogin: FakeLaunchAtLoginManager(status: .disabled),
            launchAtLoginLocation: FixedLaunchAtLoginLocation(isSupported: true)
        )

        XCTAssertEqual(services.preferences.microphoneSelection, .systemDefault)
        XCTAssertEqual(services.settingsStore.load().microphoneSelection, .systemDefault)
    }

    @MainActor
    func testProductionCompositionReportsPathStartupFailureWithoutCrashing() {
        let services = AppServices.production(
            pathFactory: { throw AppPathFixtureError.unavailable },
            launchAtLogin: FakeLaunchAtLoginManager(status: .disabled),
            launchAtLoginLocation: FixedLaunchAtLoginLocation(isSupported: true)
        )

        XCTAssertEqual(services.startupIssue, AppStartupIssue.applicationPathsUnavailable("unavailable"))
        services.startRuntime()
        XCTAssertEqual(services.runtimeIssue, .persistentStorageUnavailable)
        XCTAssertFalse(services.hotkeyMonitor.isRunning)
    }

    @MainActor
    private static func makeServices(
        preferences: AppPreferences? = .defaults,
        paths providedPaths: AppPaths? = nil,
        settingsStore providedSettingsStore: SettingsStore? = nil,
        hotkeyMonitor: GlobalHotkeyMonitor? = nil,
        launchAtLogin: FakeLaunchAtLoginManager? = nil,
        launchAtLoginLocation: any LaunchAtLoginLocationChecking = FixedLaunchAtLoginLocation(isSupported: true),
        modelCatalogCompatibilityResolver: ModelCatalogCompatibilityResolver = .current(),
        models: any RuntimeModelResolving = FakeRuntimeModelResolver(),
        transcriber: any RuntimeTranscribing = FakeRuntimeTranscriber(),
        voiceCleaner: any RuntimeVoiceCleaning = DisabledRuntimeVoiceCleaning(),
        overlayPresenter: (any RecordingOverlayPresenting)? = nil,
        waitBeforeProcessingIndicator: @escaping @Sendable () async -> Void = {},
        modelWorkflowDurabilityObserver:
            ModelWorkflowDurabilityObserver = .none
    ) throws -> AppServices {
        let paths = try providedPaths ?? makeTemporaryPaths()
        let settingsStore = providedSettingsStore
            ?? SettingsStore(storage: .file(paths.settingsFileURL))
        if let preferences {
            settingsStore.save(preferences)
        }
        let diagnosticsLogger = DiagnosticsLogger(directory: paths.logsDirectory)
        let launchAtLogin = launchAtLogin ?? FakeLaunchAtLoginManager(status: .disabled)
        let hotkeyMonitor = hotkeyMonitor ?? GlobalHotkeyMonitor(
            permissionClient: InputMonitoringPermissionClient(
                status: { .granted },
                requestAccess: { .granted }
            ),
            eventTapClient: FakeCGEventTapClient()
        )
        return AppServices(
            paths: paths,
            settingsStore: settingsStore,
            diagnosticsLogger: diagnosticsLogger,
            dictation: AppDictationService(dependencies: RuntimeDependencies(
                settings: RuntimeSettingsStoreAdapter(storage: .file(paths.settingsFileURL)),
                permissions: FakeRuntimePermissionChecker(),
                models: models,
                audio: FakeRuntimeAudioRecorder(),
                transcriber: transcriber,
                voiceCleaner: voiceCleaner,
                targetCapturer: FakeInsertionTargetCapturer(),
                inserter: FakeInsertionService(),
                diagnostics: RuntimeDiagnosticsLoggerAdapter(logger: diagnosticsLogger),
                postProcessor: FakeRuntimePostProcessor(),
                clock: SuspendedRuntimeClock()
            )),
            hotkeyMonitor: hotkeyMonitor,
            launchAtLogin: launchAtLogin,
            launchAtLoginLocation: launchAtLoginLocation,
            modelCatalogCompatibilityResolver: modelCatalogCompatibilityResolver,
            overlayPresenter: overlayPresenter,
            waitBeforeProcessingIndicator: waitBeforeProcessingIndicator,
            modelWorkflowDurabilityObserver:
                modelWorkflowDurabilityObserver
        )
    }

    private static func writeInstalledStore(
        models: [ModelEntry],
        to paths: AppPaths
    ) throws {
        let records = models.map { model in
            InstalledModelRecord(
                model: model,
                installedAt: "2026-07-24T00:00:00Z",
                localFilesByManifestFilename: Dictionary(
                    uniqueKeysWithValues: model.files.map { file in
                        (
                            file.filename,
                            "/tmp/\(model.id)/\(file.relativePath ?? file.filename)"
                        )
                    }
                )
            )
        }
        let storeURL = ModelStorageLayout(
            rootDirectory: paths.modelsDirectory
        ).installedStoreURL
        try JSONEncoder().encode(
            InstalledModelsStore(records: records)
        ).write(to: storeURL, options: .atomic)
    }

    @discardableResult
    private static func writeInstalledArtifact(
        _ model: ModelEntry,
        to paths: AppPaths
    ) throws -> URL {
        try XCTUnwrap(
            writeInstalledArtifacts([model], to: paths)[model.id]
        )
    }

    private static func writeInstalledArtifacts(
        _ models: [ModelEntry],
        to paths: AppPaths
    ) throws -> [String: URL] {
        let layout = ModelStorageLayout(
            rootDirectory: paths.modelsDirectory
        )
        var records: [InstalledModelRecord] = []
        var directories: [String: URL] = [:]
        for model in models {
            let directory = try layout.installedModelDirectory(
                modelID: model.id
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            var localFiles: [String: String] = [:]
            for file in model.files {
                let relativePath = file.relativePath ?? file.filename
                let fileURL = directory.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("model".utf8).write(to: fileURL)
                localFiles[file.filename] = fileURL.path
            }
            records.append(
                InstalledModelRecord(
                    model: model,
                    installedAt: "2026-07-24T00:00:00Z",
                    localFilesByManifestFilename: localFiles
                )
            )
            directories[model.id] = directory
        }
        try JSONEncoder().encode(
            InstalledModelsStore(records: records)
        ).write(to: layout.installedStoreURL, options: .atomic)
        return directories
    }

    private static func runtimeModel(_ model: ModelEntry) -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: model.id,
            displayName: model.displayName,
            tier: model.tier,
            localModelPath: "/tmp/\(model.id)",
            useGPU: model.runtime.accelerator == .metalGPU,
            threadCount: 1,
            engine: model.runtime.engine,
            variant: model.runtime.variant,
            accelerator: model.runtime.accelerator,
            artifactLayout: model.runtime.artifactLayout,
            runtimeParameters: model.runtimeParameters,
            purpose: model.purpose
        )
    }

    private static func copyModel(
        _ model: ModelEntry,
        id: String,
        displayName: String,
        sizeBytes: Int64? = nil,
        files: [ModelFile]? = nil
    ) -> ModelEntry {
        ModelEntry(
            id: id,
            displayName: displayName,
            tier: model.tier,
            description: model.description,
            sizeBytes: sizeBytes ?? model.sizeBytes,
            files: files ?? model.files,
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

    private static func catalogModel(id: String) throws -> ModelEntry {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try ModelManifest.decode(
            Data(contentsOf: repositoryRoot.appendingPathComponent("models/manifest.json"))
        )
        return try XCTUnwrap(manifest.models.first { $0.id == id })
    }

    private static func retiredOmnilingualModel() throws -> ModelEntry {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try ModelManifest.decode(
            Data(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "Tests/TextifyModelsTests/Fixtures/Models/manifest_v2.production-migration.json"
                )
            )
        )
        return try XCTUnwrap(
            manifest.models.first {
                $0.id == RetiredManagedModelCleanup
                    .omnilingualASR300M.artifactID
            }
        )
    }

    private static func makeTemporaryPaths() throws -> AppPaths {
        let root = temporaryDirectory()
        return try AppPaths.make(
            applicationSupportBase: root.appendingPathComponent("Application Support", isDirectory: true),
            libraryDirectory: root.appendingPathComponent("Library", isDirectory: true)
        )
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyAppTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private enum AppPathFixtureError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "unavailable"
    }
}

private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var currentStatus: LaunchAtLoginStatus
    var setResult: LaunchAtLoginStatus?
    var liveStatusAfterSetFailure: LaunchAtLoginStatus?
    private(set) var requestedEnabledValues: [Bool] = []

    init(status: LaunchAtLoginStatus) {
        self.currentStatus = status
    }

    func status() -> LaunchAtLoginStatus {
        currentStatus
    }

    func setEnabled(_ enabled: Bool) async -> LaunchAtLoginStatus {
        requestedEnabledValues.append(enabled)
        let result = setResult ?? (enabled ? LaunchAtLoginStatus.enabled : .disabled)
        if case .failed = result, let liveStatusAfterSetFailure {
            currentStatus = liveStatusAfterSetFailure
        } else {
            currentStatus = result
        }
        return result
    }
}

private struct FixedLaunchAtLoginLocation: LaunchAtLoginLocationChecking {
    let isSupported: Bool
}

private final class FakeCGEventTapClient: CGEventTapClient, @unchecked Sendable {
    private var handler: (@Sendable (CGEventTapMessage) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var startError: Error?

    func start(handler: @escaping @Sendable (CGEventTapMessage) -> Void) throws -> CGEventTapHandle {
        startCount += 1
        if let startError {
            throw startError
        }
        self.handler = handler
        return CGEventTapHandle()
    }

    func setEnabled(_ handle: CGEventTapHandle, enabled: Bool) {}

    func stop(_ handle: CGEventTapHandle) {
        stopCount += 1
    }

    func send(_ message: CGEventTapMessage) {
        handler?(message)
    }
}

private struct FakeRuntimePermissionChecker: RuntimePermissionChecking {
    func permissionSnapshot() async -> RuntimePermissionSnapshot {
        RuntimePermissionSnapshot(
            microphone: .granted,
            accessibility: .granted,
            inputMonitoring: .granted
        )
    }
}

private struct FakeRuntimeModelResolver: RuntimeModelResolving {
    func resolveActiveModel(preferences: AppPreferences) async -> RuntimeActiveModel? {
        nil
    }

    func readiness(for model: RuntimeActiveModel?) async -> RuntimeModelReadiness {
        .noActiveModel
    }
}

private actor CandidateRuntimeModelResolver: RuntimeModelResolving {
    private let modelsByID: [String: RuntimeActiveModel]
    private let readinessByModelID: [String: RuntimeModelReadiness]
    private var suspendedReadinessModelID: String?
    private var readinessContinuation:
        CheckedContinuation<Void, Never>?

    init(
        models: [RuntimeActiveModel],
        readinessByModelID: [String: RuntimeModelReadiness] = [:]
    ) {
        self.modelsByID = Dictionary(
            uniqueKeysWithValues: models.map { ($0.id, $0) }
        )
        self.readinessByModelID = readinessByModelID
    }

    func resolveActiveModel(
        preferences: AppPreferences
    ) async -> RuntimeActiveModel? {
        guard let modelID = preferences.activeModelID else {
            return nil
        }
        return modelsByID[modelID]
    }

    func resolveActiveVoiceCleaningModel(
        preferences: AppPreferences
    ) async -> RuntimeActiveModel? {
        guard let modelID = preferences.activeVoiceCleaningModelID else {
            return nil
        }
        return modelsByID[modelID]
    }

    func readiness(
        for model: RuntimeActiveModel?
    ) async -> RuntimeModelReadiness {
        guard let model else {
            return .noActiveModel
        }
        if suspendedReadinessModelID == model.id {
            await withCheckedContinuation { continuation in
                readinessContinuation = continuation
            }
        }
        return readinessByModelID[model.id] ?? .ready(modelID: model.id)
    }

    func suspendReadiness(for modelID: String) {
        suspendedReadinessModelID = modelID
    }

    func isReadinessSuspended() -> Bool {
        readinessContinuation != nil
    }

    func releaseReadiness() {
        suspendedReadinessModelID = nil
        let continuation = readinessContinuation
        readinessContinuation = nil
        continuation?.resume()
    }
}

private struct ReadyRuntimeModelResolver: RuntimeModelResolving {
    private let model = RuntimeActiveModel(
        id: "ggml-small.en-q5_1",
        displayName: "Balanced - Whisper small.en",
        tier: "balanced",
        localModelPath: "/tmp/ggml-small.en-q5_1.bin",
        useGPU: true,
        threadCount: 1
    )

    func resolveActiveModel(preferences: AppPreferences) async -> RuntimeActiveModel? {
        model
    }

    func readiness(for model: RuntimeActiveModel?) async -> RuntimeModelReadiness {
        .ready(modelID: self.model.id)
    }
}

private enum ActivationPreparationError: Error {
    case rejected
}

private final class FailingSettingsSaveFileManager:
    FileManager,
    @unchecked Sendable {
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

private actor ActivationTranscriberSpy: RuntimeTranscribing {
    private let failingModelIDs: Set<String>
    private var preparedIDs: [String] = []
    private var unloadCountValue = 0

    init(failingModelIDs: Set<String> = []) {
        self.failingModelIDs = failingModelIDs
    }

    var readiness: RuntimeModelReadiness {
        get async {
            guard let modelID = preparedIDs.last else {
                return .noActiveModel
            }
            return .ready(modelID: modelID)
        }
    }

    func prepare(model: RuntimeActiveModel) async throws {
        preparedIDs.append(model.id)
        if failingModelIDs.contains(model.id) {
            throw ActivationPreparationError.rejected
        }
    }

    func transcribe(
        _ audio: TranscriptionAudioBuffer
    ) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "",
            noSpeechProbability: 1,
            averageLogProbability: -2,
            compressionRatio: 1
        )
    }

    func unload() async {
        unloadCountValue += 1
        preparedIDs.removeAll()
    }

    func preparedModelIDs() -> [String] {
        preparedIDs
    }

    func unloadCount() -> Int {
        unloadCountValue
    }
}

private actor ActivationVoiceCleanerSpy: RuntimeVoiceCleaning {
    private let failingModelIDs: Set<String>
    private var preparedIDs: [String] = []
    private var unloadCountValue = 0

    init(failingModelIDs: Set<String> = []) {
        self.failingModelIDs = failingModelIDs
    }

    func prepare(model: RuntimeActiveModel) async throws {
        preparedIDs.append(model.id)
        if failingModelIDs.contains(model.id) {
            throw ActivationPreparationError.rejected
        }
    }

    func clean(
        _ audio: TranscriptionAudioBuffer
    ) async throws -> TranscriptionAudioBuffer {
        audio
    }

    func unload() async {
        unloadCountValue += 1
        preparedIDs.removeAll()
    }

    func preparedModelIDs() -> [String] {
        preparedIDs
    }

    func unloadCount() -> Int {
        unloadCountValue
    }
}

@MainActor
private final class OverlayPresenterSpy: RecordingOverlayPresenting {
    private(set) var states: [RecordingOverlayState] = []
    private(set) var preferences: [RecordingOverlayPreferences] = []

    func present(
        _ state: RecordingOverlayState,
        preferences: RecordingOverlayPreferences
    ) {
        states.append(state)
        self.preferences.append(preferences)
    }
}

private actor OverlayDelayGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiting = false
    private var released = false

    func wait() async {
        guard !released else {
            return
        }
        waiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func isWaiting() -> Bool {
        waiting
    }

    func release() {
        released = true
        waiting = false
        continuation?.resume()
        continuation = nil
    }
}

private actor FakeRuntimeAudioRecorder: RuntimeAudioRecording {
    func startRecording(
        microphone: MicrophoneSelection,
        maximumDurationSeconds: Double,
        onSpeechDetected: @escaping @Sendable () -> Void,
        onMaximumDurationReached: @escaping @Sendable () -> Void
    ) async throws {}

    func finishRecording() async throws -> CanonicalAudioBuffer {
        CanonicalAudioBuffer(samples: [])
    }

    func discardRecording() async {}
}

private struct FakeInsertionTargetCapturer: InsertionTargetCapturing {
    func currentTargetIdentity() async -> InsertionTargetIdentity? {
        InsertionTargetIdentity(processIdentifier: 42, bundleIdentifier: "com.example.Target")
    }
}

private actor FakeRuntimeTranscriber: RuntimeTranscribing {
    var readiness: RuntimeModelReadiness {
        get async { .noActiveModel }
    }

    func prepare(model: RuntimeActiveModel) async throws {}

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "",
            noSpeechProbability: 1,
            averageLogProbability: -2,
            compressionRatio: 1
        )
    }

    func unload() async {}
}

private actor FakeInsertionService: InsertionService {
    func insert(_ request: InsertionRequest) async -> InsertionOutcome {
        .notInserted(.emptyText)
    }
}

private struct FakeRuntimePostProcessor: RuntimePostProcessing {
    func process(rawText: String, preferences: AppPreferences) async -> String {
        rawText
    }
}

private struct SuspendedRuntimeClock: RuntimeClock {
    func nowMilliseconds() -> Int {
        0
    }

    func sleep(milliseconds: Int) async {
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
    }
}

private actor SuspendedModelInstallGate {
    private var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        calls += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func callCount() -> Int {
        calls
    }

    func release() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private struct AppWorkflowBoundaryEvent: Equatable {
    let boundary: ModelWorkflowDurableBoundary
    let artifactID: String?
}

private final class AppWorkflowBoundaryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [AppWorkflowBoundaryEvent] = []

    var observer: ModelWorkflowDurabilityObserver {
        ModelWorkflowDurabilityObserver { [weak self] boundary, artifactID in
            guard let self else {
                return
            }
            lock.lock()
            recordedEvents.append(
                AppWorkflowBoundaryEvent(
                    boundary: boundary,
                    artifactID: artifactID
                )
            )
            lock.unlock()
        }
    }

    var events: [AppWorkflowBoundaryEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }
}
