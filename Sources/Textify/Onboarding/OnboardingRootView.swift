import Observation
import SwiftUI
import TextifyHotkeys
import TextifyModels
import TextifyRuntime
import TextifySettings

struct OnboardingRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    private let closeWindow: (@MainActor () -> Void)?

    @State private var launchAtLogin = true
    @State private var permissionMessage: String?
    @State private var modelMessage: String?
    @State private var launchAtLoginCompletionStatus: LaunchAtLoginStatus?
    @State private var didCompleteOnboarding = false
    @State private var triggerTest = OnboardingTriggerTestController()

    init(closeWindow: (@MainActor () -> Void)? = nil) {
        self.closeWindow = closeWindow
    }

    var body: some View {
        @Bindable var services = services

        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Textify Setup")
                    .font(.largeTitle.bold())
                Text(services.onboardingStep.progressTitle)
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value: Double(currentStepIndex + 1),
                total: Double(OnboardingStep.productionFlow.count)
            )

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(OnboardingStep.productionFlow) { step in
                        StepRow(
                            title: step.title,
                            isSelected: step == services.onboardingStep,
                            isComplete: isComplete(step)
                        )
                    }
                }
                .frame(width: 170, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    Text(services.onboardingStep.productionTitle)
                        .font(.title2.bold())

                    onboardingContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Back") {
                    moveBack()
                }
                .disabled(currentStepIndex == 0)

                Spacer()

                if services.onboardingStep == .completion {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .toggleStyle(.checkbox)
                }

                Button(primaryButtonTitle) {
                    primaryAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(primaryButtonDisabled)
            }
        }
        .padding(28)
        .frame(width: 680, height: 470)
        .onAppear {
            launchAtLogin = services.preferences.onboardingCompleted
                ? services.preferences.launchAtLoginEnabled
                : true
            Task {
                _ = await services.dictation.refreshReadiness()
            }
        }
        .onDisappear {
            triggerTest.stop()
        }
        .onChange(of: services.onboardingStep) { _, newStep in
            if newStep != .triggerTest {
                triggerTest.stop()
            }
            permissionMessage = nil
            modelMessage = nil
            if newStep != .completion {
                launchAtLoginCompletionStatus = nil
                didCompleteOnboarding = false
            }
        }
    }

    @ViewBuilder
    private var onboardingContent: some View {
        switch services.onboardingStep {
        case .welcome:
            VStack(alignment: .leading, spacing: 10) {
                Text("Textify turns a held Right Command key into short local dictation.")
                Text("Setup checks the model, macOS permissions, and the trigger before the menu bar utility is ready.")
            }
            .foregroundStyle(.secondary)

        case .model:
            VStack(alignment: .leading, spacing: 12) {
                ModelSummaryView(readiness: services.dictation.readiness.model)

                HStack {
                    Button("Verify Installed Model") {
                        Task {
                            _ = await services.dictation.refreshReadiness()
                            modelMessage = modelReadinessText
                        }
                    }

                    Button("Install Model") {
                        Task {
                            await installModel()
                        }
                    }
                    .disabled(ProductionModelInstallConfiguration.current == nil)
                }

                if ProductionModelInstallConfiguration.current == nil {
                    Text("Signed model manifest is not configured in this build.")
                        .foregroundStyle(.secondary)
                }

                if let modelMessage {
                    Text(modelMessage)
                        .foregroundStyle(.secondary)
                }
            }

        case .microphone:
            PermissionStepView(
                name: "Microphone",
                status: services.dictation.readiness.permissions.microphone.settingsStatusLabel,
                details: "Required to capture speech only while the trigger is held.",
                actionTitle: "Request Microphone Access"
            ) {
                Task {
                    let state = await ProductionPermissionRequester.requestMicrophone()
                    permissionMessage = state.permissionRequestMessage(for: "Microphone")
                    _ = await services.dictation.refreshReadiness()
                }
            }
            if let permissionMessage {
                Text(permissionMessage)
                    .foregroundStyle(.secondary)
            }

        case .accessibility:
            PermissionStepView(
                name: "Accessibility",
                status: services.dictation.readiness.permissions.accessibility.settingsStatusLabel,
                details: "Required so Textify can type into the active app.",
                actionTitle: "Open Accessibility Prompt"
            ) {
                ProductionPermissionRequester.requestAccessibilityPrompt()
                Task {
                    _ = await services.dictation.refreshReadiness()
                    permissionMessage = services.dictation.readiness.permissions.accessibility
                        .permissionRequestMessage(for: "Accessibility")
                }
            }
            if let permissionMessage {
                Text(permissionMessage)
                    .foregroundStyle(.secondary)
            }

        case .inputMonitoring:
            PermissionStepView(
                name: "Input Monitoring",
                status: services.dictation.readiness.permissions.inputMonitoring.settingsStatusLabel,
                details: "Required to detect the Right Command trigger globally.",
                actionTitle: "Request Input Monitoring"
            ) {
                Task {
                    let state = await ProductionPermissionRequester.requestInputMonitoring()
                    permissionMessage = state.permissionRequestMessage(for: "Input Monitoring")
                    _ = await services.dictation.refreshReadiness()
                }
            }
            if let permissionMessage {
                Text(permissionMessage)
                    .foregroundStyle(.secondary)
            }

        case .triggerTest:
            VStack(alignment: .leading, spacing: 12) {
                Text("Hold Right Command until the check appears, then release.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button(triggerTest.isRunning ? "Restart Test" : "Start Test") {
                        triggerTest.start(suspending: services)
                    }

                    Button("Stop Test") {
                        triggerTest.stop()
                    }
                    .disabled(!triggerTest.isRunning)
                }

                TriggerTestResultView(result: triggerTest.result)

                Text(triggerTest.statusText)
                    .foregroundStyle(triggerTest.result.passed ? .green : .secondary)
            }

        case .completion:
            VStack(alignment: .leading, spacing: 10) {
                Text("Textify will stay in the menu bar and listen for Right Command.")
                Text("Dictation starts only after setup is complete and readiness has no blockers.")

                if let message = OnboardingLaunchAtLoginNotice.message(for: launchAtLoginCompletionStatus) {
                    Text(message)
                        .foregroundStyle(.secondary)
                }

                if OnboardingLaunchAtLoginNotice.showsLoginItemsAction(for: launchAtLoginCompletionStatus) {
                    Button("Open Login Items Settings") {
                        LoginItemsSettingsOpener.open()
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private var primaryButtonTitle: String {
        services.onboardingStep == .completion ? "Done" : "Continue"
    }

    private var primaryButtonDisabled: Bool {
        services.onboardingStep == .triggerTest && !triggerTest.result.passed
    }

    private var currentStepIndex: Int {
        OnboardingStep.productionFlow.firstIndex(of: services.onboardingStep) ?? 0
    }

    private var modelReadinessText: String {
        services.dictation.readiness.model.settingsModelStatus
    }

    private func primaryAction() {
        if services.onboardingStep == .completion {
            Task {
                await completeOnboarding()
            }
            return
        }

        moveForward()
    }

    private func moveForward() {
        let nextIndex = currentStepIndex + 1
        guard nextIndex < OnboardingStep.productionFlow.count else {
            return
        }
        services.onboardingStep = OnboardingStep.productionFlow[nextIndex]
    }

    private func moveBack() {
        let previousIndex = currentStepIndex - 1
        guard previousIndex >= 0 else {
            return
        }
        services.onboardingStep = OnboardingStep.productionFlow[previousIndex]
    }

    private func isComplete(_ step: OnboardingStep) -> Bool {
        guard let index = OnboardingStep.productionFlow.firstIndex(of: step) else {
            return false
        }
        return index < currentStepIndex
    }

    private func installModel() async {
        guard let configuration = ProductionModelInstallConfiguration.current else {
            modelMessage = "Signed model manifest is not configured in this build."
            return
        }

        do {
            let verifier = ManifestVerifier(trustedKeys: configuration.trustedKeys)
            let downloader = ModelDownloader(manifestVerifier: verifier)
            let manifest = try await downloader.downloadManifest(
                manifestURL: configuration.manifestURL,
                signatureURL: configuration.signatureURL
            )
            let installer = ModelInstaller(
                layout: ModelStorageLayout(rootDirectory: services.paths.modelsDirectory),
                transport: URLSessionDownloadTransport()
            )
            _ = try await installer.install(
                modelID: ProductionModelPolicy.requiredModelID,
                from: manifest
            )
            services.preferences.activeModelID = ProductionModelPolicy.requiredModelID
            services.savePreferences()
            _ = await services.dictation.refreshReadiness()
            modelMessage = "Model installed and verified."
        } catch {
            modelMessage = "Model install failed: \(String(describing: error))"
        }
    }

    private func completeOnboarding() async {
        guard !didCompleteOnboarding else {
            close()
            return
        }

        let status = await services.completeOnboarding(launchAtLogin: launchAtLogin)
        didCompleteOnboarding = true
        launchAtLoginCompletionStatus = status
        guard OnboardingLaunchAtLoginNotice.message(for: status) == nil else {
            return
        }

        close()
    }

    @MainActor
    private func close() {
        if let closeWindow {
            closeWindow()
        } else {
            dismiss()
        }
    }
}

enum OnboardingCompletion {
    static func apply(to preferences: inout AppPreferences, launchAtLogin: Bool) {
        preferences.launchAtLoginEnabled = launchAtLogin
        preferences.onboardingCompleted = true
    }
}

enum OnboardingLaunchAtLoginNotice {
    static func message(for status: LaunchAtLoginStatus?) -> String? {
        guard let status else {
            return nil
        }

        switch status {
        case .requiresApproval:
            return "macOS needs approval before Textify can open at login."
        case .unsupportedLocation:
            return "Move Textify to Applications to use Launch at Login."
        case .failed:
            return "Textify could not update Launch at Login."
        case .enabled, .disabled, .unavailable:
            return nil
        }
    }

    static func showsLoginItemsAction(for status: LaunchAtLoginStatus?) -> Bool {
        status == .requiresApproval
    }
}

extension OnboardingStep {
    static let productionFlow: [OnboardingStep] = [
        .welcome,
        .model,
        .microphone,
        .accessibility,
        .inputMonitoring,
        .triggerTest,
        .completion
    ]

    var productionTitle: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .model:
            return "Install Textify's Model"
        case .microphone:
            return "Allow Microphone"
        case .accessibility:
            return "Allow Accessibility"
        case .inputMonitoring:
            return "Allow Input Monitoring"
        case .triggerTest:
            return "Test Right Command"
        case .completion:
            return "Finish Setup"
        }
    }

    var progressTitle: String {
        "Step \((Self.productionFlow.firstIndex(of: self) ?? 0) + 1) of \(Self.productionFlow.count)"
    }
}

@MainActor
@Observable
final class OnboardingTriggerTestController: @unchecked Sendable {
    private let makeMonitor: @MainActor () -> GlobalHotkeyMonitor
    private let activationDelayMilliseconds: Int
    private let sleepMilliseconds: @Sendable (Int) async -> Void
    private var monitor: GlobalHotkeyMonitor?
    private var session: TriggerTestSession
    private weak var suspendedServices: AppServices?
    private var shouldResumeRuntime = false
    private var activationTask: Task<Void, Never>?
    private var lastTriggerDownTimestamp: Int?

    private(set) var result = TriggerTestSessionResult(
        sawDown: false,
        sawBeginRecording: false,
        sawUp: false
    )
    private(set) var statusText = "Start the test, then hold and release Right Command."
    private(set) var isRunning = false

    init(
        activationDelayMilliseconds: Int = 250,
        sleepMilliseconds: @escaping @Sendable (Int) async -> Void = { milliseconds in
            guard milliseconds > 0 else {
                return
            }
            let (nanoseconds, overflow) = UInt64(milliseconds).multipliedReportingOverflow(by: 1_000_000)
            try? await Task.sleep(nanoseconds: overflow ? UInt64.max : nanoseconds)
        },
        makeMonitor: @escaping @MainActor () -> GlobalHotkeyMonitor = {
            GlobalHotkeyMonitor(trigger: .rightCommand)
        }
    ) {
        self.activationDelayMilliseconds = activationDelayMilliseconds
        self.sleepMilliseconds = sleepMilliseconds
        self.makeMonitor = makeMonitor
        self.session = TriggerTestSession(activationDelayMs: activationDelayMilliseconds)
    }

    func start(suspending services: AppServices) {
        stop()
        suspendedServices = services
        shouldResumeRuntime = services.preferences.onboardingCompleted
        services.stopRuntime()
        activationTask?.cancel()
        activationTask = nil
        lastTriggerDownTimestamp = nil
        session = TriggerTestSession(activationDelayMs: activationDelayMilliseconds)
        result = TriggerTestSessionResult(
            sawDown: false,
            sawBeginRecording: false,
            sawUp: false
        )
        statusText = "Listening for Right Command."

        let monitor = makeMonitor()
        self.monitor = monitor
        isRunning = true

        let startResult = monitor.start(
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    await self?.ingest(event)
                }
            },
            onFailure: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.statusText = error.triggerTestStatusText
                    self?.finish()
                }
            }
        )

        if case let .failure(error) = startResult {
            statusText = error.triggerTestStatusText
            stop()
        }
    }

    func stop() {
        finish()
    }

    private func finish() {
        activationTask?.cancel()
        activationTask = nil
        lastTriggerDownTimestamp = nil
        monitor?.stop()
        monitor = nil
        isRunning = false
        if shouldResumeRuntime, let suspendedServices {
            suspendedServices.startRuntime()
        }
        suspendedServices = nil
        shouldResumeRuntime = false
    }

    private func ingest(_ event: TriggerEvent) async {
        switch event {
        case .triggerDown(let timestampMs):
            lastTriggerDownTimestamp = timestampMs
            scheduleActivationTimer(from: timestampMs)
        case .triggerUp(let timestampMs):
            if let lastTriggerDownTimestamp,
               timestampMs >= lastTriggerDownTimestamp + activationDelayMilliseconds {
                _ = await session.ingest(.timerFired(timestampMs: lastTriggerDownTimestamp + activationDelayMilliseconds))
            }
        case .escapeKeyDown, .nonTriggerKeyDown:
            activationTask?.cancel()
            activationTask = nil
        case .timerFired, .speechDetected:
            break
        }

        result = await session.ingest(event)
        if result.passed {
            statusText = "Right Command detected."
            finish()
        } else {
            statusText = "Keep holding Right Command until recording begins, then release."
        }
    }

    private func scheduleActivationTimer(from triggerDownTimestampMs: Int) {
        activationTask?.cancel()
        activationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await sleepMilliseconds(activationDelayMilliseconds)
            guard !Task.isCancelled else {
                return
            }
            await ingest(.timerFired(timestampMs: triggerDownTimestampMs + activationDelayMilliseconds))
        }
    }
}

