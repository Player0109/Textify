import Foundation
import Network
import Observation
import TextifyAudio
import TextifyDiagnostics
import TextifyHotkeys
import TextifyInsertion
import TextifyModels
import TextifyRuntime
import TextifySettings
import TextifyTranscription

@MainActor
@Observable
final class AppServices {
    let settingsRouter = SettingsRouter()
    let paths: AppPaths
    let settingsStore: SettingsStore
    let diagnosticsLogger: DiagnosticsLogger
    let dictation: AppDictationService
    let hotkeyMonitor: GlobalHotkeyMonitor
    let launchAtLogin: any LaunchAtLoginManaging
    let launchAtLoginLocation: any LaunchAtLoginLocationChecking
    let modelCatalogCompatibilityResolver: ModelCatalogCompatibilityResolver
    let modelStorageInventory: ModelStorageInventoryCoordinator
    let startupIssue: AppStartupIssue?
    @ObservationIgnored private let modelTransferNetworkObserver:
        ModelTransferNetworkObserver?

    private var installedModelsStore: InstalledModelsStore

    @ObservationIgnored lazy var modelInstallCoordinator = ModelInstallCoordinator(
        queueStore: ModelInstallQueueStore(
            fileURL: ModelStorageLayout(
                rootDirectory: paths.modelsDirectory
            ).installQueueURL
        ),
        installOperation: { [weak self] modelID, onStateChange in
            guard let self,
                  self.startupIssue == nil,
                  ProductionModelInstallConfiguration.current != nil
            else {
                throw ModelInstallCoordinatorError.storageOrConfigurationUnavailable
            }

            guard let manifest =
                self.modelCatalogCoordinator.authoritativeManifest else {
                throw ModelInstallCoordinatorError.catalogCheckUnavailable
            }
            let installer = ModelInstaller(
                layout: ModelStorageLayout(rootDirectory: self.paths.modelsDirectory),
                transport: URLSessionDownloadTransport(),
                currentAppVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "1.1.0"
            )
            let installedRecord: InstalledModelRecord
            do {
                installedRecord = try await installer.install(
                    modelID: modelID,
                    from: manifest
                ) { state in
                    guard !state.phase.isTerminal else {
                        return
                    }
                    onStateChange(state)
                }
            } catch is URLError {
                throw ModelInstallCoordinatorError.networkUnavailable
            }
            try await self.completeModelInstall(
                installedRecord.model,
                onStateChange: onStateChange
            )
        },
        resumableDataProvider: { [weak self] attempt in
            guard let self,
                  let expectedFiles = self.modelCatalogCoordinator
                    .authoritativeManifest?.models.first(
                        where: { $0.id == attempt.artifactID }
                    )?.files
            else {
                return nil
            }
            return try? ModelInstallResumableDataInspector(
                layout: ModelStorageLayout(
                    rootDirectory: self.paths.modelsDirectory
                )
            ).inspect(
                for: attempt,
                expectedFiles: expectedFiles
            )
        },
        lastSuccessfulCatalogIntegrityCheckAt: { [weak self] in
            self?.modelCatalogCoordinator
                .lastSuccessfulCatalogIntegrityCheckAt
        },
        integrityCheckOperation: { [weak self] _ in
            guard let self else {
                return .waitingForCatalogCheck
            }
            switch await self.modelCatalogCoordinator.refresh() {
            case .authoritativeIntegrityAccepted:
                guard let checkedAt = self.modelCatalogCoordinator
                    .lastSuccessfulCatalogIntegrityCheckAt else {
                    return .waitingForCatalogCheck
                }
                return .ready(checkedAt: checkedAt)
            case .networkUnavailable:
                return .waitingForNetwork
            case .presentationAccepted,
                 .catalogUnavailable,
                 .rejected,
                 .requiresNewerTextify:
                return .waitingForCatalogCheck
            }
        },
        isArtifactKnownRevoked: { _ in
            false
        },
        lifecycleDidChange: { [weak self] in
            self?.refreshModelStorageInventory()
        }
    )

    @ObservationIgnored lazy var modelCatalogCoordinator = ModelCatalogCoordinator(
        initialManifest: nil,
        loadOperation: {
            throw ModelCatalogRefreshError.unavailable
        }
    )

    var preferences: AppPreferences
    var launchAtLoginStatus: LaunchAtLoginStatus
    var launchAtLoginOperationError: String?
    var launchAtLoginFailedRequestedEnabled: Bool?
    var onboardingStep = OnboardingStep.welcome
    var overlayState = RecordingOverlayState.hidden
    var runtimeIssue: AppRuntimeIssue?

    @ObservationIgnored private var runtimeStarted = false
    @ObservationIgnored private var diagnosticsStarted = false
    @ObservationIgnored private let overlayPresenter: any RecordingOverlayPresenting
    @ObservationIgnored private let waitBeforeProcessingIndicator: @Sendable () async -> Void
    @ObservationIgnored private let waitBeforeTerminalStatusDismissal: @Sendable () async -> Void
    @ObservationIgnored private var processingOverlayTask: Task<Void, Never>?
    @ObservationIgnored private var terminalStatusTask: Task<Void, Never>?
    @ObservationIgnored private var overlayUpdateGeneration = 0
    private var managedReadinessByModelID:
        [String: ModelCatalogManagedReadiness] = [:]

    static func production() -> AppServices {
        production(
            pathFactory: { try AppPaths.production() },
            launchAtLogin: LaunchAtLoginController(),
            launchAtLoginLocation: LaunchAtLoginLocationChecker()
        )
    }

    static func production(
        pathFactory: () throws -> AppPaths,
        fileManager: FileManager = .default,
        launchAtLogin: any LaunchAtLoginManaging,
        launchAtLoginLocation: any LaunchAtLoginLocationChecking
    ) -> AppServices {
        do {
            return production(
                paths: try pathFactory(),
                fileManager: fileManager,
                launchAtLogin: launchAtLogin,
                launchAtLoginLocation: launchAtLoginLocation,
                startupIssue: nil
            )
        } catch {
            return production(
                paths: AppPaths.temporaryFallback(fileManager: fileManager),
                fileManager: fileManager,
                launchAtLogin: launchAtLogin,
                launchAtLoginLocation: launchAtLoginLocation,
                startupIssue: .applicationPathsUnavailable(String(describing: error))
            )
        }
    }

