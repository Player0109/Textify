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

    var preferences: AppPreferences
    var launchAtLoginStatus: LaunchAtLoginStatus
    var launchAtLoginOperationError: String?
    var launchAtLoginFailedRequestedEnabled: Bool?
    var onboardingStep = OnboardingStep.welcome
    var overlayState = RecordingOverlayState.hidden

    @ObservationIgnored private var runtimeStarted = false

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
        startupIssue: AppStartupIssue? = nil
    ) {
        self.paths = paths
        self.settingsStore = settingsStore
        self.diagnosticsLogger = diagnosticsLogger
        self.dictation = dictation
        self.hotkeyMonitor = hotkeyMonitor
        self.launchAtLogin = launchAtLogin
        self.launchAtLoginLocation = launchAtLoginLocation
        self.startupIssue = startupIssue
        self.preferences = settingsStore.load()
        self.launchAtLoginStatus = launchAtLoginLocation.isSupported ? launchAtLogin.status() : .unsupportedLocation
    }

    func startRuntime() {
        guard !runtimeStarted || !hotkeyMonitor.isRunning else {
            return
        }

        let dictation = dictation

        Task { @MainActor in
            await dictation.refreshReadiness()
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
                    await dictation.refreshReadiness()
                }
            }
        )
        if case .success = result {
            runtimeStarted = true
        }
    }

    func stopRuntime() {
        hotkeyMonitor.stop()
        runtimeStarted = false
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
        case .inputMonitoringPermissionRequired,
             .inputMonitoringDenied,
             .eventTapDisabledByUserInput,
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
        let preferences = settingsStore.load()
        let trigger = hotkeyTrigger(for: preferences.trigger)
        let dependencies = RuntimeDependencies(
            settings: RuntimeSettingsStoreAdapter(storage: .file(paths.settingsFileURL)),
            permissions: SystemRuntimePermissionAdapter(),
            models: RuntimeModelResolverAdapter(layout: modelLayout),
            audio: RuntimeAudioRecorderAdapter(),
            transcriber: WhisperRuntimeTranscribingAdapter(runtime: whisperRuntime),
            inserter: PasteInsertionService(
                pasteboard: SystemPasteboardClient(),
                eventPoster: SystemEventPoster(),
                accessibility: .live,
                targetChecker: SystemInsertionTargetChecker()
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
    case inputMonitoring
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
        case .inputMonitoring:
            return "Input Monitoring"
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
