import Foundation
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
    let startupIssue: AppStartupIssue?

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
                  let configuration = ProductionModelInstallConfiguration.current
            else {
                throw ModelInstallCoordinatorError.storageOrConfigurationUnavailable
            }

            let manifest: ModelManifest
            do {
                manifest = try await ProductionModelManifestLoader(
                    configuration: configuration
                ).load()
            } catch {
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
            guard let self else {
                return nil
            }
            return try? ModelInstallResumableDataInspector(
                layout: ModelStorageLayout(
                    rootDirectory: self.paths.modelsDirectory
                )
            ).inspect(for: attempt)
        }
    )

    @ObservationIgnored lazy var modelCatalogCoordinator = ModelCatalogCoordinator(
        loadOperation: {
            guard let configuration = ProductionModelInstallConfiguration.current else {
                throw ModelInstallCoordinatorError.storageOrConfigurationUnavailable
            }
            return try await ProductionModelManifestLoader(
                configuration: configuration
            ).load()
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
        self.overlayPresenter = overlayPresenter ?? RecordingOverlayPresenter()
        self.waitBeforeProcessingIndicator = waitBeforeProcessingIndicator
        self.waitBeforeTerminalStatusDismissal = waitBeforeTerminalStatusDismissal
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
        onDiskBytesByModelID: [String: Int64] = [:],
        query: ModelCatalogQuery = ModelCatalogQuery()
    ) -> ModelCatalogExperience {
        var scopedQuery = query
        scopedQuery.purpose = purpose
        return ModelCatalogExperience(
            trustedManifest: modelCatalogCoordinator.manifest,
            compatibilityResolver: modelCatalogCompatibilityResolver,
            installedRecords: installedModelRecords,
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID: preferences.activeModelID,
                voiceCleaningModelID: preferences.activeVoiceCleaningModelID
            ),
            transferStatesByModelID: modelInstallCoordinator.artifactStates,
            managedReadinessByModelID: managedReadinessByModelID,
            onDiskBytesByModelID: onDiskBytesByModelID,
            query: scopedQuery
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
        makeAttemptID: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        },
        nowISO8601: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        }
    ) {
        self.queueStore = queueStore
        self.installOperation = installOperation
        self.resumableDataProvider = resumableDataProvider
        self.makeAttemptID = makeAttemptID
        self.nowISO8601 = nowISO8601

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
            revision &+= 1
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
            revision &+= 1
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
              [.paused, .waitingForNetwork, .waitingForCatalogCheck]
                .contains(attempt.state.phase)
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
            revision &+= 1
        } catch {
            return nil
        }
        processNextAttempt()
        return newAttemptID
    }

    func attempt(id: String) -> ModelInstallQueueAttempt? {
        queue.attempt(id: id)
    }

    private func processNextAttempt() {
        guard installTask == nil,
              persistenceIsAvailable,
              let attempt = queue.nextRunnableAttempt
        else {
            return
        }

        do {
            try transition(
                attemptID: attempt.id,
                phase: .checkingSpace,
                message: "Preparing model download."
            )
        } catch {
            return
        }
        activeAttemptID = attempt.id
        installTask = Task { @MainActor [weak self] in
            guard let self else {
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
            } catch {
                finish(
                    attemptID: attempt.id,
                    phase: .failed,
                    message: "Model install failed. Check your connection and try again."
                )
            }
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
            revision &+= 1
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
        revision &+= 1
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
            revision &+= 1
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
}

@MainActor
@Observable
final class ModelCatalogCoordinator {
    typealias LoadOperation = @Sendable () async throws -> ModelManifest

    private let loadOperation: LoadOperation
    private(set) var manifest: ModelManifest?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(loadOperation: @escaping LoadOperation) {
        self.loadOperation = loadOperation
    }

    func refresh() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            manifest = try await loadOperation()
            errorMessage = nil
        } catch {
            errorMessage = "The signed model catalog is unavailable. Your installed model still works offline."
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