    init(
        paths: AppPaths,
        settingsStore: SettingsStore,
        diagnosticsLogger: DiagnosticsLogger,
        dictation: AppDictationService,
        hotkeyMonitor: GlobalHotkeyMonitor,
        launchAtLogin: any LaunchAtLoginManaging,
        launchAtLoginLocation: any LaunchAtLoginLocationChecking = LaunchAtLoginLocationChecker(),
        modelCatalogCompatibilityResolver: ModelCatalogCompatibilityResolver = .current(),
        overlayPresenter: (any RecordingOverlayPresenting)? = nil,
        waitBeforeProcessingIndicator: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(nanoseconds: 900_000_000)
        },
        waitBeforeTerminalStatusDismissal: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        },
        modelTransferNetworkObserver: ModelTransferNetworkObserver? = nil,
        startupIssue: AppStartupIssue? = nil
    ) {
        self.paths = paths
        self.settingsStore = settingsStore
        self.diagnosticsLogger = diagnosticsLogger
        self.dictation = dictation
        self.hotkeyMonitor = hotkeyMonitor
        self.launchAtLogin = launchAtLogin
        self.launchAtLoginLocation = launchAtLoginLocation
        self.modelCatalogCompatibilityResolver = modelCatalogCompatibilityResolver
        let storageScanner = ModelStorageInventoryScanner(
            layout: ModelStorageLayout(rootDirectory: paths.modelsDirectory),
            fileManager: FileManager.default
        )
        self.modelStorageInventory = ModelStorageInventoryCoordinator {
            installedRecords in
            try await storageScanner.scan(installedRecords: installedRecords)
        }
        self.overlayPresenter = overlayPresenter ?? RecordingOverlayPresenter()
        self.waitBeforeProcessingIndicator = waitBeforeProcessingIndicator
        self.waitBeforeTerminalStatusDismissal = waitBeforeTerminalStatusDismissal
        self.modelTransferNetworkObserver = modelTransferNetworkObserver
        self.startupIssue = startupIssue
        self.runtimeIssue = startupIssue == nil ? nil : .persistentStorageUnavailable
        let installedModelsStore = Self.loadInstalledModelsStore(paths: paths)
        self.installedModelsStore = installedModelsStore
        self.managedReadinessByModelID = Dictionary(
            uniqueKeysWithValues: installedModelsStore.records.map {
                ($0.model.id, .installed)
            }
        )
        self.preferences = settingsStore.load()
        self.launchAtLoginStatus = launchAtLoginLocation.isSupported ? launchAtLogin.status() : .unsupportedLocation
        updateOverlay()
        observeDictationStatus()
        Task { @MainActor [weak self] in
            await self?.refreshManagedModelReadiness()
        }
        modelCatalogCoordinator = makeProductionModelCatalogCoordinator()
        modelTransferNetworkObserver?.start { [weak self] in
            Task { @MainActor [weak self] in
                self?.modelInstallCoordinator.networkDidBecomeAvailable()
            }
        }
        refreshModelStorageInventory()
    }

    func startRuntime() {
        guard startupIssue == nil else {
            runtimeIssue = .persistentStorageUnavailable
            runtimeStarted = false
            return
        }
        guard !runtimeStarted || !hotkeyMonitor.isRunning else {
            return
        }

        let dictation = dictation

        if !diagnosticsStarted {
            diagnosticsStarted = true
            let diagnosticsLogger = diagnosticsLogger
            let appVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown"
            let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
            Task {
                try? await diagnosticsLogger.rotate()
                try? await diagnosticsLogger.log(
                    .appStarted(appVersion: appVersion, macOSVersion: macOSVersion)
                )
            }
        }

        Task { @MainActor in
            await dictation.prepareActiveModelIfAvailable()
        }

        let result = hotkeyMonitor.start(
            onEvent: { event in
                Task { @MainActor in
                    await dictation.handleTriggerEvent(event)
                }
            },
            onFailure: { [weak self] error in
                Task { @MainActor in
                    if AppServices.hotkeyFailureLeavesMonitorStopped(error) {
                        self?.runtimeStarted = false
                    }
                    self?.runtimeIssue = .hotkeyMonitorUnavailable
                    await dictation.refreshReadiness()
                }
            }
        )
        if case .success = result {
            runtimeStarted = true
            runtimeIssue = nil
        } else {
            runtimeIssue = .hotkeyMonitorUnavailable
        }
    }

    func stopRuntime() {
        hotkeyMonitor.stop()
        runtimeStarted = false
    }

    func setTrigger(_ trigger: TextifySettings.TriggerPreference) {
        let wasRunning = hotkeyMonitor.isRunning
        stopRuntime()
        let runtimeTrigger = Self.hotkeyTrigger(for: trigger)
        guard dictation.updateConfiguredTrigger(runtimeTrigger) else {
            if wasRunning {
                startRuntime()
            }
            return
        }
        hotkeyMonitor.updateTrigger(runtimeTrigger)
        preferences.trigger = trigger
        savePreferences()
        if wasRunning || preferences.onboardingCompleted {
            startRuntime()
        }
    }

    var configuredHotkeyTrigger: TextifyHotkeys.TriggerPreference {
        Self.hotkeyTrigger(for: preferences.trigger)
    }

    private func observeDictationStatus() {
        withObservationTracking {
            _ = dictation.status
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.updateOverlay()
                self.scheduleTerminalStatusDismissal(for: self.dictation.status)
                self.observeDictationStatus()
            }
        }
    }

    private func makeProductionModelCatalogCoordinator() -> ModelCatalogCoordinator {
        guard startupIssue == nil,
              let configuration = ProductionModelInstallConfiguration.current
        else {
            return ModelCatalogCoordinator {
                throw ModelCatalogRefreshError.unavailable
            }
        }

        let verifier = ManifestVerifier(
            trustedKeys: configuration.trustedKeys,
            legacyPolicy: .publishedV1_1
        )
        let store = TrustedCatalogStore(
            fileURL: paths.manifestCacheDirectory
                .appendingPathComponent("catalog-state.json"),
            verifier: verifier
        )
        let loader = ProductionModelManifestLoader(
            configuration: configuration
        )
        var storedState: TrustedCatalogStoredState
        var bootstrapIssue: TrustedCatalogSecurityIssue?
        do {
            storedState = try store.load()
        } catch {
            bootstrapIssue = TrustedCatalogSecurityIssue(
                reason: .cacheCorruption
            )
            storedState = TrustedCatalogStoredState(
                securityIssue: bootstrapIssue
            )
        }

        let bundledSnapshot: TrustedCatalogSnapshot?
        do {
            bundledSnapshot = try loader.loadBundledSnapshot()
        } catch {
            let issue = TrustedCatalogSecurityIssue(
                reason: .bundledCatalogInvalid,
                highestAcceptedRevision: storedState.highestAcceptedRevision
            )
            bootstrapIssue = issue
            storedState.securityIssue = issue
            bundledSnapshot = nil
        }

        if let bootstrapIssue {
            logCatalogSecurityIssue(bootstrapIssue)
        }
        return ModelCatalogCoordinator(
            storedState: storedState,
            bundledSnapshot: bundledSnapshot,
            snapshotLoadOperation: {
                try await loader.downloadRemoteSnapshot()
            },
            saveOperation: { state in
                try store.save(state)
            },
            diagnosticOperation: { [weak self] issue in
                self?.logCatalogSecurityIssue(issue)
            },
            integrityCheckAcceptedOperation: { [weak self] in
                self?.modelInstallCoordinator
                    .catalogIntegrityCheckDidSucceed()
            }
        )
    }

    private func logCatalogSecurityIssue(_ issue: TrustedCatalogSecurityIssue) {
        let logger = diagnosticsLogger
        Task {
            try? await logger.log(
                .catalogUpdateRejected(
                    severity: issue.severity.rawValue,
                    reasonCode: issue.reason.rawValue,
                    candidateRevision: issue.candidateRevision,
                    acceptedRevision: issue.highestAcceptedRevision
                )
            )
        }
    }

    private func updateOverlay() {
        updateOverlay(for: dictation.status)
    }

    func updateOverlay(for status: DictationRuntimeStatus) {
        overlayUpdateGeneration &+= 1
        let generation = overlayUpdateGeneration
        processingOverlayTask?.cancel()
        processingOverlayTask = nil

        guard case .processing = status else {
            presentOverlay(DictationOverlayPresentation.state(for: status))
            return
        }

        presentOverlay(.hidden)
        let waitBeforeProcessingIndicator = waitBeforeProcessingIndicator
        processingOverlayTask = Task { @MainActor [weak self] in
            await waitBeforeProcessingIndicator()
            guard !Task.isCancelled,
                  let self,
                  self.overlayUpdateGeneration == generation
            else {
                return
            }
            self.presentOverlay(.processing)
            self.processingOverlayTask = nil
        }
    }

    private func presentOverlay(_ state: RecordingOverlayState) {
        overlayState = state
        overlayPresenter.present(state)
    }

    private func scheduleTerminalStatusDismissal(for status: DictationRuntimeStatus) {
        terminalStatusTask?.cancel()
        terminalStatusTask = nil

        let shouldDismiss: Bool
        switch status {
        case .completed, .cancelled, .failed:
            shouldDismiss = true
        case .blocked(.excludedApp):
            shouldDismiss = false
        case .blocked:
            shouldDismiss = true
        case .idle, .waitingForActivation, .recording, .processing, .inserting:
            shouldDismiss = false
        }
        guard shouldDismiss else {
            return
        }

        let waitBeforeTerminalStatusDismissal = waitBeforeTerminalStatusDismissal
        terminalStatusTask = Task { @MainActor [weak self] in
            await waitBeforeTerminalStatusDismissal()
            guard !Task.isCancelled,
                  let self,
                  self.dictation.status == status
            else {
                return
            }
            self.dictation.dismissTerminalStatus()
            self.terminalStatusTask = nil
        }
    }

    @discardableResult
    func completeOnboarding(launchAtLogin enabled: Bool) async -> LaunchAtLoginStatus {
        preferences.onboardingCompleted = true
        preferences.launchAtLoginEnabled = enabled
        savePreferences()
        let status = await setLaunchAtLoginEnabled(enabled)
        await dictation.refreshReadiness()
        startRuntime()
        return status
    }

    func savePreferences() {
        settingsStore.save(preferences)
    }

    func isModelInstalled(_ modelID: String) -> Bool {
        installedModel(modelID) != nil
    }

    func isModelActive(_ modelID: String) -> Bool {
        guard let model = installedModel(modelID)?.model else {
            return false
        }
        switch model.purpose {
        case .transcription:
            return preferences.activeModelID == modelID
        case .voiceCleaning:
            return preferences.activeVoiceCleaningModelID == modelID
        }
    }

    var installedModels: [ModelEntry] {
        installedModelsStore.records.map(\.model)
    }

    var installedModelRecords: [InstalledModelRecord] {
        installedModelsStore.records
    }

    func modelCatalogExperience(
        for purpose: ModelPurpose,
        onDiskBytesByModelID: [String: Int64]? = nil,
        query: ModelCatalogQuery = ModelCatalogQuery()
    ) -> ModelCatalogExperience {
        var scopedQuery = query
        scopedQuery.purpose = purpose
        var readiness = managedReadinessByModelID
        let measuredBytes: [String: Int64]
        let storageInventoryByModelID: [String: ModelStorageArtifactInventory]
        let installedSizeStatus: ModelCatalogInstalledSizeStatus
        if let onDiskBytesByModelID {
            measuredBytes = onDiskBytesByModelID
            storageInventoryByModelID = [:]
            installedSizeStatus = .measured
        } else {
            switch modelStorageInventory.state {
            case .calculating:
                measuredBytes = [:]
                storageInventoryByModelID = [:]
                installedSizeStatus = .calculating
            case .unavailable:
                measuredBytes = [:]
                storageInventoryByModelID = [:]
                installedSizeStatus = .unavailable
            case let .available(_, snapshot):
                measuredBytes = Dictionary(
                    uniqueKeysWithValues: snapshot.artifacts.compactMap {
                        artifact in
                        artifact.onDiskBytes.map {
                            (artifact.artifactID, $0)
                        }
                    }
                )
                storageInventoryByModelID = Dictionary(
                    uniqueKeysWithValues: snapshot.artifacts.map {
                        ($0.artifactID, $0)
                    }
                )
                installedSizeStatus = .measured
                for artifact in snapshot.artifacts
                where artifact.condition == .needsRepair {
                    readiness[artifact.artifactID] = .needsRepair
                }
            }
        }
        return ModelCatalogExperience(
            trustedManifest: modelCatalogCoordinator.manifest,
            compatibilityResolver: modelCatalogCompatibilityResolver,
            installedRecords: installedModelRecords,
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID: preferences.activeModelID,
                voiceCleaningModelID: preferences.activeVoiceCleaningModelID
            ),
            transferStatesByModelID: modelInstallCoordinator.artifactStates,
            managedReadinessByModelID: readiness,
            onDiskBytesByModelID: measuredBytes,
            storageInventoryByModelID: storageInventoryByModelID,
            installedSizeStatus: installedSizeStatus,
            query: scopedQuery
        )
    }

    func refreshModelStorageInventory() {
        modelStorageInventory.refresh(
            installedRecords: installedModelsStore.records
        )
    }

    func refreshInstalledModels() {
        installedModelsStore = Self.loadInstalledModelsStore(paths: paths)
        managedReadinessByModelID = Dictionary(
            uniqueKeysWithValues: installedModelsStore.records.map {
                ($0.model.id, .installed)
            }
        )
        Task { @MainActor [weak self] in
            await self?.refreshManagedModelReadiness()
        }
        refreshModelStorageInventory()
    }

    func completeModelInstall(
        _ installedModel: ModelEntry,
        onStateChange: @escaping @Sendable (DownloadState) -> Void
    ) async throws {
        refreshInstalledModels()
        managedReadinessByModelID[installedModel.id] = .ready
        try Task.checkCancellation()
        if isModelActive(installedModel.id) {
            _ = await dictation.prepareActiveModelIfAvailable()
        }
        try Task.checkCancellation()
        onStateChange(DownloadState(
            modelID: installedModel.id,
            phase: .installed,
            bytesDownloaded: installedModel.sizeBytes,
            totalBytes: installedModel.sizeBytes,
            message: installedModel.purpose == .voiceCleaning
                ? "Voice cleaner installed. Enable it when you are ready."
                : "Model installed. Select Use Model to activate it."
        ))
    }

    var availableTranscriptionLanguages: [TranscriptionLanguage] {
        guard let activeModelID = preferences.activeModelID,
              let model = installedModel(activeModelID)?.model
        else {
            return [.english]
        }
        return availableTranscriptionLanguages(for: model)
    }

    private func availableTranscriptionLanguages(
        for model: ModelEntry
    ) -> [TranscriptionLanguage] {
        if model.capabilities.languages.contains("*") {
            return TranscriptionLanguage.allCases
        }
        let supported = TranscriptionLanguage.allCases.filter {
            $0 != .automatic && model.capabilities.languages.contains($0.rawValue)
        }
        return supported.count > 1 ? [.automatic] + supported : supported
    }

    func setTranscriptionLanguage(_ language: TranscriptionLanguage) {
        guard availableTranscriptionLanguages.contains(language) else {
            return
        }
        preferences.transcriptionLanguage = language
        savePreferences()
        Task { @MainActor [dictation] in
            _ = await dictation.prepareActiveModelIfAvailable()
        }
    }

    @discardableResult
    func activateInstalledModel(
        _ modelID: String
    ) async -> AppModelActivationResult {
        guard dictation.allowsModelTransactions else {
            return .dictationInProgress
        }
        guard let model = installedModel(modelID)?.model else {
            return .notInstalled
        }
        let compatibility = activationCompatibility(for: modelID)
        guard compatibility == .compatible else {
            return .incompatible(compatibility)
        }

        let candidatePreferences = preferencesSelecting(model)

        let preparation = await dictation.prepareModelSelection(
            modelID: modelID,
            purpose: model.purpose,
            preferences: candidatePreferences
        )
        switch preparation {
        case .ready:
            managedReadinessByModelID[modelID] = .ready
            preferences = candidatePreferences
            savePreferences()
            _ = await dictation.prepareActiveModelIfAvailable()
            return .activated
        case .needsRepair:
            managedReadinessByModelID[modelID] = .needsRepair
            _ = await dictation.prepareActiveModelIfAvailable()
            return .needsRepair
        case .failed:
            _ = await dictation.prepareActiveModelIfAvailable()
            return .preparationFailed
        case .busy:
            return .dictationInProgress
        }
    }

    @discardableResult
    func disableVoiceCleaning() async -> Bool {
        guard dictation.allowsModelTransactions else {
            return false
        }
        preferences.activeVoiceCleaningModelID = nil
        savePreferences()
        _ = await dictation.prepareActiveModelIfAvailable()
        return true
    }

    func importCustomWhisperModel(
        from sourceURL: URL,
        displayName: String
    ) async throws -> ModelEntry {
        let importer = CustomWhisperModelImporter(
            layout: ModelStorageLayout(rootDirectory: paths.modelsDirectory)
        )
        let record = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: displayName,
                licenseName: "User-provided model; license not verified by Textify"
            )
        )
        refreshInstalledModels()
        guard await activateInstalledModel(record.model.id) == .activated else {
            try? importer.removeImportedModel(modelID: record.model.id)
            refreshInstalledModels()
            throw ModelInstallCoordinatorError.modelPreparationFailed
        }
        return record.model
    }

    func removeInstalledModel(_ modelID: String) async throws {
        guard preferences.activeModelID != modelID,
              preferences.activeVoiceCleaningModelID != modelID else {
            throw AppModelRemovalError.activeModelMustBeSwitchedFirst
        }
        let manager = InstalledModelManager(
            layout: ModelStorageLayout(rootDirectory: paths.modelsDirectory)
        )
        _ = try await Task.detached(priority: .utility) {
            try manager.remove(modelID: modelID)
        }.value
        refreshInstalledModels()
        managedReadinessByModelID[modelID] = nil
        _ = await dictation.refreshReadiness()
    }

    private func installedModel(_ modelID: String) -> InstalledModelRecord? {
        installedModelsStore.record(forModelID: modelID)
    }

    func refreshManagedModelReadiness() async {
        let records = installedModelsStore.records
        for record in records {
            let model = record.model
            let readiness = await dictation.modelReadiness(
                modelID: model.id,
                purpose: model.purpose,
                preferences: preferencesSelecting(model)
            )
            guard isModelInstalled(model.id) else {
                continue
            }
            switch readiness {
            case .ready:
                managedReadinessByModelID[model.id] = .ready
            case .loading, .warming:
                managedReadinessByModelID[model.id] = .installed
            case .noActiveModel, .missing, .failed:
                managedReadinessByModelID[model.id] = .needsRepair
            }
        }
    }

    private func preferencesSelecting(_ model: ModelEntry) -> AppPreferences {
        var candidate = preferences
        switch model.purpose {
        case .transcription:
            candidate.activeModelID = model.id
            let languages = availableTranscriptionLanguages(for: model)
            if !languages.contains(candidate.transcriptionLanguage) {
                candidate.transcriptionLanguage = languages.first ?? .english
            }
        case .voiceCleaning:
            candidate.activeVoiceCleaningModelID = model.id
        }
        return candidate
    }

    private func activationCompatibility(
        for modelID: String
    ) -> ModelCatalogCompatibility {
        guard let manifest = modelCatalogCoordinator.manifest,
              manifest.models.contains(where: { $0.id == modelID })
        else {
            return .compatible
        }
        return modelCatalogCompatibilityResolver.compatibility(
            for: modelID,
            in: manifest
        )
    }

    private static func loadInstalledModelsStore(paths: AppPaths) -> InstalledModelsStore {
        guard let data = try? Data(contentsOf: ModelStorageLayout(
            rootDirectory: paths.modelsDirectory
        ).installedStoreURL),
              let store = try? JSONDecoder().decode(InstalledModelsStore.self, from: data)
        else {
            return InstalledModelsStore()
        }
        return store
    }

    var canChangeLaunchAtLogin: Bool {
        launchAtLoginLocation.isSupported && launchAtLoginStatus != .unsupportedLocation
    }

    @discardableResult
    func refreshLaunchAtLoginStatus() -> LaunchAtLoginStatus {
        let status = currentLaunchAtLoginStatus()
        launchAtLoginStatus = status
        launchAtLoginOperationError = nil
        launchAtLoginFailedRequestedEnabled = nil
        return status
    }

    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) async -> LaunchAtLoginStatus {
        let currentStatus = refreshLaunchAtLoginStatus()
        guard currentStatus != .unsupportedLocation else {
            persistLaunchAtLoginPreference(for: currentStatus)
            return currentStatus
        }

        let operationStatus = await launchAtLogin.setEnabled(enabled)
        switch operationStatus {
        case .failed(let message):
            let status = refreshLaunchAtLoginStatus()
            launchAtLoginOperationError = message
            launchAtLoginFailedRequestedEnabled = enabled
            persistLaunchAtLoginPreference(for: status)
            return operationStatus
        case let status:
            launchAtLoginStatus = status
            launchAtLoginOperationError = nil
            launchAtLoginFailedRequestedEnabled = nil
            persistLaunchAtLoginPreference(for: status)
            return status
        }
    }

    private func persistLaunchAtLoginPreference(for status: LaunchAtLoginStatus) {
        switch status {
        case .enabled:
            preferences.launchAtLoginEnabled = true
        case .disabled, .requiresApproval, .unsupportedLocation, .unavailable:
            preferences.launchAtLoginEnabled = false
        case .failed:
            break
        }
        savePreferences()
    }

    private func currentLaunchAtLoginStatus() -> LaunchAtLoginStatus {
        guard launchAtLoginLocation.isSupported else {
            return .unsupportedLocation
        }
        return launchAtLogin.status()
    }

    nonisolated private static func hotkeyFailureLeavesMonitorStopped(_ error: HotkeyMonitorError) -> Bool {
        switch error {
        case .eventTapDisabledByUserInput,
             .eventTapCreationFailed,
             .runLoopSourceCreationFailed,
             .notRunning:
            return true
        case .alreadyRunning:
            return false
        }
    }

    private static func production(
        paths: AppPaths,
        fileManager: FileManager,
        launchAtLogin: any LaunchAtLoginManaging,
        launchAtLoginLocation: any LaunchAtLoginLocationChecking,
        startupIssue: AppStartupIssue?
    ) -> AppServices {
        let settingsStore = SettingsStore(storage: .file(paths.settingsFileURL), fileManager: fileManager)
        let diagnosticsLogger = DiagnosticsLogger(directory: paths.logsDirectory)
        let modelLayout = ModelStorageLayout(rootDirectory: paths.modelsDirectory)
        let whisperRuntime = WhisperRuntime()
        let parakeetRuntime = ParakeetRuntime()
        let paraformerRuntime = ParaformerRuntime()
        let sherpaOnnxRuntime = SherpaOnnxRuntime()
        let transcribeCppRuntime = TranscribeCppRuntime()
        let mlxAudioRuntime = MLXAudioRuntime()
        let mossFormer2VoiceCleaningRuntime = MossFormer2VoiceCleaningRuntime()
        let liteRTLMRuntime = LiteRTLMRuntime(
            cacheDirectory: paths.applicationSupportDirectory
                .appendingPathComponent("LiteRTLMCache", isDirectory: true).path
        )
        let transcriber = MultiEngineRuntimeTranscribingAdapter(
            whisper: WhisperRuntimeTranscribingAdapter(runtime: whisperRuntime),
            parakeet: ParakeetRuntimeTranscribingAdapter(runtime: parakeetRuntime),
            paraformer: ParaformerRuntimeTranscribingAdapter(runtime: paraformerRuntime),
            sherpaOnnx: SherpaOnnxRuntimeTranscribingAdapter(runtime: sherpaOnnxRuntime),
            transcribeCpp: TranscribeCppRuntimeTranscribingAdapter(runtime: transcribeCppRuntime),
            mlxAudio: MLXAudioRuntimeTranscribingAdapter(runtime: mlxAudioRuntime),
            liteRTLM: LiteRTLMRuntimeTranscribingAdapter(runtime: liteRTLMRuntime)
        )
        var preferences = settingsStore.load()
        if preferences.microphoneSelection != .systemDefault {
            preferences.microphoneSelection = .systemDefault
            settingsStore.save(preferences)
        }
        let trigger = hotkeyTrigger(for: preferences.trigger)
        let targetChecker = SystemInsertionTargetChecker()
        let dependencies = RuntimeDependencies(
            settings: RuntimeSettingsStoreAdapter(storage: .file(paths.settingsFileURL)),
            permissions: SystemRuntimePermissionAdapter(),
            models: RuntimeModelResolverAdapter(layout: modelLayout),
            audio: RuntimeAudioRecorderAdapter(),
            transcriber: transcriber,
            voiceCleaner: MossFormer2RuntimeVoiceCleaner(
                runtime: mossFormer2VoiceCleaningRuntime
            ),
            targetCapturer: targetChecker,
            inserter: PasteInsertionService(
                pasteboard: SystemPasteboardClient(),
                eventPoster: SystemEventPoster(),
                accessibility: .live,
                targetChecker: targetChecker
            ),
            diagnostics: RuntimeDiagnosticsLoggerAdapter(logger: diagnosticsLogger),
            postProcessor: RuntimePostProcessingAdapter(),
            clock: SystemRuntimeClock()
        )

        return AppServices(
            paths: paths,
            settingsStore: settingsStore,
            diagnosticsLogger: diagnosticsLogger,
            dictation: AppDictationService(
                dependencies: dependencies,
                triggerStateMachine: TriggerStateMachine(trigger: trigger)
            ),
            hotkeyMonitor: GlobalHotkeyMonitor(trigger: trigger),
            launchAtLogin: launchAtLogin,
            launchAtLoginLocation: launchAtLoginLocation,
            modelTransferNetworkObserver: ModelTransferNetworkObserver(),
            startupIssue: startupIssue
        )
    }

    private static func hotkeyTrigger(
        for preference: TextifySettings.TriggerPreference
    ) -> TextifyHotkeys.TriggerPreference {
        switch preference {
        case .rightCommand:
            return .rightCommand
        case .rightOption:
            return .rightOption
        case .rightControl:
            return .rightControl
        case .controlSpace:
            return .controlSpace
        }
    }
}