private struct StepRow: View {
    let title: String
    let isSelected: Bool
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected || isComplete ? Color.accentColor : Color.secondary)
            Text(title)
                .font(.callout)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
    }
}

private struct ModelSummaryView: View {
    let readiness: RuntimeModelReadiness

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Model", value: ProductionModelPresentation.v1_1.displayName)
            LabeledContent("Identifier", value: ProductionModelPresentation.v1_1.id)
            LabeledContent("Status", value: readiness.settingsModelStatus)
        }
    }
}

private struct PermissionStepView: View {
    let name: String
    let status: String
    let details: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(name, value: status)
            Text(details)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: action)
        }
    }
}

private struct TriggerTestResultView: View {
    let result: TriggerTestSessionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TriggerCheckRow(title: "Key down", isComplete: result.sawDown)
            TriggerCheckRow(title: "Recording started", isComplete: result.sawBeginRecording)
            TriggerCheckRow(title: "Key released", isComplete: result.sawUp)
        }
    }
}

private struct TriggerCheckRow: View {
    let title: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)
            Text(title)
        }
    }
}

extension HotkeyMonitorError {
    var triggerTestStatusText: String {
        switch self {
        case .inputMonitoringPermissionRequired:
            return "Input Monitoring permission is required."
        case .inputMonitoringDenied:
            return "Input Monitoring permission is denied."
        case .eventTapDisabledByUserInput:
            return "macOS disabled the trigger monitor. Start the test again."
        case .eventTapCreationFailed, .runLoopSourceCreationFailed:
            return "Textify could not start the trigger monitor."
        case .alreadyRunning:
            return "The trigger monitor is already running."
        case .notRunning:
            return "The trigger monitor is not running."
        }
    }
}
