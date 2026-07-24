import AppKit
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
    @State private var selectedOnboardingModelID: String?
    @State private var launchAtLoginCompletionStatus: LaunchAtLoginStatus?
    @State private var didCompleteOnboarding = false
    @State private var triggerTest = OnboardingTriggerTestController()

    init(closeWindow: (@MainActor () -> Void)? = nil) {
        self.closeWindow = closeWindow
    }

    var body: some View {
        @Bindable var services = services

        HStack(spacing: 0) {
            onboardingSidebar

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(services.onboardingStep.progressTitle.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                    Text(currentStepTitle)
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.35)
                }
                .padding(.horizontal, 34)
                .padding(.top, 32)
                .padding(.bottom, 18)

                ScrollView {
                    TextifyCard(padding: 22) {
                        onboardingContent
                    }
                    .padding(.horizontal, 34)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                HStack(spacing: 12) {
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
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(primaryButtonDisabled)
                }
                .padding(.horizontal, 34)
                .frame(height: 68)
            }
        }
        .tint(TextifyVisualIdentity.voiceViolet)
        .preferredColorScheme(.dark)
        .background(TextifyVisualIdentity.windowSurface)
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: TextifyWindowMetrics.onboardingWidth, height: TextifyWindowMetrics.onboardingHeight)
        .disabled(services.startupIssue != nil)
        .overlay {
            if services.startupIssue != nil {
                PersistentStorageUnavailableView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
        .onAppear {
            launchAtLogin = services.preferences.onboardingCompleted
                ? services.preferences.launchAtLoginEnabled
                : true
        }
        .task {
            _ = await services.dictation.refreshReadiness()
            await services.modelCatalogCoordinator.refresh()
            reconcileOnboardingModelSelection()
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
        .onChange(of: services.modelCatalogCoordinator.manifest) {
            reconcileOnboardingModelSelection()
        }
    }

    private var onboardingSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                TextifyVoiceMark(state: .processing, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Textify")
                        .font(.system(size: 16, weight: .semibold))
                    Text("First-time setup")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 45)
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(OnboardingStep.productionFlow.enumerated()), id: \.element) { index, step in
                    StepRow(
                        number: index + 1,
                        title: step.title,
                        isSelected: step == services.onboardingStep,
                        isComplete: isComplete(step),
                        isPast: index < currentStepIndex
                    )
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 20)

            Label("On-device by design", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(20)
        }
        .frame(width: TextifyWindowMetrics.sidebarWidth)
        .background(TextifyVisualIdentity.sidebarSurface)
    }

    @ViewBuilder
    private var onboardingContent: some View {
        switch services.onboardingStep {
        case .welcome:
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(TextifyVisualIdentity.voiceViolet.opacity(0.12))
                    TextifyVoiceMark(state: .processing, height: 54)
                }
                .frame(height: 128)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Speak here. Type anywhere.")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Hold your trigger, speak naturally, then release. Textify turns short speech into text without sending dictation off your Mac.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("Setup takes about two minutes", systemImage: "timer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .model:
            VStack(alignment: .leading, spacing: 12) {
                ModelSummaryView(readiness: services.dictation.readiness.model)

                if onboardingModelCatalog.choices.isEmpty {
                    ContentUnavailableView {
                        Label(
                            onboardingCatalogUnavailable
                                ? ModelCatalogPurposeDestination.transcription.unavailableTitle
                                : ModelCatalogPurposeDestination.transcription.emptyTitle,
                            systemImage: "waveform.badge.exclamationmark"
                        )
                    } description: {
                        Text(
                            onboardingCatalogUnavailable
                                ? ModelCatalogPurposeDestination.transcription.unavailableDetail
                                : ModelCatalogPurposeDestination.transcription.emptyDetail
                        )
                    } actions: {
                        Button("Refresh Catalog") {
                            refreshOnboardingCatalog()
                        }
                    }
                } else {
                    Picker(
                        "Transcription Model",
                        selection: onboardingModelSelectionBinding
                    ) {
                        ForEach(onboardingModelCatalog.choices) { choice in
                            Text(choice.model.catalogDisplayName)
                                .tag(Optional(choice.id))
                        }
                    }
                    .disabled(services.modelInstallCoordinator.isActive)

                    if let selectedModel = selectedOnboardingModel {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selectedModel.model.description)
                                .foregroundStyle(.secondary)
                            Text(
                                [
                                    selectedModel.model.engineName,
                                    selectedModel.model.acceleratorName,
                                    selectedModel.model.sizeDescription,
                                ].joined(separator: " • ")
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }

                        HStack {
                            Button("Verify Installed Model") {
                                Task {
                                    _ = await services.dictation.refreshReadiness()
                                    modelMessage = modelReadinessText
                                }
                            }

                            onboardingModelActionButton(for: selectedModel)
                        }
                    }
                }

                if ProductionModelInstallConfiguration.current == nil {
                    Text("Signed model manifest is not configured in this build.")
                        .foregroundStyle(.secondary)
                }

                if let modelDownloadState = onboardingModelCatalog.transferState(
                    for: onboardingModelCatalog.selectedModelID
                ) {
                    ModelInstallProgressView(state: modelDownloadState)
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

        case .triggerTest:
            VStack(alignment: .leading, spacing: 12) {
                Picker("Dictation Trigger", selection: triggerBinding) {
                    ForEach(TextifySettings.TriggerPreference.allCases, id: \.self) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }

                HStack(spacing: 14) {
                    TextifyKeycap(title: services.preferences.trigger.displayName)
                    Text("Hold until the check appears, then release.")
                        .foregroundStyle(.secondary)
                }

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

                Text(triggerTest.displayStatusText(triggerName: services.preferences.trigger.displayName))
                    .foregroundStyle(triggerTest.result.passed ? .green : .secondary)
            }

        case .completion:
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(TextifyVisualIdentity.readyMint.opacity(0.14))
                        TextifyVoiceMark(state: .ready, height: 32)
                    }
                    .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Setup is complete")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("Textify will stay nearby in the menu bar.")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Hold \(services.preferences.trigger.displayName), speak, then release to type. If a requirement still needs attention, Textify will show it in the main window.")
                    .foregroundStyle(.secondary)

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

    private var currentStepTitle: String {
        if services.onboardingStep == .triggerTest {
            return "Test \(services.preferences.trigger.displayName)"
        }
        return services.onboardingStep.productionTitle
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

    private var onboardingModelCatalog: OnboardingModelCatalog {
        OnboardingModelCatalog(
            experience: services.modelCatalogExperience(for: .transcription),
            selectedModelID: selectedOnboardingModelID
        )
    }

    private var selectedOnboardingModel: ModelCatalogRowPresentation? {
        guard let selectedModelID = onboardingModelCatalog.selectedModelID else {
            return nil
        }
        return onboardingModelCatalog.choices.first {
            $0.id == selectedModelID
        }
    }

    private var onboardingCatalogUnavailable: Bool {
        services.modelCatalogCoordinator.manifest == nil
            && (services.modelCatalogCoordinator.errorMessage != nil
                || ProductionModelInstallConfiguration.current == nil)
    }

    private var onboardingModelSelectionBinding: Binding<String?> {
        Binding(
            get: { onboardingModelCatalog.selectedModelID },
            set: { selectedOnboardingModelID = $0 }
        )
    }

    private var triggerBinding: Binding<TextifySettings.TriggerPreference> {
        Binding(
            get: { services.preferences.trigger },
            set: { trigger in
                triggerTest.stop()
                services.setTrigger(trigger)
            }
        )
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

    @ViewBuilder
    private func onboardingModelActionButton(
        for row: ModelCatalogRowPresentation
    ) -> some View {
        switch onboardingModelCatalog.action(for: row.id) {
        case .install:
            Button("Install Model") {
                selectedOnboardingModelID = row.id
                services.modelInstallCoordinator.start(modelID: row.id)
            }
            .disabled(
                services.modelInstallCoordinator.isActive
                    || ProductionModelInstallConfiguration.current == nil
            )
        case .cancelInstall:
            Button("Cancel") {
                services.modelInstallCoordinator.cancel()
            }
        case .retryInstall:
            Button("Retry") {
                selectedOnboardingModelID = row.id
                services.modelInstallCoordinator.retry()
            }
        case .activate:
            Button("Use Model") {
                selectedOnboardingModelID = row.id
                Task {
                    let activated = await services.activateInstalledModel(row.id)
                    modelMessage = activated
                        ? row.model.activationMessage
                        : "Textify kept the previous model because this model could not be prepared."
                    _ = await services.dictation.refreshReadiness()
                }
            }
            .disabled(services.modelInstallCoordinator.isActive)
        case .active:
            Label("Active", systemImage: "checkmark.circle.fill")
                .foregroundStyle(TextifyVisualIdentity.readyMint)
        case nil:
            EmptyView()
        }
    }

    private func refreshOnboardingCatalog() {
        Task {
            await services.modelCatalogCoordinator.refresh()
            reconcileOnboardingModelSelection()
        }
    }

    private func reconcileOnboardingModelSelection() {
        selectedOnboardingModelID = onboardingModelCatalog.selectedModelID
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
        switch step {
        case .welcome:
            return currentStepIndex > 0
        case .model:
            return services.dictation.readiness.model.isReady
        case .microphone:
            return services.dictation.readiness.permissions.microphone == .granted
        case .accessibility:
            return services.dictation.readiness.permissions.accessibility == .granted
        case .triggerTest:
            return triggerTest.result.passed
        case .completion:
            return didCompleteOnboarding
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
    private let makeMonitor: @MainActor (TextifyHotkeys.TriggerPreference) -> GlobalHotkeyMonitor
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
        makeMonitor: @escaping @MainActor (TextifyHotkeys.TriggerPreference) -> GlobalHotkeyMonitor = {
            GlobalHotkeyMonitor(trigger: $0)
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
        statusText = "Listening for \(services.preferences.trigger.displayName)."

        let monitor = makeMonitor(services.configuredHotkeyTrigger)
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

    func displayStatusText(triggerName: String) -> String {
        if !isRunning,
           !result.sawDown,
           !result.sawBeginRecording,
           !result.sawUp {
            return "Start the test, then hold and release \(triggerName)."
        }
        return statusText
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
            statusText = "Dictation trigger detected."
            finish()
        } else {
            statusText = "Keep holding the dictation trigger until recording begins, then release."
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
    let number: Int
    let title: String
    let isSelected: Bool
    let isComplete: Bool
    let isPast: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(stepColor.opacity(isSelected || isComplete ? 0.16 : 0.07))
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                } else if isPast {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 9, weight: .bold))
                } else {
                    Text(String(number))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(stepColor)
            .frame(width: 24, height: 24)

            Text(title)
                .font(.system(.callout, design: .rounded, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 38)
        .background(
            isSelected ? TextifyVisualIdentity.voiceViolet.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isComplete ? "Complete" : isPast ? "Needs attention" : isSelected ? "Current step" : "Not started"
        )
    }

    private var stepColor: Color {
        if isComplete {
            return TextifyVisualIdentity.readyMint
        }
        if isSelected {
            return TextifyVisualIdentity.voiceViolet
        }
        if isPast {
            return TextifyVisualIdentity.warmWarning
        }
        return TextifyVisualIdentity.slate
    }
}

private struct ModelSummaryView: View {
    let readiness: RuntimeModelReadiness

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TextifyVisualIdentity.voiceViolet.opacity(0.13))
                Image(systemName: "externaldrive.fill")
                    .font(.title2)
                    .foregroundStyle(TextifyVisualIdentity.voiceViolet)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(ProductionModelPresentation.v1_1.displayName)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(ProductionModelPresentation.v1_1.id)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            TextifyStatusBadge(
                title: readiness.settingsModelStatus.uppercased(),
                tone: readiness.isReady ? .success : .warning
            )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionStepView: View {
    let name: String
    let status: String
    let details: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(status == "Granted" ? TextifyVisualIdentity.readyMint.opacity(0.13) : TextifyVisualIdentity.voiceViolet.opacity(0.13))
                    Image(systemName: name == "Microphone" ? "mic.fill" : "cursorarrow.rays")
                        .font(.title2)
                        .foregroundStyle(status == "Granted" ? TextifyVisualIdentity.readyMint : TextifyVisualIdentity.voiceViolet)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Text(details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                TextifyStatusBadge(
                    title: status.uppercased(),
                    tone: status == "Granted" ? .success : .warning
                )
            }

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
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