final class ModelTransferNetworkObserver: @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let callbackQueue: DispatchQueue
    private let lock = NSLock()
    private var recoveryState = ModelTransferNetworkRecoveryState()
    private var recoveryOperation: (@Sendable () -> Void)?
    private var isStarted = false

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        callbackQueue: DispatchQueue = DispatchQueue(
            label: "io.github.Player0109.Textify.model-transfer-network"
        )
    ) {
        self.monitor = monitor
        self.callbackQueue = callbackQueue
    }

    func start(
        recoveryOperation: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        guard !isStarted else {
            lock.unlock()
            return
        }
        isStarted = true
        self.recoveryOperation = recoveryOperation
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            self?.receive(path.status)
        }
        monitor.start(queue: callbackQueue)
    }

    private func receive(_ status: NWPath.Status) {
        let shouldRecover: Bool
        let operation: (@Sendable () -> Void)?
        lock.lock()
        shouldRecover = recoveryState.receive(
            isSatisfied: status == .satisfied
        )
        operation = recoveryOperation
        lock.unlock()

        if shouldRecover {
            operation?()
        }
    }

    deinit {
        monitor.cancel()
    }
}

struct ModelTransferNetworkRecoveryState {
    private var wasSatisfied: Bool?

    mutating func receive(isSatisfied: Bool) -> Bool {
        defer {
            wasSatisfied = isSatisfied
        }
        return isSatisfied && wasSatisfied != true
    }
}

