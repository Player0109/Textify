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
        hotkeyMonitor: GlobalHotkeyMonitor? = nil,
        launchAtLogin: FakeLaunchAtLoginManager? = nil,
        launchAtLoginLocation: any LaunchAtLoginLocationChecking = FixedLaunchAtLoginLocation(isSupported: true),
        modelCatalogCompatibilityResolver: ModelCatalogCompatibilityResolver = .current(),
        models: any RuntimeModelResolving = FakeRuntimeModelResolver(),
        transcriber: any RuntimeTranscribing = FakeRuntimeTranscriber(),
        voiceCleaner: any RuntimeVoiceCleaning = DisabledRuntimeVoiceCleaning(),
        overlayPresenter: (any RecordingOverlayPresenting)? = nil,
        waitBeforeProcessingIndicator: @escaping @Sendable () async -> Void = {}
    ) throws -> AppServices {
        let paths = try providedPaths ?? makeTemporaryPaths()
        let settingsStore = SettingsStore(storage: .file(paths.settingsFileURL))
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
            waitBeforeProcessingIndicator: waitBeforeProcessingIndicator
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
        return readinessByModelID[model.id] ?? .ready(modelID: model.id)
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

private actor ActivationTranscriberSpy: RuntimeTranscribing {
    private let failingModelIDs: Set<String>
    private var preparedIDs: [String] = []

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

    func preparedModelIDs() -> [String] {
        preparedIDs
    }
}

private actor ActivationVoiceCleanerSpy: RuntimeVoiceCleaning {
    private let failingModelIDs: Set<String>
    private var preparedIDs: [String] = []

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

    func unload() async {}

    func preparedModelIDs() -> [String] {
        preparedIDs
    }
}

@MainActor
private final class OverlayPresenterSpy: RecordingOverlayPresenting {
    private(set) var states: [RecordingOverlayState] = []

    func present(_ state: RecordingOverlayState) {
        states.append(state)
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
