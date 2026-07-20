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
    let startupIssue: AppStartupIssue?

    private var installedModelsStore: InstalledModelsStore

    @ObservationIgnored lazy var modelInstallCoordinator = ModelInstallCoordinator(
        installOperation: { [weak self] modelID, onStateChange in
            guard let self,
                  self.startupIssue == nil,
                  let configuration = ProductionModelInstallConfiguration.current
            else {
                throw ModelInstallCoordinatorError.storageOrConfigurationUnavailable
            }

            let manifest = try await ProductionModelManifestLoader(
                configuration: configuration
            ).load()
            let installer = ModelInstaller(
                layout: ModelStorageLayout(rootDirectory: self.paths.modelsDirectory),
                transport: URLSessionDownloadTransport(),
                currentAppVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "1.1.0"
            )
            _ = try await installer.install(
                modelID: modelID,
                from: manifest
            ) { state in
                guard state.phase != .installed else {
                    return
                }
                onStateChange(state)
            }
            self.refreshInstalledModels()
            try Task.checkCancellation()
            onStateChange(DownloadState(
                modelID: modelID,
                phase: .installing,
                message: "Preparing model for dictation."
            ))
            let previousModelID = self.preferences.activeModelID
            let previousLanguage = self.preferences.transcriptionLanguage
            self.preferences.activeModelID = modelID
            if !self.availableTranscriptionLanguages.contains(self.preferences.transcriptionLanguage) {
                self.preferences.transcriptionLanguage = self.availableTranscriptionLanguages.first ?? .english
            }
            self.savePreferences()
            let snapshot = await self.dictation.prepareActiveModelIfAvailable()
            try Task.checkCancellation()
            guard case .ready(modelID: modelID) = snapshot.model else {
                self.preferences.activeModelID = previousModelID
                self.preferences.transcriptionLanguage = previousLanguage
                self.savePreferences()
                _ = await self.dictation.prepareActiveModelIfAvailable()
                throw ModelInstallCoordinatorError.modelPreparationFailed
            }
            let installedModel = manifest.models.first { $0.id == modelID }
            onStateChange(DownloadState(
                modelID: modelID,
                phase: .installed,
                bytesDownloaded: installedModel?.sizeBytes ?? 0,
                totalBytes: installedModel?.sizeBytes ?? 0,
                message: "Model installed and ready."
            ))
        }
    )

    @ObservationIgnored lazy var modelCatalogCoordinator = ModelCatalogCoordinator(
        loadOperation: {
            guard let configuration = ProductionModelInstallConfiguration.current else {
                throw ModelInstallCoordinatorError.storageOrConfigurationUnavailable
            }
            return try await ProductionModelManifestLoader(
                configuration: configuration
            ).load().models
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
        overlayPresenter: (any RecordingOverlayPresenting)? = nil,
        waitBeforeProcessingIndicator: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(nanoseconds: 450_000_000)
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
        self.overlayPresenter = overlayPresenter ?? RecordingOverlayPresenter()
        self.waitBeforeProcessingIndicator = waitBeforeProcessingIndicator
        self.waitBeforeTerminalStatusDismissal = waitBeforeTerminalStatusDismissal
        self.startupIssue = startupIssue
        self.runtimeIssue = startupIssue == nil ? nil : .persistentStorageUnavailable
        self.installedModelsStore = Self.loadInstalledModelsStore(paths: paths)
        self.preferences = settingsStore.load()
        self.launchAtLoginStatus = launchAtLoginLocation.isSupported ? launchAtLogin.status() : .unsupportedLocation
        updateOverlay()
        observeDictationStatus()
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

    var installedModels: [ModelEntry] {
        installedModelsStore.records.map(\.model)
    }

    func refreshInstalledModels() {
        installedModelsStore = Self.loadInstalledModelsStore(paths: paths)
    }

    var availableTranscriptionLanguages: [TranscriptionLanguage] {
        guard let activeModelID = preferences.activeModelID,
              let model = installedModel(activeModelID)?.model
        else {
            return [.english]
        }
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
    func activateInstalledModel(_ modelID: String) async -> Bool {
        guard isModelInstalled(modelID) else {
            return false
        }
        let previousModelID = preferences.activeModelID
        let previousLanguage = preferences.transcriptionLanguage
        preferences.activeModelID = modelID
        if !availableTranscriptionLanguages.contains(preferences.transcriptionLanguage) {
            preferences.transcriptionLanguage = availableTranscriptionLanguages.first ?? .english
        }
        savePreferences()
        let snapshot = await dictation.prepareActiveModelIfAvailable()
        guard case .ready(modelID: modelID) = snapshot.model else {
            preferences.activeModelID = previousModelID
            preferences.transcriptionLanguage = previousLanguage
            savePreferences()
            _ = await dictation.prepareActiveModelIfAvailable()
            return false
        }
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
        guard await activateInstalledModel(record.model.id) else {
            try? importer.removeImportedModel(modelID: record.model.id)
            refreshInstalledModels()
            throw ModelInstallCoordinatorError.modelPreparationFailed
        }
        return record.model
    }

    func removeInstalledModel(_ modelID: String) async throws {
        guard preferences.activeModelID != modelID else {
            throw AppModelRemovalError.activeModelMustBeSwitchedFirst
        }
        let manager = InstalledModelManager(
            layout: ModelStorageLayout(rootDirectory: paths.modelsDirectory)
        )
        _ = try await Task.detached(priority: .utility) {
            try manager.remove(modelID: modelID)
        }.value
        refreshInstalledModels()
        _ = await dictation.refreshReadiness()
    }

    private func installedModel(_ modelID: String) -> InstalledModelRecord? {
        installedModelsStore.record(forModelID: modelID)
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
}

enum AppModelRemovalError: Error, LocalizedError {
    case activeModelMustBeSwitchedFirst

    var errorDescription: String? {
        switch self {
        case .activeModelMustBeSwitchedFirst:
            return "Select another installed model before deleting the active model."
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
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var activeModelID: String?

    private(set) var state: DownloadState?

    var isActive: Bool {
        installTask != nil
    }

    init(installOperation: @escaping InstallOperation) {
        self.installOperation = installOperation
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

    func start(modelID: String = ProductionModelPolicy.requiredModelID) {
        guard installTask == nil else {
            return
        }

        activeModelID = modelID
        state = DownloadState(
            modelID: modelID,
            phase: .checkingSpace,
            message: "Preparing model download."
        )
        installTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { installTask = nil }

            do {
                try await installOperation(modelID) { [weak self] state in
                    Task { @MainActor in
                        self?.state = state
                    }
                }
            } catch is CancellationError {
                state = DownloadState(
                    modelID: modelID,
                    phase: .cancelled,
                    message: "Download cancelled."
                )
            } catch {
                state = DownloadState(
                    modelID: modelID,
                    phase: .failed,
                    message: "Model install failed. Check your connection and try again."
                )
            }
        }
    }

    func cancel() {
        installTask?.cancel()
    }

    func retry() {
        start(modelID: activeModelID ?? ProductionModelPolicy.requiredModelID)
    }
}

@MainActor
@Observable
final class ModelCatalogCoordinator {
    typealias LoadOperation = @Sendable () async throws -> [ModelEntry]

    private let loadOperation: LoadOperation
    private(set) var models: [ModelEntry] = []
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
            models = try await loadOperation()
            errorMessage = nil
        } catch {
            errorMessage = "The signed model catalog is unavailable. Your installed model still works offline."
        }
    }
}

@Observable
final class SettingsRouter {
    var selectedPane: SettingsPane = .general
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case dictation
    case models
    case privacy
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .dictation:
            return "Dictation"
        case .models:
            return "Models"
        case .privacy:
            return "Privacy"
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
        case .models:
            return "externaldrive"
        case .privacy:
            return "hand.raised"
        case .advanced:
            return "slider.horizontal.3"
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