enum AppStartupIssue: Equatable {
    case applicationPathsUnavailable(String)
}

enum AppRuntimeIssue: Equatable {
    case persistentStorageUnavailable
    case hotkeyMonitorUnavailable

    var userMessage: String {
        switch self {
        case .persistentStorageUnavailable:
            return "Textify cannot access its Application Support folder. Check disk space and folder permissions, then reopen Textify. Dictation and model installation are disabled to protect your settings and model data."
        case .hotkeyMonitorUnavailable:
            return "Textify could not start the dictation trigger. Retry the trigger, or reopen Textify."
        }
    }
}

enum ModelInstallCoordinatorError: Error {
    case storageOrConfigurationUnavailable
    case modelPreparationFailed
    case bundledCatalogIncomplete
    case networkUnavailable
    case catalogCheckUnavailable
}

enum ModelTransferPrerequisiteResult: Equatable, Sendable {
    case ready(checkedAt: Date)
    case waitingForNetwork
    case waitingForCatalogCheck
    case revoked
}

enum AppModelActivationResult: Equatable {
    case activated
    case dictationInProgress
    case notInstalled
    case incompatible(ModelCatalogCompatibility)
    case needsRepair
    case preparationFailed

    func message(for model: ProductionModelPresentation) -> String {
        switch self {
        case .activated:
            return model.activationMessage
        case .dictationInProgress:
            return "Wait for the current dictation to finish, then try again."
        case .notInstalled:
            return "Install \(model.displayName) before \(model.useLabel.lowercased())."
        case let .incompatible(compatibility):
            return compatibility.catalogExplanation
        case .needsRepair:
            return "\(model.displayName) needs repair. Reinstall it and try again."
        case .preparationFailed:
            return "Textify kept the previous model because \(model.displayName) could not be prepared."
        }
    }
}

