import XCTest
@testable import Textify
import TextifyAudio
import TextifyDiagnostics
@testable import TextifyHotkeys
import TextifyInsertion
import TextifyRuntime
import TextifySettings
import TextifyTranscription

final class AppCompositionTests: XCTestCase {
    func testAppDelegateActivationPolicyFollowsShowInDockPreference() {
        var preferences = AppPreferences.defaults
        preferences.showInDock = false
        XCTAssertEqual(AppDelegate.activationPolicy(preferences: preferences), .accessory)

        preferences.showInDock = true
        XCTAssertEqual(AppDelegate.activationPolicy(preferences: preferences), .regular)
    }

    func testAppDelegateActivationPolicyFallsBackToAccessoryWhenSettingsPathFails() {
        let policy = AppDelegate.activationPolicy(
            pathFactory: { throw AppPathFixtureError.unavailable }
        )

        XCTAssertEqual(policy, .accessory)
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
        let permission = MutableInputMonitoringPermission(status: .denied)
        let services = try Self.makeServices(
            hotkeyMonitor: GlobalHotkeyMonitor(
                permissionClient: permission.client,
                eventTapClient: tap
            )
        )

        services.startRuntime()
        XCTAssertEqual(tap.startCount, 0)

        permission.status = .granted
        services.startRuntime()

        XCTAssertEqual(tap.startCount, 1)
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
        let coordinator = AppLaunchCoordinator(services: services) {
            didShowOnboarding = true
        }

        await coordinator.run()

        XCTAssertTrue(didShowOnboarding)
        XCTAssertEqual(runtimeTap.startCount, 0)
        XCTAssertFalse(services.dictation.readiness.canDictate)
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
        let coordinator = AppLaunchCoordinator(services: services) {
            didShowOnboarding = true
        }

        await coordinator.run()

        XCTAssertFalse(didShowOnboarding)
        XCTAssertEqual(runtimeTap.startCount, 1)
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
            makeMonitor: {
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
            makeMonitor: {
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
            makeMonitor: {
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
            makeMonitor: {
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
    func testProductionCompositionReportsPathStartupFailureWithoutCrashing() {
        let services = AppServices.production(
            pathFactory: { throw AppPathFixtureError.unavailable },
            launchAtLogin: FakeLaunchAtLoginManager(status: .disabled),
            launchAtLoginLocation: FixedLaunchAtLoginLocation(isSupported: true)
        )

        XCTAssertEqual(services.startupIssue, AppStartupIssue.applicationPathsUnavailable("unavailable"))
    }

    @MainActor
    private static func makeServices(
        preferences: AppPreferences = .defaults,
        hotkeyMonitor: GlobalHotkeyMonitor? = nil,
        launchAtLogin: FakeLaunchAtLoginManager? = nil,
        launchAtLoginLocation: any LaunchAtLoginLocationChecking = FixedLaunchAtLoginLocation(isSupported: true)
    ) throws -> AppServices {
        let paths = try makeTemporaryPaths()
        let settingsStore = SettingsStore(storage: .file(paths.settingsFileURL))
        settingsStore.save(preferences)
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
                models: FakeRuntimeModelResolver(),
                audio: FakeRuntimeAudioRecorder(),
                transcriber: FakeRuntimeTranscriber(),
                inserter: FakeInsertionService(),
                diagnostics: RuntimeDiagnosticsLoggerAdapter(logger: diagnosticsLogger),
                postProcessor: FakeRuntimePostProcessor(),
                clock: SuspendedRuntimeClock()
            )),
            hotkeyMonitor: hotkeyMonitor,
            launchAtLogin: launchAtLogin,
            launchAtLoginLocation: launchAtLoginLocation
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

private final class MutableInputMonitoringPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var protectedStatus: InputMonitoringPermissionStatus

    var status: InputMonitoringPermissionStatus {
        get {
            lock.lock()
            defer { lock.unlock() }
            return protectedStatus
        }
        set {
            lock.lock()
            protectedStatus = newValue
            lock.unlock()
        }
    }

    init(status: InputMonitoringPermissionStatus) {
        self.protectedStatus = status
    }

    var client: InputMonitoringPermissionClient {
        InputMonitoringPermissionClient(
            status: { self.status },
            requestAccess: { self.status }
        )
    }
}

private final class FakeCGEventTapClient: CGEventTapClient, @unchecked Sendable {
    private var handler: (@Sendable (CGEventTapMessage) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(handler: @escaping @Sendable (CGEventTapMessage) -> Void) throws -> CGEventTapHandle {
        startCount += 1
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

private actor FakeRuntimeAudioRecorder: RuntimeAudioRecording {
    func startRecording(
        microphone: MicrophoneSelection,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) async throws {}

    func finishRecording() async throws -> CanonicalAudioBuffer {
        CanonicalAudioBuffer(samples: [])
    }

    func discardRecording() async {}
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
