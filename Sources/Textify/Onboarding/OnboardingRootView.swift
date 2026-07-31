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
    @State private var microphonePermissionTask: Task<Void, Never>?
    @State private var microphonePermissionRequestID: UUID?

    init(closeWindow: (@MainActor () -> Void)? = nil) {
        self.closeWindow = closeWindow
    }

    var body: some View {
        @Bindable var services = services

        HStack(spacing: 0) {
            onboardingSidebar

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(services.onboardingStep.progressTitle.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.65)
                            .foregroundStyle(TextifyVisualIdentity.voiceViolet)

                        Text(currentStepTitle)
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .tracking(-0.25)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    OnboardingProgressRail(
                        titles: OnboardingStep.productionFlow.map { $0.title },
                        completed: OnboardingStep.productionFlow.map { isComplete($0) },
                        currentIndex: currentStepIndex
                    )
                }
                .padding(.horizontal, 34)
                .padding(.top, 27)
                .padding(.bottom, 18)

                ScrollView {
                    TextifyCard(padding: 24) {
                        onboardingContent
                    }
                    .padding(.horizontal, 34)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack(spacing: 12) {
                    Button("Back") {
                        moveBack()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(minWidth: 82)
                    .disabled(currentStepIndex == 0)

                    Spacer()

                    if services.onboardingStep == .completion {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                            .toggleStyle(.checkbox)
                            .font(.callout)
                    }

                    Button(primaryButtonTitle) {
                        primaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(minWidth: 104)
                    .keyboardShortcut(.defaultAction)
                    .disabled(primaryButtonDisabled)
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 13)
                .frame(minHeight: 66)
                .background(TextifyVisualIdentity.sidebarSurface.opacity(0.55))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(TextifyVisualIdentity.separator)
                        .frame(height: 1)
                }
            }
        }
        .tint(TextifyVisualIdentity.voiceViolet)
        .preferredColorScheme(.dark)
        .background {
            TextifyAcousticBackdrop()
        }
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
            reconcileOnboardingModelSelection()
        }
        .task(id: services.onboardingStep) {
            guard services.onboardingStep == .accessibility else {
                return
            }
            await monitorOnboardingAccessibilityPermission()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task {
                _ = await services.dictation.refreshReadiness()
                services.applicationDidBecomeActive()
            }
        }
        .onDisappear {
            cancelMicrophonePermissionRequest()
            triggerTest.stop()
        }
        .onChange(of: services.onboardingStep) { _, newStep in
            if newStep != .microphone {
                cancelMicrophonePermissionRequest()
            }
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
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TextifyVisualIdentity.voiceViolet.opacity(0.12))

                    TextifyVoiceMark(state: .processing, height: 20)
                }
                .frame(width: 38, height: 38)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TextifyVisualIdentity.voiceViolet.opacity(0.24), lineWidth: 0.75)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Textify")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .tracking(-0.15)
                    Text("First-time setup")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 34)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 4) {
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
            .padding(.horizontal, 13)

            Spacer(minLength: 20)

            Label("On-device by design", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    TextifyVisualIdentity.cardSurface.opacity(0.56),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TextifyVisualIdentity.separator, lineWidth: 0.75)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        }
        .frame(width: TextifyWindowMetrics.sidebarWidth)
        .background(TextifyVisualIdentity.sidebarSurface)
    }

    @ViewBuilder
    private var onboardingContent: some View {
        switch services.onboardingStep {
        case .welcome:
            VStack(alignment: .leading, spacing: 18) {
                WelcomeVoiceHero()

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
                    }
                } else {
                    Picker(
                        "Transcription Model",
                        selection: onboardingModelSelectionBinding
                    ) {
                        ForEach(onboardingModelCatalog.choices) { choice in
                            Text(
                                choice.model.catalogDisplayName
                                    + (choice.compatibility == .compatible
                                        ? ""
                                        : " — \(choice.compatibility.catalogTitle)")
                            )
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
                                    "Download Size: "
                                        + selectedModel.model.sizeDescription,
                                ].joined(separator: " • ")
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }

                        if let model = selectedModel.operationalModel {
                            ModelSourceLicenseButton(
                                presentation:
                                    ModelSourceLicensePresentation(model: model)
                            )
                        }

                        if let notice = onboardingModelCatalog.selectionNotice {
                            Label(notice, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(TextifyVisualIdentity.warmWarning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack {
                            Button("Verify Installed Model") {
                                Task {
                                    _ = await services.dictation.refreshReadiness()
                                    services.refreshModelStorageInventory()
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
                actionTitle:
                    services.dictation.readiness.permissions.microphone
                        == .granted
                        ? nil
                        : services.dictation.readiness.permissions.microphone
                            == .denied
                            ? "Open Microphone Settings"
                            : "Request Microphone Access",
                isDisabled: microphonePermissionRequestID != nil
            ) {
                if services.dictation.readiness.permissions.microphone
                    == .denied {
                    if SystemPrivacySettingsOpener.open(.microphone) {
                        permissionMessage =
                            "Turn on Microphone for Textify in System Settings, then return here."
                    } else {
                        permissionMessage =
                            "Open System Settings → Privacy & Security → Microphone, then turn on Textify."
                    }
                    return
                }

                guard microphonePermissionRequestID == nil else {
                    return
                }

                let requestID = UUID()
                microphonePermissionRequestID = requestID
                microphonePermissionTask = Task {
                    defer {
                        if microphonePermissionRequestID == requestID {
                            microphonePermissionRequestID = nil
                            microphonePermissionTask = nil
                        }
                    }

                    let state = await ProductionPermissionRequester.requestMicrophone()
                    guard !Task.isCancelled,
                          microphonePermissionRequestID == requestID else {
                        return
                    }

                    permissionMessage = state.permissionRequestMessage(for: "Microphone")
                    _ = await services.dictation.refreshReadiness()
                }
            }
            if services.dictation.readiness.permissions.microphone
                == .granted {
                MicrophoneInputLevelView(
                    level: services.microphoneInputPresentation.level,
                    isMonitoring:
                        services.microphoneInputPresentation.isMonitoring,
                    error:
                        services.microphoneInputPresentation.monitoringError
                )
                .padding(.top, 4)
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
                actionTitle:
                    services.dictation.readiness.permissions.accessibility
                        == .granted
                        ? nil
                        : "Allow Accessibility",
                isDisabled: false
            ) {
                ProductionPermissionRequester.requestAccessibilityPrompt()
                permissionMessage =
                    "Turn on Textify under Accessibility in System Settings."
                Task {
                    _ = await services.dictation.refreshReadiness()
                }
            }

            if services.dictation.readiness.permissions.accessibility
                != .granted {
                Divider()
                AccessibilityAppDragSource()
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
                services.modelInstallCoordinator.start(
                    modelID: row.id,
                    purpose: row.model.purpose,
                    action: .install
                )
            }
            .disabled(
                ProductionModelInstallConfiguration.current == nil
            )
        case .reinstall:
            Button("Reinstall Model") {
                selectedOnboardingModelID = row.id
                services.modelInstallCoordinator.start(
                    modelID: row.id,
                    purpose: row.model.purpose,
                    action: .reinstall
                )
            }
            .disabled(
                ProductionModelInstallConfiguration.current == nil
            )
        case .cancelInstall:
            Button("Cancel") {
                guard let attemptID = row.installState?.attemptID else {
                    return
                }
                services.modelInstallCoordinator.cancel(attemptID: attemptID)
            }
        case .retryInstall:
            Button("Retry") {
                selectedOnboardingModelID = row.id
                guard let attemptID = row.installState?.attemptID else {
                    return
                }
                services.modelInstallCoordinator.retry(attemptID: attemptID)
            }
        case .activate:
            Button("Use Model") {
                selectedOnboardingModelID = row.id
                Task {
                    let result = await services.activateInstalledModel(row.id)
                    modelMessage = result.message(for: row.model)
                    _ = await services.dictation.refreshReadiness()
                }
            }
            .disabled(
                services.modelInstallCoordinator.isActive
                    || !services.dictation.allowsModelTransactions
            )
        case .active:
            Label("Active", systemImage: "checkmark.circle.fill")
                .foregroundStyle(TextifyVisualIdentity.readyMint)
        case .unavailable:
            Button(row.isInstalled ? "Use Model" : row.model.installLabel) {}
                .disabled(true)
                .help(row.compatibility.catalogExplanation)
        case nil:
            EmptyView()
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

    private func monitorOnboardingAccessibilityPermission() async {
        var displayedState =
            services.dictation.readiness.permissions.accessibility

        while !Task.isCancelled {
            do {
                _ = try await AccessibilityPermissionMonitor.live.nextChange(
                    from: displayedState
                )
            } catch {
                return
            }

            let snapshot = await services.dictation.refreshReadiness()
            displayedState = snapshot.permissions.accessibility
            permissionMessage = displayedState.permissionRequestMessage(
                for: "Accessibility"
            )
        }
    }

    private func cancelMicrophonePermissionRequest() {
        microphonePermissionTask?.cancel()
        microphonePermissionTask = nil
        microphonePermissionRequestID = nil
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
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(stepColor.opacity(isSelected || isComplete ? 0.17 : 0.08))

                Circle()
                    .stroke(stepColor.opacity(isSelected || isComplete ? 0.48 : 0.20), lineWidth: 0.75)

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
            .frame(width: 26, height: 26)

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if isSelected {
                Circle()
                    .fill(TextifyVisualIdentity.voiceViolet)
                    .frame(width: 5, height: 5)
                    .shadow(color: TextifyVisualIdentity.voiceViolet.opacity(0.55), radius: 2)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minHeight: 42)
        .background(
            isSelected ? TextifyVisualIdentity.consoleSelection : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected
                        ? TextifyVisualIdentity.voiceViolet.opacity(0.25)
                        : Color.clear,
                    lineWidth: 0.75
                )
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(TextifyVisualIdentity.voiceViolet)
                    .frame(width: 3, height: 22)
                    .padding(.leading, 1)
            }
        }
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

private struct OnboardingProgressRail: View {
    let titles: [String]
    let completed: [Bool]
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { index in
                if index > 0 {
                    Capsule(style: .continuous)
                        .fill(connectorColor(before: index))
                        .frame(maxWidth: .infinity)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }

                ZStack {
                    Circle()
                        .fill(nodeColor(at: index).opacity(nodeOpacity(at: index)))

                    Circle()
                        .stroke(nodeColor(at: index).opacity(strokeOpacity(at: index)), lineWidth: 1)

                    if isComplete(at: index) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                    } else if index < currentIndex {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 7, weight: .bold))
                    } else {
                        Circle()
                            .fill(nodeColor(at: index))
                            .frame(width: index == currentIndex ? 5 : 3, height: index == currentIndex ? 5 : 3)
                    }
                }
                .foregroundStyle(nodeColor(at: index))
                .frame(width: 17, height: 17)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(titles[index])
                .accessibilityValue(accessibilityStatus(at: index))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func isComplete(at index: Int) -> Bool {
        completed.indices.contains(index) && completed[index]
    }

    private func connectorColor(before index: Int) -> Color {
        index <= currentIndex
            ? TextifyVisualIdentity.voiceViolet.opacity(0.72)
            : TextifyVisualIdentity.separator
    }

    private func nodeColor(at index: Int) -> Color {
        if isComplete(at: index) {
            return TextifyVisualIdentity.readyMint
        }
        if index == currentIndex {
            return TextifyVisualIdentity.voiceViolet
        }
        if index < currentIndex {
            return TextifyVisualIdentity.warmWarning
        }
        return TextifyVisualIdentity.slate
    }

    private func nodeOpacity(at index: Int) -> Double {
        index == currentIndex || isComplete(at: index) ? 0.18 : 0.08
    }

    private func strokeOpacity(at index: Int) -> Double {
        index == currentIndex || isComplete(at: index) ? 0.70 : 0.26
    }

    private func accessibilityStatus(at index: Int) -> String {
        if isComplete(at: index) {
            return "Complete"
        }
        if index == currentIndex {
            return "Current step"
        }
        if index < currentIndex {
            return "Needs attention"
        }
        return "Not started"
    }
}

private struct WelcomeVoiceHero: View {
    private let signalHeights: [CGFloat] = [
        12, 18, 27, 17, 36, 24, 42, 20, 31, 16, 26, 13, 20, 10, 15,
        11, 18, 29, 16, 36, 22, 43, 25, 34, 18, 27, 15, 21, 12
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TextifyVisualIdentity.raisedSurface.opacity(0.72),
                            TextifyVisualIdentity.cardSurface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 25) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(TextifyVisualIdentity.separator.opacity(0.46))
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 18)
            .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 5) {
                ForEach(signalHeights.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            index.isMultiple(of: 4)
                                ? TextifyVisualIdentity.voiceViolet.opacity(0.30)
                                : TextifyVisualIdentity.slate.opacity(0.20)
                        )
                        .frame(width: 3, height: signalHeights[index])
                }
            }
            .accessibilityHidden(true)

            ZStack {
                Circle()
                    .fill(TextifyVisualIdentity.windowSurface.opacity(0.94))
                    .shadow(color: TextifyVisualIdentity.voiceViolet.opacity(0.22), radius: 18)

                Circle()
                    .stroke(TextifyVisualIdentity.voiceViolet.opacity(0.30), lineWidth: 1)

                TextifyVoiceMark(state: .processing, height: 54, animated: true)
            }
            .frame(width: 92, height: 92)
        }
        .frame(height: 134)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TextifyVisualIdentity.separator, lineWidth: 0.8)
        }
        .accessibilityHidden(true)
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
    let actionTitle: String?
    let isDisabled: Bool
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

            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .disabled(isDisabled)
            }
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