enum AppModelRemovalError: Error, LocalizedError {
    case activeModelMustBeSwitchedFirst

    var errorDescription: String? {
        switch self {
        case .activeModelMustBeSwitchedFirst:
            return "Select another model or disable voice cleaning before deleting the active model."
        }
    }
}

@MainActor
@Observable
final class ModelInstallCoordinator {
    typealias InstallOperation = @MainActor @Sendable (
        _ modelID: String,
        @escaping @Sendable (DownloadState) -> Void
    ) async throws -> Void

    private let installOperation: InstallOperation
    private let queueStore: ModelInstallQueueStore?
    private let resumableDataProvider:
        @MainActor @Sendable (ModelInstallQueueAttempt) -> ModelInstallResumableData?
    private let makeAttemptID: @Sendable () -> String
    private let nowISO8601: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let freshnessPolicy: ModelTransferFreshnessPolicy
    private let lastSuccessfulCatalogIntegrityCheckAt:
        @MainActor @Sendable () -> Date?
    private let integrityCheckOperation:
        @MainActor @Sendable (String) async -> ModelTransferPrerequisiteResult
    private let isArtifactKnownRevoked:
        @MainActor @Sendable (String) -> Bool
    private let lifecycleDidChange: @MainActor @Sendable () -> Void
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var activeAttemptID: String?
    @ObservationIgnored private var queue: ModelInstallQueue
    @ObservationIgnored private var persistenceIsAvailable = true

    private(set) var revision = 0
    private(set) var persistenceErrorMessage: String?

    var isActive: Bool {
        _ = revision
        return installTask != nil
    }

    var hasNonterminalAttempts: Bool {
        _ = revision
        return queue.headAttempt != nil
    }

    var attempts: [ModelInstallQueueAttempt] {
        _ = revision
        return queue.attempts
    }

    var artifactStates: [String: DownloadState] {
        _ = revision
        return queue.latestStatesByArtifactID
    }

    init(
        queueStore: ModelInstallQueueStore? = nil,
        installOperation: @escaping InstallOperation,
        resumableDataProvider: @escaping @MainActor @Sendable (
            ModelInstallQueueAttempt
        ) -> ModelInstallResumableData? = { _ in nil },
        freshnessPolicy: ModelTransferFreshnessPolicy =
            ModelTransferFreshnessPolicy(),
        lastSuccessfulCatalogIntegrityCheckAt:
            @escaping @MainActor @Sendable () -> Date? = { Date() },
        integrityCheckOperation:
            @escaping @MainActor @Sendable (
                String
            ) async -> ModelTransferPrerequisiteResult = { _ in
                .ready(checkedAt: Date())
            },
        isArtifactKnownRevoked:
            @escaping @MainActor @Sendable (String) -> Bool = { _ in false },
        makeAttemptID: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        },
        nowISO8601: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        },
        now: @escaping @Sendable () -> Date = { Date() },
        lifecycleDidChange: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.queueStore = queueStore
        self.installOperation = installOperation
        self.resumableDataProvider = resumableDataProvider
        self.freshnessPolicy = freshnessPolicy
        self.lastSuccessfulCatalogIntegrityCheckAt =
            lastSuccessfulCatalogIntegrityCheckAt
        self.integrityCheckOperation = integrityCheckOperation
        self.isArtifactKnownRevoked = isArtifactKnownRevoked
        self.makeAttemptID = makeAttemptID
        self.nowISO8601 = nowISO8601
        self.now = now
        self.lifecycleDidChange = lifecycleDidChange

        if let queueStore {
            do {
                queue = try queueStore.loadForRelaunch()
                try queueStore.save(queue)
            } catch {
                queue = ModelInstallQueue()
                persistenceIsAvailable = false
                persistenceErrorMessage = "Textify could not restore the Downloads queue."
            }
        } else {
            queue = ModelInstallQueue()
        }

        Task { @MainActor [weak self] in
            self?.processNextAttempt()
        }
    }

    convenience init(
        installOperation: @escaping @MainActor @Sendable (
            @escaping @Sendable (DownloadState) -> Void
        ) async throws -> Void
    ) {
        self.init { _, onStateChange in
            try await installOperation(onStateChange)
        }
    }

    @discardableResult
    func start(
        modelID: String = ProductionModelPolicy.requiredModelID,
        purpose: ModelPurpose = .transcription,
        action: ModelInstallQueueAction = .install
    ) -> String? {
        guard persistenceIsAvailable else {
            return nil
        }
        let previousQueue = queue
        let attemptID = makeAttemptID()
        do {
            try queue.authorize(
                artifactID: modelID,
                purpose: purpose,
                action: action,
                attemptID: attemptID,
                createdAt: nowISO8601()
            )
            guard persistQueue() else {
                queue = previousQueue
                return nil
            }
            recordLifecycleChange()
        } catch {
            return nil
        }
        processNextAttempt()
        return attemptID
    }

    func cancel(attemptID: String) {
        guard let attempt = queue.attempt(id: attemptID),
              !attempt.state.phase.isTerminal,
              attempt.state.phase != .installing
        else {
            return
        }
        let previousQueue = queue
        do {
            try queue.cancel(attemptID: attemptID)
            guard persistQueue() else {
                queue = previousQueue
                return
            }
            recordLifecycleChange()
            if activeAttemptID == attemptID {
                installTask?.cancel()
            } else {
                processNextAttempt()
            }
        } catch {
            return
        }
    }

    func pause(attemptID: String) {
        guard let attempt = queue.attempt(id: attemptID),
              attempt.state.phase == .downloading
        else {
            return
        }
        do {
            try transition(
                attemptID: attemptID,
                phase: .paused,
                message: "Download paused."
            )
            if activeAttemptID == attemptID {
                installTask?.cancel()
            }
        } catch {
            return
        }
    }

    func resume(attemptID: String) {
        guard let attempt = queue.attempt(id: attemptID),
              attempt.state.phase == .paused
        else {
            return
        }
        do {
            try transition(
                attemptID: attemptID,
                phase: .queued,
                message: "Queued"
            )
            processNextAttempt()
        } catch {
            return
        }
    }

    @discardableResult
    func retry(attemptID: String) -> String? {
        guard persistenceIsAvailable else {
            return nil
        }
        if queue.attempt(id: attemptID)?.state.phase
            == .waitingForCatalogCheck {
            do {
                try transition(
                    attemptID: attemptID,
                    phase: .queued,
                    message: "Checking catalog authority."
                )
                processNextAttempt()
                return attemptID
            } catch {
                return nil
            }
        }
        let previousQueue = queue
        let newAttemptID = makeAttemptID()
        do {
            try queue.retry(
                attemptID: attemptID,
                newAttemptID: newAttemptID,
                createdAt: nowISO8601()
            )
            guard persistQueue() else {
                queue = previousQueue
                return nil
            }
            recordLifecycleChange()
        } catch {
            return nil
        }
        processNextAttempt()
        return newAttemptID
    }

    func attempt(id: String) -> ModelInstallQueueAttempt? {
        queue.attempt(id: id)
    }

    func networkDidBecomeAvailable() {
        requeueWaitingHead(
            phases: [.waitingForNetwork],
            message: "Checking network and catalog authority."
        )
    }

    func catalogIntegrityCheckDidSucceed() {
        requeueWaitingHead(
            phases: [.waitingForNetwork, .waitingForCatalogCheck],
            message: "Catalog authority restored."
        )
    }

    private func processNextAttempt() {
        guard installTask == nil,
              persistenceIsAvailable,
              let attempt = queue.nextRunnableAttempt
        else {
            return
        }

        activeAttemptID = attempt.id
        installTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if finishIfKnownRevoked(attempt) {
                return
            }

            let currentTime = now()
            if !freshnessPolicy.isFresh(
                lastSuccessfulCheckAt:
                    lastSuccessfulCatalogIntegrityCheckAt(),
                now: currentTime
            ) {
                let prerequisite = await integrityCheckOperation(
                    attempt.artifactID
                )
                guard !Task.isCancelled,
                      queue.attempt(id: attempt.id)?.state.phase
                        .isTerminal == false
                else {
                    completeTask(attemptID: attempt.id)
                    return
                }
                switch prerequisite {
                case let .ready(checkedAt):
                    guard freshnessPolicy.isFresh(
                        lastSuccessfulCheckAt: checkedAt,
                        now: now()
                    ),
                    freshnessPolicy.isFresh(
                        lastSuccessfulCheckAt:
                            lastSuccessfulCatalogIntegrityCheckAt(),
                        now: now()
                    ) else {
                        finish(
                            attemptID: attempt.id,
                            phase: .waitingForCatalogCheck,
                            message: "Waiting for catalog check."
                        )
                        return
                    }
                case .waitingForNetwork:
                    finish(
                        attemptID: attempt.id,
                        phase: .waitingForNetwork,
                        message: "Waiting for network."
                    )
                    return
                case .waitingForCatalogCheck:
                    finish(
                        attemptID: attempt.id,
                        phase: .waitingForCatalogCheck,
                        message: "Waiting for catalog check."
                    )
                    return
                case .revoked:
                    finish(
                        attemptID: attempt.id,
                        phase: .revoked,
                        message: "Install revoked."
                    )
                    return
                }
            }

            if finishIfKnownRevoked(attempt) {
                return
            }

            do {
                try transition(
                    attemptID: attempt.id,
                    phase: .checkingSpace,
                    message: "Preparing model download."
                )
            } catch {
                completeTask(attemptID: attempt.id)
                return
            }
            do {
                try await installOperation(attempt.artifactID) { [weak self] state in
                    Task { @MainActor [weak self] in
                        self?.receive(
                            state,
                            forAttemptID: attempt.id
                        )
                    }
                }
                finish(
                    attemptID: attempt.id,
                    phase: .installed,
                    message: "Model installed."
                )
            } catch is CancellationError {
                finishCancelledTask(attemptID: attempt.id)
            } catch ModelInstallCoordinatorError.networkUnavailable {
                finish(
                    attemptID: attempt.id,
                    phase: .waitingForNetwork,
                    message: "Waiting for network."
                )
            } catch ModelInstallCoordinatorError.catalogCheckUnavailable {
                finish(
                    attemptID: attempt.id,
                    phase: .waitingForCatalogCheck,
                    message: "Waiting for catalog check."
                )
            } catch let error as ModelInstallError {
                finish(
                    attemptID: attempt.id,
                    phase: .failed,
                    message: error.description
                )
            } catch {
                finish(
                    attemptID: attempt.id,
                    phase: .failed,
                    message: "Model install failed. Check your connection and try again."
                )
            }
        }
    }

    private func finishIfKnownRevoked(
        _ attempt: ModelInstallQueueAttempt
    ) -> Bool {
        guard isArtifactKnownRevoked(attempt.artifactID) else {
            return false
        }
        finish(
            attemptID: attempt.id,
            phase: .revoked,
            message: "Install revoked."
        )
        return true
    }

    private func requeueWaitingHead(
        phases: [DownloadPhase],
        message: String
    ) {
        guard installTask == nil,
              let head = queue.headAttempt,
              phases.contains(head.state.phase)
        else {
            return
        }
        do {
            try transition(
                attemptID: head.id,
                phase: .queued,
                message: message
            )
            processNextAttempt()
        } catch {
            return
        }
    }

    private func receive(
        _ state: DownloadState,
        forAttemptID attemptID: String
    ) {
        guard activeAttemptID == attemptID,
              !state.phase.isTerminal,
              let attempt = queue.attempt(id: attemptID),
              !attempt.state.phase.isTerminal
        else {
            return
        }
        do {
            let previousQueue = queue
            let shouldPersist = attempt.state.phase != state.phase
            try queue.transition(
                attemptID: attemptID,
                to: DownloadState(
                    modelID: attempt.artifactID,
                    phase: state.phase,
                    bytesDownloaded: state.bytesDownloaded,
                    totalBytes: state.totalBytes,
                    message: state.message,
                    attemptID: attemptID
                )
            )
            if shouldPersist, !persistQueue() {
                queue = previousQueue
                return
            }
            if shouldPersist {
                recordLifecycleChange()
            } else {
                revision &+= 1
            }
        } catch {
            return
        }
    }

    private func finishCancelledTask(attemptID: String) {
        guard let attempt = queue.attempt(id: attemptID) else {
            completeTask(attemptID: attemptID)
            return
        }
        if !attempt.state.phase.isTerminal,
           attempt.state.phase != .paused {
            finish(
                attemptID: attemptID,
                phase: .cancelled,
                message: "Download cancelled."
            )
            return
        }
        associateResumableDataIfAvailable(attemptID: attemptID)
        completeTask(attemptID: attemptID)
    }

    private func finish(
        attemptID: String,
        phase: DownloadPhase,
        message: String
    ) {
        if let attempt = queue.attempt(id: attemptID),
           !attempt.state.phase.isTerminal,
           attempt.state.phase != .paused {
            try? transition(
                attemptID: attemptID,
                phase: phase,
                message: message
            )
        }
        if phase != .installed {
            associateResumableDataIfAvailable(attemptID: attemptID)
        }
        completeTask(attemptID: attemptID)
    }

    private func completeTask(attemptID: String) {
        guard activeAttemptID == attemptID else {
            return
        }
        installTask = nil
        activeAttemptID = nil
        processNextAttempt()
    }

    private func transition(
        attemptID: String,
        phase: DownloadPhase,
        message: String
    ) throws {
        guard let attempt = queue.attempt(id: attemptID) else {
            throw ModelInstallQueueError.attemptNotFound(attemptID)
        }
        let previousQueue = queue
        try queue.transition(
            attemptID: attemptID,
            to: DownloadState(
                modelID: attempt.artifactID,
                phase: phase,
                bytesDownloaded: attempt.state.bytesDownloaded,
                totalBytes: attempt.state.totalBytes,
                message: message,
                attemptID: attemptID
            )
        )
        guard persistQueue() else {
            queue = previousQueue
            throw ModelInstallCoordinatorError.storageOrConfigurationUnavailable
        }
        recordLifecycleChange()
    }

    private func associateResumableDataIfAvailable(attemptID: String) {
        guard let attempt = queue.attempt(id: attemptID),
              let resumableData = resumableDataProvider(attempt)
        else {
            return
        }
        let previousQueue = queue
        do {
            try queue.associateResumableData(
                resumableData,
                with: attemptID
            )
            guard persistQueue() else {
                queue = previousQueue
                return
            }
            recordLifecycleChange()
        } catch {
            return
        }
    }

    @discardableResult
    private func persistQueue() -> Bool {
        guard let queueStore else {
            return true
        }
        do {
            try queueStore.save(queue)
            persistenceErrorMessage = nil
            return true
        } catch {
            persistenceIsAvailable = false
            persistenceErrorMessage = "Textify could not save the Downloads queue."
            return false
        }
    }

    private func recordLifecycleChange() {
        revision &+= 1
        lifecycleDidChange()
    }
}

@MainActor
@Observable
final class ModelCatalogCoordinator {
    typealias LoadOperation = @Sendable () async throws -> ModelManifest
    typealias SnapshotLoadOperation =
        @Sendable () async throws -> TrustedCatalogSnapshot
    typealias SaveOperation =
        @MainActor @Sendable (TrustedCatalogStoredState) throws -> Void
    typealias DiagnosticOperation =
        @MainActor @Sendable (TrustedCatalogSecurityIssue) -> Void

    private enum Candidate {
        case manifest(ModelManifest)
        case snapshot(TrustedCatalogSnapshot)

        var manifest: ModelManifest {
            switch self {
            case let .manifest(manifest):
                return manifest
            case let .snapshot(snapshot):
                return snapshot.manifest
            }
        }

        var snapshot: TrustedCatalogSnapshot? {
            if case let .snapshot(snapshot) = self {
                return snapshot
            }
            return nil
        }
    }

    private let loadCandidate: @Sendable () async throws -> Candidate
    private let saveOperation: SaveOperation?
    private let diagnosticOperation: DiagnosticOperation
    private let now: @Sendable () -> Date
    private let integrityCheckAcceptedOperation:
        @MainActor @Sendable () -> Void
    @ObservationIgnored private var openDestinations: Set<ModelPurpose> = []
    @ObservationIgnored private var presentedSnapshot: TrustedCatalogSnapshot?
    @ObservationIgnored private var stagedSnapshot: TrustedCatalogSnapshot?
    @ObservationIgnored private var refreshInProgress = false
    @ObservationIgnored private var refreshWaiters:
        [CheckedContinuation<ModelCatalogRefreshResult, Never>] = []

    private(set) var manifest: ModelManifest?
    private(set) var stagedManifest: ModelManifest?
    private(set) var highestAcceptedRevision: String?
    private(set) var presentedRevision: String?
    private(set) var stagedRevision: String?
    private(set) var securityIssue: TrustedCatalogSecurityIssue?
    private(set) var lastSuccessfulCatalogIntegrityCheckAt: Date?
    private(set) var status: ModelCatalogCoordinatorStatus

    var isLoading: Bool {
        refreshInProgress || manifest == nil && status == .checking
    }

    var authoritativeManifest: ModelManifest? {
        stagedManifest ?? manifest
    }

    var errorMessage: String? {
        switch status {
        case .checking, .checkingForUpdates, .trusted, .updateAvailable:
            return nil
        case .offline:
            return "Using the last trusted catalog while Textify is offline."
        case let .securityFailure(reason):
            return "Textify rejected an untrusted catalog update (\(reason.displayName)). The last trusted catalog remains available."
        case let .requiresNewerTextify(manifestVersion):
            return "Catalog version \(manifestVersion) requires a newer version of Textify."
        case .unavailable:
            return "The signed model catalog is unavailable. Installed models still work offline."
        }
    }

    init(
        initialManifest: ModelManifest? = nil,
        loadOperation: @escaping LoadOperation,
        diagnosticOperation: @escaping DiagnosticOperation = { _ in },
        now: @escaping @Sendable () -> Date = { Date() },
        integrityCheckAcceptedOperation:
            @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.loadCandidate = {
            .manifest(try await loadOperation())
        }
        self.saveOperation = nil
        self.diagnosticOperation = diagnosticOperation
        self.now = now
        self.integrityCheckAcceptedOperation =
            integrityCheckAcceptedOperation
        self.manifest = initialManifest
        self.highestAcceptedRevision = initialManifest?.generatedAt
        self.presentedRevision = initialManifest?.generatedAt
        self.lastSuccessfulCatalogIntegrityCheckAt = nil
        self.status = initialManifest == nil ? .checking : .trusted
    }

    init(
        storedState: TrustedCatalogStoredState,
        bundledSnapshot: TrustedCatalogSnapshot?,
        snapshotLoadOperation: @escaping SnapshotLoadOperation,
        saveOperation: @escaping SaveOperation,
        diagnosticOperation: @escaping DiagnosticOperation = { _ in },
        now: @escaping @Sendable () -> Date = { Date() },
        integrityCheckAcceptedOperation:
            @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.loadCandidate = {
            .snapshot(try await snapshotLoadOperation())
        }
        self.saveOperation = saveOperation
        self.diagnosticOperation = diagnosticOperation
        self.now = now
        self.integrityCheckAcceptedOperation =
            integrityCheckAcceptedOperation

        var resolved = storedState
        if let staged = resolved.stagedSnapshot {
            resolved.presentedSnapshot = staged
            resolved.stagedSnapshot = nil
        }
        if let bundledSnapshot {
            let bundledDate = Self.revisionDate(bundledSnapshot.revision)
            let highestDate = resolved.highestAcceptedRevision.flatMap(
                Self.revisionDate
            )
            if highestDate == nil || bundledDate.map({
                $0 > highestDate!
            }) == true {
                resolved.highestAcceptedRevision = bundledSnapshot.revision
                resolved.presentedSnapshot = bundledSnapshot
                resolved.stagedSnapshot = nil
            } else if resolved.presentedSnapshot == nil,
                      resolved.highestAcceptedRevision == bundledSnapshot.revision {
                resolved.presentedSnapshot = bundledSnapshot
            }
        }

        if resolved != storedState {
            do {
                try saveOperation(resolved)
            } catch {
                resolved = storedState
            }
        }

        presentedSnapshot = resolved.presentedSnapshot
        stagedSnapshot = resolved.stagedSnapshot
        manifest = resolved.presentedSnapshot?.manifest
        stagedManifest = resolved.stagedSnapshot?.manifest
        highestAcceptedRevision = resolved.highestAcceptedRevision
        presentedRevision = resolved.presentedSnapshot?.revision
        stagedRevision = resolved.stagedSnapshot?.revision
        securityIssue = resolved.securityIssue
        lastSuccessfulCatalogIntegrityCheckAt =
            resolved.lastSuccessfulCatalogIntegrityCheckAt
        if let issue = resolved.securityIssue {
            status = .securityFailure(issue.reason)
        } else {
            status = resolved.presentedSnapshot == nil ? .checking : .trusted
        }
    }

    @discardableResult
    func refresh() async -> ModelCatalogRefreshResult {
        if refreshInProgress {
            return await withCheckedContinuation { continuation in
                refreshWaiters.append(continuation)
            }
        }
        refreshInProgress = true
        status = manifest == nil ? .checking : .checkingForUpdates
        let result: ModelCatalogRefreshResult
        do {
            result = try accept(try await loadCandidate())
        } catch let error as ModelCatalogRefreshError {
            handle(error)
            result = switch error {
            case .networkUnavailable:
                .networkUnavailable
            case .unavailable:
                .catalogUnavailable
            case let .requiresNewerTextify(manifestVersion):
                .requiresNewerTextify(manifestVersion: manifestVersion)
            }
        } catch let error as ManifestVerificationError {
            switch error {
            case let .unsupportedManifestVersion(version):
                handle(
                    .requiresNewerTextify(manifestVersion: version)
                )
                result = .requiresNewerTextify(manifestVersion: version)
            default:
                reject(reason: .invalidSignature)
                result = .rejected
            }
        } catch is DecodingError {
            reject(reason: .strictDecoding)
            result = .rejected
        } catch is ModelManifestDecodingError {
            reject(reason: .strictDecoding)
            result = .rejected
        } catch let error as ProductionModelPolicyError {
            switch error {
            case let .unsupportedManifestVersion(version):
                handle(
                    .requiresNewerTextify(manifestVersion: version)
                )
                result = .requiresNewerTextify(manifestVersion: version)
            default:
                reject(reason: .schemaValidation)
                result = .rejected
            }
        } catch let error as URLError where Self.isNetworkUnavailable(error) {
            handle(.networkUnavailable)
            result = .networkUnavailable
        } catch {
            handle(.unavailable)
            result = .catalogUnavailable
        }
        refreshInProgress = false
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: result)
        }
        return result
    }

    func destinationOpened(_ purpose: ModelPurpose) {
        openDestinations.insert(purpose)
    }

    func destinationClosed(_ purpose: ModelPurpose) {
        openDestinations.remove(purpose)
        if openDestinations.isEmpty {
            applyStagedUpdate()
        }
    }

    func destinationChanged(
        from previousPurpose: ModelPurpose?,
        to nextPurpose: ModelPurpose?
    ) {
        if let nextPurpose {
            openDestinations.insert(nextPurpose)
        }
        if let previousPurpose {
            openDestinations.remove(previousPurpose)
        }
        if openDestinations.isEmpty {
            applyStagedUpdate()
        }
    }

    func applyStagedUpdate() {
        guard let stagedManifest else {
            return
        }
        let nextState = TrustedCatalogStoredState(
            highestAcceptedRevision: highestAcceptedRevision,
            presentedSnapshot: stagedSnapshot ?? presentedSnapshot,
            stagedSnapshot: nil,
            securityIssue: securityIssue,
            lastSuccessfulCatalogIntegrityCheckAt:
                lastSuccessfulCatalogIntegrityCheckAt
        )
        guard persist(nextState) else {
            return
        }
        manifest = stagedManifest
        presentedRevision = stagedRevision
        presentedSnapshot = stagedSnapshot ?? presentedSnapshot
        self.stagedManifest = nil
        stagedRevision = nil
        stagedSnapshot = nil
        status = securityIssue.map {
            .securityFailure($0.reason)
        } ?? .trusted
    }

    private func accept(
        _ candidate: Candidate
    ) throws -> ModelCatalogRefreshResult {
        let candidateManifest = candidate.manifest
        guard let candidateDate = Self.revisionDate(
            candidateManifest.generatedAt
        ) else {
            reject(
                reason: .schemaValidation,
                candidateRevision: candidateManifest.generatedAt
            )
            return .rejected
        }

        if let highestAcceptedRevision,
           let highestDate = Self.revisionDate(highestAcceptedRevision) {
            if candidateDate < highestDate
                || candidateDate == highestDate
                    && !matchesAcceptedCandidate(candidateManifest) {
                reject(
                    reason: .rollback,
                    candidateRevision: candidateManifest.generatedAt
                )
                return .rejected
            }
            if candidateDate == highestDate {
                let acceptedAt = candidate.snapshot == nil
                    ? lastSuccessfulCatalogIntegrityCheckAt
                    : now()
                securityIssue = nil
                let nextState = storedState(
                    securityIssue: nil,
                    lastSuccessfulCatalogIntegrityCheckAt: acceptedAt
                )
                guard persist(nextState) else {
                    return .catalogUnavailable
                }
                lastSuccessfulCatalogIntegrityCheckAt = acceptedAt
                status = stagedManifest == nil
                    ? .trusted
                    : .updateAvailable
                if candidate.snapshot != nil {
                    integrityCheckAcceptedOperation()
                    return .authoritativeIntegrityAccepted
                }
                return .presentationAccepted
            }
        }

        let shouldStage = !openDestinations.isEmpty && manifest != nil
        let acceptedAt = candidate.snapshot == nil
            ? lastSuccessfulCatalogIntegrityCheckAt
            : now()
        let nextState = TrustedCatalogStoredState(
            highestAcceptedRevision: candidateManifest.generatedAt,
            presentedSnapshot: shouldStage
                ? presentedSnapshot
                : candidate.snapshot ?? presentedSnapshot,
            stagedSnapshot: shouldStage ? candidate.snapshot : nil,
            securityIssue: nil,
            lastSuccessfulCatalogIntegrityCheckAt: acceptedAt
        )
        guard persist(nextState) else {
            return .catalogUnavailable
        }

        highestAcceptedRevision = candidateManifest.generatedAt
        securityIssue = nil
        lastSuccessfulCatalogIntegrityCheckAt = acceptedAt
        if shouldStage {
            stagedManifest = candidateManifest
            stagedRevision = candidateManifest.generatedAt
            stagedSnapshot = candidate.snapshot
            status = .updateAvailable
        } else {
            manifest = candidateManifest
            presentedRevision = candidateManifest.generatedAt
            presentedSnapshot = candidate.snapshot ?? presentedSnapshot
            stagedManifest = nil
            stagedRevision = nil
            stagedSnapshot = nil
            status = .trusted
        }
        if candidate.snapshot != nil {
            integrityCheckAcceptedOperation()
            return .authoritativeIntegrityAccepted
        }
        return .presentationAccepted
    }

    private func matchesAcceptedCandidate(_ candidate: ModelManifest) -> Bool {
        stagedManifest == candidate || manifest == candidate
    }

    private func handle(_ error: ModelCatalogRefreshError) {
        switch error {
        case .networkUnavailable, .unavailable:
            if let securityIssue {
                status = .securityFailure(securityIssue.reason)
            } else if stagedManifest != nil {
                status = .updateAvailable
            } else {
                status = manifest == nil ? .unavailable : .offline
            }
        case let .requiresNewerTextify(manifestVersion):
            status = .requiresNewerTextify(
                manifestVersion: manifestVersion
            )
        }
    }

    private func reject(
        reason: TrustedCatalogSecurityReason,
        candidateRevision: String? = nil
    ) {
        let issue = TrustedCatalogSecurityIssue(
            reason: reason,
            candidateRevision: candidateRevision,
            highestAcceptedRevision: highestAcceptedRevision
        )
        securityIssue = issue
        _ = persist(storedState(securityIssue: issue))
        status = .securityFailure(reason)
        diagnosticOperation(issue)
    }

    private func storedState(
        securityIssue: TrustedCatalogSecurityIssue?,
        lastSuccessfulCatalogIntegrityCheckAt: Date? = nil
    ) -> TrustedCatalogStoredState {
        TrustedCatalogStoredState(
            highestAcceptedRevision: highestAcceptedRevision,
            presentedSnapshot: presentedSnapshot,
            stagedSnapshot: stagedSnapshot,
            securityIssue: securityIssue,
            lastSuccessfulCatalogIntegrityCheckAt:
                lastSuccessfulCatalogIntegrityCheckAt
                    ?? self.lastSuccessfulCatalogIntegrityCheckAt
        )
    }

    @discardableResult
    private func persist(_ state: TrustedCatalogStoredState) -> Bool {
        guard let saveOperation else {
            return true
        }
        do {
            try saveOperation(state)
            return true
        } catch {
            status = manifest == nil ? .unavailable : .offline
            return false
        }
    }

    private static func revisionDate(_ revision: String) -> Date? {
        ISO8601DateFormatter().date(from: revision)
    }

    private static func isNetworkUnavailable(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed,
             .internationalRoamingOff,
             .callIsActive:
            return true
        default:
            return false
        }
    }
}

enum ModelCatalogRefreshError: Error, Equatable {
    case networkUnavailable
    case unavailable
    case requiresNewerTextify(manifestVersion: Int)
}

enum ModelCatalogRefreshResult: Equatable {
    case authoritativeIntegrityAccepted
    case presentationAccepted
    case networkUnavailable
    case catalogUnavailable
    case rejected
    case requiresNewerTextify(manifestVersion: Int)
}

enum ModelCatalogCoordinatorStatus: Equatable {
    case checking
    case checkingForUpdates
    case trusted
    case updateAvailable
    case offline
    case securityFailure(TrustedCatalogSecurityReason)
    case requiresNewerTextify(manifestVersion: Int)
    case unavailable
}

extension TrustedCatalogSecurityReason {
    var displayName: String {
        switch self {
        case .invalidSignature:
            "invalid signature"
        case .rollback:
            "rollback revision"
        case .strictDecoding:
            "invalid catalog structure"
        case .schemaValidation:
            "invalid catalog policy"
        case .cacheCorruption:
            "invalid cached catalog"
        case .bundledCatalogInvalid:
            "invalid bundled catalog"
        }
    }
}

@Observable
final class SettingsRouter {
    var selectedPane: SettingsPane = .general
    private(set) var modelReveal: ModelCatalogRevealRequest?

    func revealModelArtifact(id: String, purpose: ModelPurpose) {
        modelReveal = ModelCatalogRevealRequest(
            artifactID: id,
            purpose: purpose
        )
        selectedPane = purpose == .voiceCleaning
            ? .voiceCleaning
            : .transcriptionModels
    }

    func dismissModelReveal() {
        modelReveal = nil
    }
}

struct ModelCatalogRevealRequest: Equatable {
    let artifactID: String
    let purpose: ModelPurpose
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case dictation
    case transcriptionModels
    case voiceCleaning
    case privacy
    case logs
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .dictation:
            return "Dictation"
        case .transcriptionModels:
            return "Transcription Models"
        case .voiceCleaning:
            return "Voice Cleaning"
        case .privacy:
            return "Privacy"
        case .logs:
            return "Logs"
        case .advanced:
            return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .dictation:
            return "mic"
        case .transcriptionModels:
            return "externaldrive"
        case .voiceCleaning:
            return "waveform.badge.minus"
        case .privacy:
            return "hand.raised"
        case .logs:
            return "doc.text.magnifyingglass"
        case .advanced:
            return "slider.horizontal.3"
        }
    }

    var modelPurpose: ModelPurpose? {
        switch self {
        case .transcriptionModels:
            return .transcription
        case .voiceCleaning:
            return .voiceCleaning
        case .general, .dictation, .privacy, .logs, .advanced:
            return nil
        }
    }
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case model
    case microphone
    case accessibility
    case triggerTest
    case completion

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .model:
            return "Model"
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
        case .triggerTest:
            return "Trigger Test"
        case .completion:
            return "Completion"
        }
    }
}

enum RecordingOverlayState: Equatable {
    case hidden
    case recording(elapsedSeconds: Int)
    case processing
    case cancelled
    case blocked(String)
}
