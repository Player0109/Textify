import AppKit
import ApplicationServices
import SwiftUI
import TextifyAudio
import TextifyDiagnostics
import TextifyHotkeys
import TextifyModels
import TextifyRuntime
import TextifySettings
import UniformTypeIdentifiers

struct SettingsRootView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var router = services.settingsRouter

        Group {
            if let startupIssue = services.startupIssue {
                PersistentStorageUnavailableView(
                    issue: startupIssue.runtimeIssue
                )
            } else {
                HStack(spacing: 0) {
                    SettingsSidebar(selection: $router.selectedPane)

                    Rectangle()
                        .fill(TextifyVisualIdentity.separator)
                        .frame(width: 1)

                    paneView(for: router.selectedPane)
                }
            }
        }
        .tint(TextifyVisualIdentity.voiceViolet)
        .preferredColorScheme(.dark)
        .background(TextifyVisualIdentity.windowSurface)
        .ignoresSafeArea(.container, edges: .top)
        .frame(
            minWidth: TextifyWindowMetrics.mainMinimumWidth,
            idealWidth: TextifyWindowMetrics.mainWidth,
            minHeight: TextifyWindowMetrics.mainMinimumHeight,
            idealHeight: TextifyWindowMetrics.mainHeight
        )
        .onAppear {
            if let purpose = router.selectedPane.modelPurpose {
                ModelCatalogPerformanceTrace.event("navigation-start")
                services.modelCatalogCoordinator.destinationOpened(purpose)
            }
            services.settingsPaneDidChange()
        }
        .onChange(of: router.selectedPane) { previousPane, nextPane in
            if nextPane.modelPurpose != nil {
                ModelCatalogPerformanceTrace.event("navigation-start")
            }
            services.modelCatalogCoordinator.destinationChanged(
                from: previousPane.modelPurpose,
                to: nextPane.modelPurpose
            )
            services.settingsPaneDidChange()
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
            if let purpose = router.selectedPane.modelPurpose {
                services.modelCatalogCoordinator.destinationClosed(purpose)
            }
        }
    }

    @ViewBuilder
    private func paneView(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsPane()
        case .dictation:
            DictationSettingsPane()
        case .transcriptionModels:
            ModelsSettingsPane(
                destination: .transcription,
                featureModel: services.modelCatalogFeature(
                    for: .transcription
                )
            )
        case .voiceCleaning:
            ModelsSettingsPane(
                destination: .voiceCleaning,
                featureModel: services.modelCatalogFeature(
                    for: .voiceCleaning
                )
            )
        case .privacy:
            PrivacySettingsPane()
        case .logs:
            LogsSettingsPane()
        case .advanced:
            AdvancedSettingsPane()
        }
    }
}

private struct SettingsSidebar: View {
    @Environment(AppServices.self) private var services
    @Binding var selection: SettingsPane
    @State private var hoveredPane: SettingsPane?

    private let setupPanes: [SettingsPane] = [
        .general,
        .dictation,
        .transcriptionModels,
        .voiceCleaning,
    ]
    private let systemPanes: [SettingsPane] = [
        .privacy,
        .logs,
        .advanced,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandLockup
            .padding(.horizontal, 24)
            .padding(.top, 45)
            .padding(.bottom, 24)

            sidebarGroup("SETUP", panes: setupPanes)

            sidebarGroup("SYSTEM", panes: systemPanes)
                .padding(.top, 17)

            Spacer(minLength: 20)

            sidebarStatus
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .frame(width: TextifyWindowMetrics.sidebarWidth)
        .background {
            ZStack {
                TextifyVisualIdentity.sidebarSurface
                LinearGradient(
                    colors: [
                        TextifyVisualIdentity.voiceViolet.opacity(0.075),
                        .clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
        }
    }

    private var brandLockup: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                TextifyVisualIdentity.voiceViolet.opacity(0.24),
                                TextifyVisualIdentity.voiceViolet.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                TextifyVoiceMark(state: .processing, height: 20)
            }
            .frame(width: 36, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        TextifyVisualIdentity.voiceViolet.opacity(0.22),
                        lineWidth: 1
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Textify")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("ON-DEVICE DICTATION")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sidebarGroup(
        _ title: String,
        panes: [SettingsPane]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.leading, 27)

            VStack(spacing: 3) {
                ForEach(panes) { pane in
                    sidebarButton(for: pane)
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private func sidebarButton(for pane: SettingsPane) -> some View {
        let isSelected = selection == pane
        let isHovered = hoveredPane == pane

        return Button {
            selection = pane
        } label: {
            HStack(spacing: 10) {
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? TextifyVisualIdentity.voiceViolet
                            : Color.clear
                    )
                    .frame(width: 3, height: 18)

                Image(systemName: pane.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        isSelected
                            ? TextifyVisualIdentity.voiceViolet
                            : Color.white.opacity(0.58)
                    )
                    .frame(width: 18)

                Text(pane.sidebarTitle)
                    .font(
                        .system(
                            size: 13,
                            weight: isSelected ? .semibold : .regular
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .foregroundStyle(
                isSelected
                    ? Color.white
                    : Color.white.opacity(isHovered ? 0.82 : 0.62)
            )
            .padding(.horizontal, 8)
            .frame(minHeight: 38)
            .background(
                isSelected
                    ? TextifyVisualIdentity.consoleSelection
                    : isHovered
                        ? Color.white.opacity(0.035)
                        : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        isSelected
                            ? TextifyVisualIdentity.voiceViolet.opacity(0.16)
                            : Color.clear,
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                hoveredPane = pane
            } else if hoveredPane == pane {
                hoveredPane = nil
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var sidebarStatus: some View {
        let canDictate = services.dictation.readiness.canDictate
        let statusColor = canDictate
            ? TextifyVisualIdentity.readyMint
            : TextifyVisualIdentity.warmWarning

        if canDictate {
            sidebarStatusContent(
                canDictate: true,
                statusColor: statusColor,
                showsDisclosure: false
            )
        } else {
            Button {
                selection = SettingsSetupNavigation.destination(
                    for: services.dictation.readiness
                )
            } label: {
                sidebarStatusContent(
                    canDictate: false,
                    statusColor: statusColor,
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)
            .help("Open the next setup requirement")
            .accessibilityHint("Opens the next setup requirement.")
        }
    }

    private func sidebarStatusContent(
        canDictate: Bool,
        statusColor: Color,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(TextifyReadinessPresentation.title(canDictate: canDictate))
                    .font(.system(size: 13, weight: .medium))
                Text(
                    canDictate
                        ? services.preferences.trigger.displayName
                        : SettingsSetupNavigation.detail(
                            for: services.dictation.readiness
                        )
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TextifyVisualIdentity.cardSurface.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

enum SettingsSetupNavigation {
    static func destination(
        for readiness: ReadinessSnapshot
    ) -> SettingsPane {
        if readiness.permissions.microphone != .granted
            || readiness.permissions.accessibility != .granted {
            return .privacy
        }
        return .transcriptionModels
    }

    static func detail(for readiness: ReadinessSnapshot) -> String {
        guard destination(for: readiness) != .privacy else {
            return "Grant required permissions"
        }

        switch readiness.model {
        case .noActiveModel:
            return "Choose a transcription model"
        case .missing, .failed:
            return "Repair the active model"
        case .loading, .warming:
            return "Model setup is in progress"
        case .revoked:
            return "Replace the active model"
        case .ready:
            return "Review transcription model"
        }
    }
}

struct PersistentStorageUnavailableView: View {
    let issue: AppRuntimeIssue

    init(
        issue: AppRuntimeIssue = .persistentStorageUnavailable
    ) {
        self.issue = issue
    }

    var body: some View {
        ZStack {
            TextifyAcousticBackdrop()

            TextifyCard(padding: 28) {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(TextifyVisualIdentity.warmWarning.opacity(0.14))
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(TextifyVisualIdentity.warmWarning)
                    }
                    .frame(width: 72, height: 72)

                    Text(title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(issue.userMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 460)
                    Button("Quit Textify") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 540)
            .padding(32)
        }
        .tint(TextifyVisualIdentity.voiceViolet)
    }

    private var title: String {
        switch issue {
        case .persistentStorageUnavailable:
            return "Textify storage is unavailable"
        case .modelTrustUnavailable:
            return "Textify model trust is unavailable"
        case .retiredModelCleanupFailed:
            return "Textify model cleanup is incomplete"
        case .hotkeyMonitorUnavailable:
            return "Textify trigger is unavailable"
        }
    }
}

extension SettingsPane {
    static let productionVisiblePanes: [SettingsPane] = [
        .general,
        .dictation,
        .transcriptionModels,
        .voiceCleaning,
        .privacy,
        .logs,
        .advanced
    ]

    var sidebarTitle: String {
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
}

private struct GeneralSettingsPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var services = services

        SettingsPaneLayout(
            title: "General",
            subtitle: "See readiness at a glance and choose how Textify starts."
        ) {
            SettingsSection("Status") {
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(readinessColor.opacity(0.14))
                        TextifyVoiceMark(state: services.dictation.readiness.canDictate ? .ready : .blocked, height: 28)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(TextifyReadinessPresentation.title(canDictate: services.dictation.readiness.canDictate))
                                .font(.system(size: 15, weight: .semibold))
                            TextifyStatusBadge(
                                title: services.dictation.readiness.canDictate ? "READY" : "ACTION NEEDED",
                                tone: services.dictation.readiness.canDictate ? .success : .warning
                            )
                        }
                        Text(TextifyReadinessPresentation.detail(
                            canDictate: services.dictation.readiness.canDictate,
                            triggerName: services.preferences.trigger.displayName
                        ))
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    TextifyKeycap(title: services.preferences.trigger.displayName)
                }
                .accessibilityElement(children: .combine)
            }

            SettingsSection("Behavior") {
                LabeledContent {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .disabled(!services.canChangeLaunchAtLogin)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                        Text("Start Textify automatically when you sign in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(launchAtLoginStatusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                launchAtLoginAction

                Divider()

                LabeledContent {
                    Toggle(
                        DockPreferencePresentation.title,
                        isOn: $services.preferences.keepTextifyInDock
                    )
                    .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DockPreferencePresentation.title)
                        Text("Keep a dependable way to reopen the main window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Quit and reopen Textify to apply this change.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Quit Textify") {
                    NSApplication.shared.terminate(nil)
                }
            }

            SettingsSection("About") {
                LabeledContent {
                    Text(appVersion)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                } label: {
                    Text("App Version")
                }
            }
        }
        .onChange(of: services.preferences) { _, _ in
            services.savePreferences()
        }
        .onAppear {
            services.refreshLaunchAtLoginStatus()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                LaunchAtLoginToggleModel.isOn(status: services.launchAtLoginStatus)
            },
            set: { isEnabled in
                Task {
                    await services.setLaunchAtLoginEnabled(isEnabled)
                }
            }
        )
    }

    private var launchAtLoginStatusText: String {
        if services.launchAtLoginOperationError != nil {
            if services.launchAtLoginFailedRequestedEnabled == false {
                return "Textify could not disable Launch at Login. Use System Settings -> General -> Login Items."
            }
            return "Textify could not update Launch at Login."
        }

        switch services.launchAtLoginStatus {
        case .enabled:
            return "Textify will open at login."
        case .disabled:
            return "Textify will not open at login."
        case .requiresApproval:
            return "macOS needs approval before Textify can open at login."
        case .unsupportedLocation:
            return "Move Textify to Applications to use Launch at Login."
        case .unavailable:
            return "Textify could not check Launch at Login status."
        case .failed:
            return "Textify could not update Launch at Login."
        }
    }

    @ViewBuilder
    private var launchAtLoginAction: some View {
        if services.launchAtLoginStatus == .requiresApproval {
            Button("Open Login Items Settings") {
                LoginItemsSettingsOpener.open()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var readinessColor: Color {
        services.dictation.readiness.canDictate
            ? TextifyVisualIdentity.readyMint
            : TextifyVisualIdentity.warmWarning
    }
}

enum DockPreferencePresentation {
    static let title = "Keep Textify in the Dock"
}

struct LoginItemsSettingsOpener {
    static let loginItemsSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    )!

    static func open(workspace: NSWorkspace = .shared) {
        workspace.open(loginItemsSettingsURL)
    }
}

enum LaunchAtLoginToggleModel {
    static func isOn(status: LaunchAtLoginStatus) -> Bool {
        status == .enabled
    }
}

private struct DictationSettingsPane: View {
    @Environment(AppServices.self) private var services
    @State private var triggerTest = OnboardingTriggerTestController()
    @State private var microphonePermissionTask: Task<Void, Never>?
    @State private var microphonePermissionMessage: String?

    var body: some View {
        SettingsPaneLayout(title: "Dictation") {
            SettingsSection("Input") {
                LabeledContent("Dictation Trigger") {
                    Picker("Dictation Trigger", selection: triggerBinding) {
                        ForEach(TextifySettings.TriggerPreference.allCases, id: \.self) { trigger in
                            Text(trigger.displayName).tag(trigger)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Divider()
                LabeledContent("Language") {
                    Picker("Language", selection: languageBinding) {
                        ForEach(services.availableTranscriptionLanguages, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Divider()
                LabeledContent("Microphone") {
                    microphoneMenu
                        .frame(width: 220, alignment: .trailing)
                }
                Divider()
                microphoneLevelOrPermission
            }

            SettingsSection("Floating Icon") {
                FloatingIconSettingsView(
                    preferences: services.preferences.recordingOverlay,
                    xOffset: overlayPreferenceBinding(\.xOffset),
                    yOffset: overlayPreferenceBinding(\.yOffset),
                    scale: overlayPreferenceBinding(\.scale)
                ) {
                    services.setRecordingOverlayPreferences(.defaults)
                }
            }

            SettingsSection("Trigger Test") {
                HStack(spacing: 14) {
                    TextifyKeycap(title: services.preferences.trigger.displayName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice the hold-and-release gesture")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text("The test never records or inserts text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button(triggerTest.isRunning ? "Restart Test" : "Start Test") {
                        triggerTest.start(suspending: services)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop Test") {
                        triggerTest.stop()
                    }
                    .disabled(!triggerTest.isRunning)
                }

                TriggerTestSummary(result: triggerTest.result)
                Text(triggerTest.displayStatusText(triggerName: services.preferences.trigger.displayName))
                    .foregroundStyle(triggerTest.result.passed ? .green : .secondary)
            }

            SettingsSection("Runtime") {
                LabeledContent("Status") {
                    TextifyStatusBadge(title: services.dictation.status.menuStatusTitle, tone: .accent)
                }
                LabeledContent("Readiness") {
                    TextifyStatusBadge(
                        title: services.dictation.readiness.canDictate ? "Ready" : "Setup Required",
                        tone: services.dictation.readiness.canDictate ? .success : .warning
                    )
                }
                if let runtimeIssue = services.runtimeIssue {
                    Text(runtimeIssue.userMessage)
                        .foregroundStyle(.orange)
                    if runtimeIssue == .hotkeyMonitorUnavailable {
                        Button("Retry Trigger") {
                            services.startRuntime()
                        }
                    }
                }
            }
        }
        .task {
            _ = await services.dictation.refreshReadiness()
            services.refreshMicrophoneInputs()
        }
        .onDisappear {
            triggerTest.stop()
            microphonePermissionTask?.cancel()
            microphonePermissionTask = nil
        }
    }

    private var triggerBinding: Binding<TextifySettings.TriggerPreference> {
        Binding(
            get: { services.preferences.trigger },
            set: { services.setTrigger($0) }
        )
    }

    private var languageBinding: Binding<TranscriptionLanguage> {
        Binding(
            get: { services.preferences.transcriptionLanguage },
            set: { services.setTranscriptionLanguage($0) }
        )
    }

    private var microphoneMenu: some View {
        Menu {
            Button {
                services.setMicrophoneSelection(.systemDefault)
            } label: {
                microphoneMenuLabel(
                    "System Default",
                    isSelected:
                        services.preferences.microphoneSelection
                            == .systemDefault
                )
            }

            Divider()

            let devices =
                services.microphoneInputPresentation.presentedDevices(
                    selection: services.preferences.microphoneSelection
                )
            if devices.isEmpty {
                Text("No input devices found")
            } else {
                ForEach(devices) { device in
                    Button {
                        services.setMicrophoneSelection(
                            .device(
                                deviceUID: device.id,
                                lastSeenDisplayName: device.displayName
                            )
                        )
                    } label: {
                        microphoneMenuLabel(
                            device.isAvailable
                                ? device.displayName
                                : "\(device.displayName) — Unavailable",
                            isSelected: isSelectedMicrophone(device.id)
                        )
                    }
                    .disabled(!device.isAvailable)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedMicrophoneTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityLabel("Microphone")
        .accessibilityValue(selectedMicrophoneTitle)
    }

    @ViewBuilder
    private var microphoneLevelOrPermission: some View {
        if services.dictation.readiness.permissions.microphone == .granted {
            VStack(alignment: .leading, spacing: 10) {
                if services.microphoneInputPresentation
                    .deviceRefreshFailed {
                    HStack {
                        Label(
                            "The microphone list could not be refreshed.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)

                        Spacer()

                        Button("Retry") {
                            services.refreshMicrophoneInputs()
                        }
                        .controlSize(.small)
                    }
                }

                MicrophoneInputLevelView(
                    level: services.microphoneInputPresentation.level,
                    isMonitoring:
                        services.microphoneInputPresentation.isMonitoring,
                    error:
                        services.microphoneInputPresentation.monitoringError
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Allow Microphone access to preview the selected input level."
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                Button(microphonePermissionActionTitle) {
                    performMicrophonePermissionAction()
                }
                .disabled(microphonePermissionTask != nil)

                if let microphonePermissionMessage {
                    Text(microphonePermissionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func microphoneMenuLabel(
        _ title: String,
        isSelected: Bool
    ) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func isSelectedMicrophone(_ deviceUID: String) -> Bool {
        guard case let .device(selectedUID, _) =
            services.preferences.microphoneSelection
        else {
            return false
        }
        return selectedUID == deviceUID
    }

    private var selectedMicrophoneTitle: String {
        switch services.preferences.microphoneSelection {
        case .systemDefault:
            return "System Default"
        case let .device(deviceUID, lastSeenDisplayName):
            let isAvailable =
                services.microphoneInputPresentation.devices.contains {
                    $0.id == deviceUID
                }
            return isAvailable
                ? lastSeenDisplayName
                : "\(lastSeenDisplayName) — Unavailable"
        }
    }

    private var microphonePermissionActionTitle: String {
        services.dictation.readiness.permissions.microphone == .denied
            ? "Open Microphone Settings"
            : "Request Microphone Access"
    }

    private func performMicrophonePermissionAction() {
        guard microphonePermissionTask == nil else {
            return
        }

        if services.dictation.readiness.permissions.microphone == .denied {
            if SystemPrivacySettingsOpener.open(.microphone) {
                microphonePermissionMessage =
                    "Turn on Microphone for Textify in System Settings, then return here."
            } else {
                microphonePermissionMessage =
                    "Open System Settings → Privacy & Security → Microphone, then turn on Textify."
            }
            return
        }

        microphonePermissionTask = Task {
            defer {
                microphonePermissionTask = nil
            }
            let state =
                await ProductionPermissionRequester.requestMicrophone()
            guard !Task.isCancelled else {
                return
            }
            microphonePermissionMessage =
                state.permissionRequestMessage(for: "Microphone")
            _ = await services.dictation.refreshReadiness()
            services.refreshMicrophoneInputs()
        }
    }

    private func overlayPreferenceBinding(
        _ keyPath: WritableKeyPath<RecordingOverlayPreferences, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                services.preferences.recordingOverlay[keyPath: keyPath]
            },
            set: { value in
                var preferences = services.preferences.recordingOverlay
                preferences[keyPath: keyPath] = value
                services.setRecordingOverlayPreferences(preferences)
            }
        )
    }
}

private struct FloatingIconSettingsView: View {
    let preferences: RecordingOverlayPreferences
    @Binding var xOffset: Double
    @Binding var yOffset: Double
    @Binding var scale: Double
    let reset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Place the indicator where it stays out of your way.")
                        .font(.callout.weight(.medium))
                    Text("Offsets start at the active display's bottom center.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button(action: reset) {
                    Label(
                        "Reset Position & Scale",
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(preferences == .defaults)
            }

            FloatingIconPreview(preferences: preferences)

            VStack(spacing: 8) {
                FloatingIconControlRow(
                    icon: "arrow.left.and.right",
                    title: "X Offset",
                    detail: "Left / Right",
                    value: $xOffset,
                    range: RecordingOverlayPreferences.xOffsetRange,
                    step: 1,
                    lowerLabel: "Left",
                    upperLabel: "Right"
                ) { value in
                    "\(Int(value.rounded())) pt"
                }

                FloatingIconControlRow(
                    icon: "arrow.up.and.down",
                    title: "Y Offset",
                    detail: "Down / Up",
                    value: $yOffset,
                    range: RecordingOverlayPreferences.yOffsetRange,
                    step: 1,
                    lowerLabel: "Down",
                    upperLabel: "Up"
                ) { value in
                    "\(Int(value.rounded())) pt"
                }

                FloatingIconControlRow(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Scale",
                    detail: "Indicator size",
                    value: $scale,
                    range: RecordingOverlayPreferences.scaleRange,
                    step: 0.05,
                    lowerLabel: "50%",
                    upperLabel: "200%"
                ) { value in
                    "\(Int((value * 100).rounded()))%"
                }
            }
        }
    }
}

private struct FloatingIconControlRow: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let lowerLabel: String
    let upperLabel: String
    let valueLabel: (Double) -> String

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                    .frame(width: 28, height: 28)
                    .background(
                        TextifyVisualIdentity.voiceViolet.opacity(0.12),
                        in: RoundedRectangle(
                            cornerRadius: 7,
                            style: .continuous
                        )
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Text(valueLabel(value))
                        .font(
                            .system(
                                size: 12,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .frame(minWidth: 62)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            TextifyVisualIdentity.raisedSurface,
                            in: Capsule(style: .continuous)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(
                                    TextifyVisualIdentity.separator,
                                    lineWidth: 1
                                )
                        }
                        .accessibilityHidden(true)

                    Stepper(
                        "Adjust \(title)",
                        value: quantizedValue,
                        in: range,
                        step: step
                    )
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .accessibilityLabel("Adjust \(title)")
                    .accessibilityValue(valueLabel(value))
                }
            }

            Slider(value: quantizedValue, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(valueLabel(value))

            HStack {
                Text(lowerLabel)
                Spacer()
                Text(upperLabel)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
        }
    }

    private var quantizedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                let steps = (
                    (newValue - range.lowerBound) / step
                ).rounded()
                let quantized = range.lowerBound + steps * step
                let clamped = min(
                    max(quantized, range.lowerBound),
                    range.upperBound
                )
                guard clamped != value else {
                    return
                }
                value = clamped
            }
        )
    }
}

private struct FloatingIconPreview: View {
    let preferences: RecordingOverlayPreferences

    private let indicatorSize = CGSize(width: 104, height: 28)

    var body: some View {
        GeometryReader { geometry in
            let preferences = preferences.normalized()
            let scale = CGFloat(preferences.scale)
            let scaledIndicatorSize = CGSize(
                width: indicatorSize.width * scale,
                height: indicatorSize.height * scale
            )

            ZStack {
                previewBackground

                centerGuide(in: geometry.size)

                previewIndicator
                    .scaleEffect(scale)
                    .frame(
                        width: scaledIndicatorSize.width,
                        height: scaledIndicatorSize.height
                    )
                    .position(
                        x: indicatorX(
                            in: geometry.size,
                            indicatorWidth: scaledIndicatorSize.width,
                            offset: preferences.xOffset
                        ),
                        y: indicatorY(
                            in: geometry.size,
                            indicatorHeight: scaledIndicatorSize.height,
                            offset: preferences.yOffset
                        )
                    )

                previewHeader(preferences)
            }
        }
        .frame(height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Floating icon preview")
        .accessibilityValue(accessibilityValue)
    }

    private var previewBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        TextifyVisualIdentity.raisedSurface.opacity(0.82),
                        TextifyVisualIdentity.windowSurface.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
            }
    }

    private func centerGuide(in size: CGSize) -> some View {
        Path { path in
            path.move(to: CGPoint(x: size.width / 2, y: 34))
            path.addLine(
                to: CGPoint(x: size.width / 2, y: size.height - 10)
            )
            path.move(to: CGPoint(x: 12, y: size.height - 10))
            path.addLine(
                to: CGPoint(x: size.width - 12, y: size.height - 10)
            )
        }
        .stroke(
            Color.white.opacity(0.12),
            style: StrokeStyle(lineWidth: 1, dash: [3, 4])
        )
    }

    private var previewIndicator: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(TextifyVisualIdentity.recordCoral)
                .frame(width: 6, height: 6)

            TextifyVoiceMark(state: .recording, height: 12)

            Text("Textify")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.88))
        }
        .frame(width: indicatorSize.width, height: indicatorSize.height)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.11, blue: 0.13),
                            Color(red: 0.045, green: 0.05, blue: 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.42), radius: 7, y: 4)
    }

    private func previewHeader(
        _ preferences: RecordingOverlayPreferences
    ) -> some View {
        VStack {
            HStack(spacing: 8) {
                Label("Live Preview", systemImage: "display")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(
                    "X \(signedPoints(preferences.xOffset))"
                        + "  •  Y \(signedPoints(preferences.yOffset))"
                        + "  •  \(Int((preferences.scale * 100).rounded()))%"
                )
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer()
        }
    }

    private func indicatorX(
        in size: CGSize,
        indicatorWidth: CGFloat,
        offset: Double
    ) -> CGFloat {
        let normalizedOffset = CGFloat(
            offset / RecordingOverlayPreferences.xOffsetRange.upperBound
        )
        let travel = max(0, (size.width - indicatorWidth) / 2 - 14)
        return size.width / 2 + normalizedOffset * travel
    }

    private func indicatorY(
        in size: CGSize,
        indicatorHeight: CGFloat,
        offset: Double
    ) -> CGFloat {
        let defaultY = size.height - indicatorHeight / 2 - 13
        let normalizedOffset = CGFloat(
            offset / RecordingOverlayPreferences.yOffsetRange.upperBound
        )

        if normalizedOffset >= 0 {
            let upwardTravel = max(
                0,
                defaultY - indicatorHeight / 2 - 34
            )
            return defaultY - normalizedOffset * upwardTravel
        }

        let downwardTravel = max(
            0,
            size.height - indicatorHeight / 2 - 4 - defaultY
        )
        return defaultY - normalizedOffset * downwardTravel
    }

    private var accessibilityValue: String {
        let preferences = preferences.normalized()
        return "X offset \(Int(preferences.xOffset.rounded())) points, "
            + "Y offset \(Int(preferences.yOffset.rounded())) points, "
            + "scale \(Int((preferences.scale * 100).rounded())) percent"
    }

    private func signedPoints(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded > 0 {
            return "+\(rounded)"
        }
        return "\(rounded)"
    }
}

extension TextifySettings.TriggerPreference {
    var displayName: String {
        switch self {
        case .rightCommand:
            return "Right Command"
        case .rightOption:
            return "Right Option"
        case .rightControl:
            return "Right Control"
        case .controlSpace:
            return "Control-Space"
        }
    }
}

extension TranscriptionLanguage {
    var displayName: String {
        if self == .automatic {
            return "Automatic"
        }
        return Locale.current.localizedString(forLanguageCode: rawValue)?.capitalized
            ?? rawValue.uppercased()
    }
}

struct ModelCatalogPaneLifecyclePresentation: Equatable {
    let hasUsefulProjection: Bool
    let showsInitialLoadingPlaceholder: Bool
    let showsInspector: Bool
    let focusedRowID: ModelCatalogHierarchyRowID?
    let scrollAnchorID: ModelCatalogHierarchyRowID?

    @MainActor
    init(
        featureModel: ModelCatalogFeatureModel,
        coordinator: ModelCatalogCoordinator
    ) {
        hasUsefulProjection = featureModel.snapshot != nil
        showsInitialLoadingPlaceholder =
            featureModel.snapshot == nil
            && coordinator.manifest == nil
            && coordinator.status == .checking
        showsInspector = featureModel.showsInspector
        focusedRowID = featureModel.hierarchyState.focusedRowID
        scrollAnchorID = featureModel.hierarchyState.scrollAnchorID
    }
}

private struct ModelCheckpointPendingLanguageUse: Equatable {
    let checkpointID: String
    let artifactID: String
    let artifactName: String
    let mismatch: ModelCheckpointLanguageMismatch
}

private struct ModelCheckpointOrderContext: Equatable {
    let language: String?
    let browsesAllLanguages: Bool
    let searchText: String
}

private enum ModelCheckpointInspectorMode {
    case trailing
    case sheet
}

struct ModelsSettingsPane: View {
    @Environment(AppServices.self) private var services
    let destination: ModelCatalogPurposeDestination
    @Bindable private var featureModel: ModelCatalogFeatureModel

    @State private var modelMessage: String?
    @State private var activatingModelID: String?
    @State private var pendingImportURL: URL?
    @State private var showsImportConfirmation = false
    @State private var isImporting = false
    @State private var pendingRemoval:
        ModelRemovalConfirmationPresentation?
    @State private var showsModelVariantsHelp = false
    @State private var showsDownloads = false
    @State private var pendingLanguageMismatchUse:
        ModelCheckpointPendingLanguageUse?
    @State private var checkpointInspectorMode:
        ModelCheckpointInspectorMode = .sheet
    @State private var expandedCheckpointID: String?
    @FocusState private var catalogHasKeyboardFocus: Bool
    @FocusState private var focusedCatalogRowID: ModelCatalogHierarchyRowID?
    @AccessibilityFocusState private var accessibilityFocusedCatalogRowID:
        ModelCatalogHierarchyRowID?
    @Environment(\.colorSchemeContrast)
    private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    init(
        destination: ModelCatalogPurposeDestination,
        featureModel: ModelCatalogFeatureModel
    ) {
        self.destination = destination
        _featureModel = Bindable(wrappedValue: featureModel)
    }

    var body: some View {
        var derivationRequest = services.modelCatalogDerivationRequest(
            for: destination.purpose,
            query: catalogQuery
        )
        derivationRequest.screen = ModelCatalogScreenRequest(
            purpose: destination.purpose,
            selectedLanguage:
                destination == .transcription
                    ? services.preferences.transcriptionLanguage.rawValue
                    : nil,
            browseAllLanguages: featureModel.browseAllLanguages,
            artifactOverrides: services.modelArtifactOverrides(
                for: destination.purpose
            ),
            stableCheckpointOrder: featureModel.checkpointOrderIDs,
            includesRichTransferState: true
        )
        let catalogExperience = featureModel.snapshot?.experience
            ?? ModelCatalogExperience(
                trustedModels: [],
                installedRecords: [],
                activePreferences: ModelCatalogActivePreferences(),
                transferState: nil,
                query: catalogQuery
            )
        let lifecyclePresentation =
            ModelCatalogPaneLifecyclePresentation(
                featureModel: featureModel,
                coordinator: services.modelCatalogCoordinator
            )
        let checkpointPresentation =
            featureModel.snapshot?.screenProjection ?? .empty
        let richCheckpointPresentation:
            ModelCheckpointListPresentation? =
            destination == .voiceCleaning || featureModel.showsInspector
            ? ModelCheckpointListPresentation(
                experience: catalogExperience,
                purpose: destination.purpose,
                selectedLanguage:
                    destination == .transcription
                        ? services.preferences.transcriptionLanguage.rawValue
                        : nil,
                browseAllLanguages: featureModel.browseAllLanguages,
                searchText: featureModel.discoveryQuery.searchText,
                artifactOverrides:
                    featureModel.snapshot?.overrideResolution
                    .legalArtifactIDsByCheckpoint ?? [:],
                stableCheckpointOrder: featureModel.checkpointOrderIDs
            )
            : nil
        let inspectedCheckpointRow =
            richCheckpointPresentation?.rows.first {
                featureModel.hierarchyState.selection
                    == .checkpoint($0.checkpointID)
            }
        let standaloneInstalledRows =
            ModelCheckpointListPresentation.standaloneInstalledRows(
                in: catalogExperience
            )

        return ModelCatalogSettingsPaneLayout(
            title: destination.title,
            subtitle: destination.subtitle,
            maxContentWidth:
                destination == .voiceCleaning ? 880 : 1_360,
            catalogViewportRestoration: viewportRestoration
        ) {
            catalogStatus(hasRows: !catalogExperience.rows.isEmpty)

            if services.modelCatalogCoordinator.securityIssue != nil {
                ModelCatalogEmptyState(
                    presentation: .securityFailure(destination),
                    onAction: {}
                )
                .onAppear {
                    featureModel.showsInspector = false
                }
            } else {
                if services.settingsRouter.modelReplacementPurpose
                    == destination.purpose
                {
                    Label(
                        "The previous selection was revoked. Choose and explicitly activate a replacement.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }

                if let removalStatus = services.modelRemovalStatus {
                    Label(
                        removalStatus.phase == .finishingCurrentDictation
                            ? "Finishing Current Dictation before removing this Exact Artifact."
                            : "Removing the selected Exact Artifact…",
                        systemImage: "hourglass"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else if let modelMessage {
                    Text(modelMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let modelUseStatusMessage =
                    services.modelUseStatusMessage
                {
                    Text(modelUseStatusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if ProductionModelInstallConfiguration.current == nil,
                    services.modelCatalogCoordinator.manifest == nil
                {
                    Text("Signed catalog unavailable in this build")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !lifecyclePresentation.showsInitialLoadingPlaceholder {
                    if destination == .transcription {
                        ModelCheckpointToolbar(
                            searchText:
                                $featureModel.discoveryQuery.searchText,
                            browseAllLanguages:
                                $featureModel.browseAllLanguages,
                            language:
                                services.preferences.transcriptionLanguage,
                            downloadCount:
                                ModelDownloadsPresentation(
                                    attempts:
                                        services.modelInstallCoordinator
                                        .attempts
                                ).nonterminalCount,
                            onSelectLanguage: {
                                services.selectCatalogTranscriptionLanguage($0)
                            },
                            onShowDownloads: {
                                showsDownloads = true
                            },
                            onVerify: verifyInstalledModels,
                            onImport: chooseCustomWhisperModel
                        )
                    } else {
                        HStack {
                            Spacer()
                            Button {
                                showsDownloads = true
                            } label: {
                                Label(
                                    "Downloads",
                                    systemImage: "arrow.down.circle"
                                )
                            }
                            .controlSize(.small)
                        }
                    }

                    if let pinnedReveal = catalogExperience.pinnedReveal {
                        pinnedRevealView(
                            pinnedReveal,
                            in: catalogExperience
                        )
                    }
                }

                if lifecyclePresentation.showsInitialLoadingPlaceholder {
                    ModelCatalogEmptyState(
                        presentation: .checking,
                        onAction: {}
                    )
                } else if destination == .voiceCleaning {
                    VoiceCleaningFeatureCard(
                        row: richCheckpointPresentation?.rows.first,
                        isBusy: modelTransactionsAreBusy,
                        disabledReason: modelTransactionDisabledReason,
                        onUse: useCheckpointArtifact,
                        onDisable: disableVoiceCleaning,
                        onInspect: inspectCheckpoint,
                        onInspectExactArtifact: inspectExactArtifact,
                        onRemoveExactArtifact: { artifactID in
                            guard let artifact =
                                exactArtifactPresentation(artifactID)
                            else {
                                return
                            }
                            removeCheckpointArtifact(artifact)
                        }
                    )
                } else if checkpointPresentation.rows.isEmpty
                    && standaloneInstalledRows.isEmpty
                {
                    ModelCatalogEmptyState(
                        presentation: emptyPresentation,
                        onAction: performEmptyStateAction
                    )
                } else {
                    if !checkpointPresentation.rows.isEmpty {
                        ModelCheckpointCatalogSurface(
                            presentation: checkpointPresentation,
                            isBusy: modelTransactionsAreBusy,
                            disabledReason: modelTransactionDisabledReason,
                            focusedCheckpointID:
                                focusedCheckpointID,
                            selectedCheckpointID:
                                selectedCheckpointID,
                            selectedExactArtifactID:
                                selectedExactArtifactID,
                            expandedCheckpointID:
                                expandedCheckpointID,
                            visualPolicy:
                                checkpointAccessibilityVisualPolicy,
                            keyboardFocus: $catalogHasKeyboardFocus,
                            transferRegistry:
                                featureModel.transferStateRegistry,
                            transferTopologyVersion:
                                featureModel.transferTopologyVersion,
                            onCommand: handleCatalogScreenCommand
                        )
                        .equatable()
                    }
                    if !standaloneInstalledRows.isEmpty {
                        standaloneInstalledSurface(
                            standaloneInstalledRows,
                            in: catalogExperience
                        )
                    }
                }
            }
        }
        .inspector(isPresented: trailingInspectorBinding) {
            ScrollView {
                modelInspectorContent(inspectedCheckpointRow)
            }
            .scrollContentBackground(.hidden)
            .inspectorColumnWidth(min: 280, ideal: 320, max: 360)
        }
        .sheet(isPresented: sheetInspectorBinding) {
            ScrollView {
                modelInspectorContent(inspectedCheckpointRow)
            }
            .scrollContentBackground(.hidden)
            .frame(minWidth: 560, minHeight: 560)
            .background(TextifyVisualIdentity.windowSurface)
        }
        .popover(isPresented: $showsModelVariantsHelp) {
            ModelCatalogVariantsAboutView()
        }
        .onAppear {
            let resetsAfterActivation =
                featureModel.refreshCheckpointOrderOnNextEntry
            if featureModel.checkpointOrderIDs.isEmpty
                || resetsAfterActivation {
                featureModel.checkpointOrderIDs =
                    checkpointPresentation.rows.map(\.id)
                featureModel.refreshCheckpointOrderOnNextEntry = false
            }
            if resetsAfterActivation,
               let activeCheckpointID =
                   checkpointPresentation.rows.first?.id {
                let rowID = ModelCatalogHierarchyRowID.checkpoint(
                    activeCheckpointID
                )
                let selection = ModelCatalogHierarchySelection.checkpoint(
                    activeCheckpointID
                )
                featureModel.hierarchyState.focus(rowID)
                featureModel.hierarchyState.select(selection)
                featureModel.hierarchyState.scroll(to: rowID)
                featureModel.viewportRestorationGeneration &+= 1
            } else {
                if destination == .voiceCleaning {
                    focusedCatalogRowID =
                        featureModel.hierarchyState.focusedRowID
                }
            }
        }
        .task {
            _ = featureModel.announcementTracker.update(
                attempts: services.modelInstallCoordinator.attempts
            )
            services.refreshModelStorageInventory()
            _ = await services.dictation.refreshReadiness()
        }
        .onChange(of: derivationRequest, initial: true) { _, request in
            featureModel.submit(request)
        }
        .onChange(of: featureModel.showsInspector) { _, showsInspector in
            if showsInspector {
                checkpointInspectorMode = preferredInspectorMode
            }
        }
        .onChange(of: checkpointOrderContext) { _, _ in
            featureModel.checkpointOrderIDs = []
        }
        .onChange(
            of: featureModel.snapshot?.screenProjection.rows.map(\.id),
            initial: true
        ) { _, checkpointIDs in
            if let expandedCheckpointID,
                checkpointIDs?.contains(expandedCheckpointID) != true
            {
                self.expandedCheckpointID = nil
            }
            guard featureModel.checkpointOrderIDs.isEmpty,
                let checkpointIDs,
                !checkpointIDs.isEmpty
            else {
                return
            }
            featureModel.checkpointOrderIDs = checkpointIDs
        }
        .onChange(of: activeArtifactIDForDestination) { previous, current in
            if current != nil, current != previous {
                featureModel.refreshCheckpointOrderOnNextEntry = true
            }
        }
        .onChange(
            of: featureModel.snapshot?.versions.queryResult,
            initial: true
        ) { _, _ in
            guard let updatedExperience =
                    featureModel.snapshot?.experience
            else {
                return
            }
            let recovery = featureModel.hierarchyState.reconcile(
                from: featureModel.reconciledCatalogExperience,
                to: updatedExperience
            )
            featureModel.reconciledCatalogExperience = updatedExperience
            if recovery != nil,
               featureModel.hierarchyState.scrollAnchorID == nil {
                featureModel.hierarchyState.scroll(to: featureModel.hierarchyState.focusedRowID)
            }
            if featureModel.hierarchyState.scrollAnchorID != nil {
                featureModel.viewportRestorationGeneration &+= 1
            }
            if destination == .voiceCleaning {
                focusedCatalogRowID =
                    featureModel.hierarchyState.focusedRowID
            }
            featureModel.inspectorController.select(
                featureModel.hierarchyState.selection,
                in: updatedExperience
            )
            if featureModel.hierarchyState.selection == nil {
                featureModel.showsInspector = false
            }
            if let recovery,
               featureModel.hierarchyState.focusedRowID != nil {
                announce(recovery.announcement)
            }
            for announcement in featureModel.announcementTracker.update(
                rows: updatedExperience.rows
            ) {
                announce(announcement)
            }
        }
        .onChange(
            of: featureModel.snapshot?.versions.localStateOverlay
        ) { _, _ in
            guard featureModel.showsInspector,
                  let updatedExperience =
                    featureModel.snapshot?.experience
            else {
                return
            }
            featureModel.inspectorController.select(
                featureModel.hierarchyState.selection,
                in: updatedExperience
            )
        }
        .onChange(of: focusedCatalogRowID) { _, rowID in
            featureModel.hierarchyState.focus(rowID)
        }
        .onChange(
            of: accessibilityFocusedCatalogRowID
        ) { _, rowID in
            if let rowID {
                featureModel.hierarchyState.focus(rowID)
            }
        }
        .onChange(
            of: services.modelInstallCoordinator.attempts
        ) { _, attempts in
            for announcement in featureModel.announcementTracker.update(
                attempts: attempts
            ) {
                announce(announcement)
            }
        }
        .onChange(
            of: featureModel.snapshot?.overrideResolution
                .invalidArtifactIDsByCheckpoint,
            initial: true
        ) { _, invalidOverrides in
            guard let invalidOverrides, !invalidOverrides.isEmpty else {
                return
            }
            services.removeInvalidModelArtifactOverrides(
                invalidOverrides,
                for: destination.purpose
            )
        }
        .onChange(of: featureModel.inspectorController.verificationState) { _, state in
            switch state {
            case let .verified(artifactID):
                let expectedRestorationIDs =
                    featureModel.verificationRestorationIDsByArtifact[artifactID]
                        ?? []
                featureModel.verificationRestorationIDsByArtifact[artifactID] = nil
                Task {
                    await services.acknowledgeRestoredModelIntegrity(
                        artifactID,
                        expectedRestorationIDs:
                            expectedRestorationIDs
                    )
                    services.refreshModelStorageInventory()
                }
            case let .failed(artifactID):
                featureModel.verificationRestorationIDsByArtifact[artifactID] = nil
                services.refreshModelStorageInventory()
            case .unavailable, .available, .verifying:
                break
            }
        }
        .onKeyPress(
            keys: [
                .upArrow,
                .downArrow,
                .pageUp,
                .pageDown,
                .home,
                .end,
                .return,
                .leftArrow,
                .rightArrow,
                .delete,
            ],
            phases: .down
        ) { keyPress in
            handleModelsKeyPress(
                keyPress,
                checkpointPresentation: checkpointPresentation,
                catalogExperience: catalogExperience
            )
        }
        .alert("Import local Whisper model?", isPresented: $showsImportConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
            Button("Import") {
                importPendingWhisperModel()
            }
        } message: {
            Text("Textify validates the file and loads it locally with Whisper.cpp. Only continue if you trust the file and its license permits your use. Textify cannot verify third-party model licenses.")
        }
        .alert(
            "Change Dictation Language?",
            isPresented: pendingLanguageMismatchAlertBinding,
            presenting: pendingLanguageMismatchUse
        ) { pending in
            Button("Cancel", role: .cancel) {
                pendingLanguageMismatchUse = nil
            }
            Button("Use \(pending.mismatch.supportedLanguageName)") {
                guard let language = TranscriptionLanguage(
                    rawValue: pending.mismatch.supportedLanguageCode
                ) else {
                    pendingLanguageMismatchUse = nil
                    return
                }
                services.selectCatalogTranscriptionLanguage(language)
                pendingLanguageMismatchUse = nil
                performCheckpointUse(
                    checkpointID: pending.checkpointID,
                    artifactID: pending.artifactID
                )
            }
        } message: { pending in
            Text(
                "\(pending.artifactName) does not support \(pending.mismatch.requestedLanguageName). Change Dictation Language to \(pending.mismatch.supportedLanguageName) and continue?"
            )
        }
        .alert(
            pendingRemoval.map {
                "Delete \($0.exactArtifactName)?"
            } ?? "Delete Exact Artifact?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { confirmation in
            Button("Cancel", role: .cancel) {
                resolveRemoval(
                    confirmation,
                    confirmed: false
                )
            }
            Button(
                confirmation.destructiveActionTitle,
                role: .destructive
            ) {
                resolveRemoval(
                    confirmation,
                    confirmed: true
                )
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var hasPendingDownloads: Bool {
        services.modelInstallCoordinator.hasNonterminalAttempts
    }

    private var focusedCheckpointID: String? {
        guard case let .checkpoint(id) =
            featureModel.hierarchyState.focusedRowID
        else {
            return nil
        }
        return id
    }

    private var selectedCheckpointID: String? {
        switch featureModel.hierarchyState.selection {
        case let .checkpoint(id):
            return id
        case let .exactArtifact(artifactID):
            return featureModel.snapshot?.screenProjection.rows.first {
                $0.containsArtifact(artifactID)
            }?.checkpointID
        case nil:
            return nil
        }
    }

    private var selectedExactArtifactID: String? {
        guard case let .exactArtifact(id) =
            featureModel.hierarchyState.selection
        else {
            return nil
        }
        return id
    }

    private var checkpointAccessibilityVisualPolicy:
        ModelCheckpointAccessibilityVisualPolicy
    {
        ModelCheckpointAccessibilityVisualPolicy(
            increaseContrast: colorSchemeContrast == .increased,
            differentiateWithoutColor: differentiateWithoutColor,
            reduceTransparency: reduceTransparency
        )
    }

    private var preferredInspectorMode: ModelCheckpointInspectorMode {
        let windowWidth = NSApp.keyWindow?.frame.width ?? 0
        return ModelCheckpointInspectorLayoutPolicy()
            .usesTrailingInspector(windowWidth: windowWidth)
            ? .trailing
            : .sheet
    }

    private var pendingLanguageMismatchAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingLanguageMismatchUse != nil },
            set: {
                if !$0 {
                    pendingLanguageMismatchUse = nil
                }
            }
        )
    }

    private var trailingInspectorBinding: Binding<Bool> {
        Binding(
            get: {
                featureModel.showsInspector
                    && checkpointInspectorMode == .trailing
            },
            set: {
                if !$0 {
                    featureModel.showsInspector = false
                }
            }
        )
    }

    private var sheetInspectorBinding: Binding<Bool> {
        Binding(
            get: {
                featureModel.showsInspector
                    && checkpointInspectorMode == .sheet
            },
            set: {
                if !$0 {
                    featureModel.showsInspector = false
                }
            }
        )
    }

    @ViewBuilder
    private func modelInspectorContent(
        _ inspectedCheckpointRow: ModelCheckpointRowPresentation?
    ) -> some View {
        if let inspectedCheckpointRow {
            ModelCheckpointInspectorSurface(
                row: inspectedCheckpointRow,
                isBusy: modelTransactionsAreBusy,
                disabledReason: modelTransactionDisabledReason,
                onVerify: verifyCheckpointArtifact,
                onReinstall: reinstallCheckpointArtifact,
                onReveal: revealCheckpointArtifact,
                onRemove: removeCheckpointArtifact,
                onInspectArtifact: { artifact in
                    inspectExactArtifact(artifact.id)
                }
            )
        } else {
            ModelCatalogInspectorView(
                presentation:
                    featureModel.inspectorController.presentation,
                localDetailsState:
                    featureModel.inspectorController.localDetailsState,
                verificationState:
                    featureModel.inspectorController.verificationState,
                onVerify: verifySelectedArtifact
            )
        }
    }

    private func standaloneInstalledSurface(
        _ rows: [ModelCatalogRowPresentation],
        in experience: ModelCatalogExperience
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Installed Models")
                .font(.headline)
            ForEach(rows) { row in
                catalogRow(
                    row,
                    context: nil,
                    onInspect: {
                        let selection =
                            ModelCatalogHierarchySelection
                            .exactArtifact(row.id)
                        featureModel.hierarchyState.select(selection)
                        featureModel.inspectorController.select(
                            selection,
                            in: experience
                        )
                        featureModel.showsInspector = true
                    }
                )
            }
        }
    }

    private var modelTransactionsAreBusy: Bool {
        activatingModelID != nil
            || isImporting
            || !services.dictation.allowsModelTransactions
    }

    private var modelTransactionDisabledReason: String? {
        guard !services.dictation.allowsModelTransactions else {
            return nil
        }
        return String(
            localized: "Finish Current Dictation before changing models."
        )
    }

    private func handleCatalogScreenCommand(
        _ command: ModelCatalogScreenCommand
    ) {
        switch command {
        case let .inspect(checkpointID):
            guard let row = richCheckpointRow(checkpointID) else {
                return
            }
            inspectCheckpoint(row)
        case let .selectArtifact(checkpointID, artifactID):
            guard screenRow(checkpointID)?.containsArtifact(artifactID)
                == true
            else {
                return
            }
            selectExactArtifactForInspector(artifactID)
            let rowID = ModelCatalogHierarchyRowID.checkpoint(
                checkpointID
            )
            featureModel.hierarchyState.focus(rowID)
            featureModel.hierarchyState.scroll(to: rowID)
        case let .inspectArtifact(artifactID):
            inspectExactArtifact(artifactID)
        case let .setVersionDisclosure(checkpointID, isExpanded):
            guard (screenRow(checkpointID)?.versionCount ?? 0) > 1 else {
                expandedCheckpointID = nil
                return
            }
            expandedCheckpointID =
                isExpanded ? checkpointID : nil
            let rowID = ModelCatalogHierarchyRowID.checkpoint(
                checkpointID
            )
            featureModel.hierarchyState.focus(rowID)
            featureModel.hierarchyState.scroll(to: rowID)
        case let .use(checkpointID, artifactID):
            useCheckpointArtifact(
                checkpointID: checkpointID,
                artifactID: artifactID
            )
        case let .installOnly(checkpointID, artifactID):
            chooseCheckpointArtifact(
                checkpointID: checkpointID,
                artifactID: artifactID
            )
            let isInstalled =
                exactArtifactPresentation(artifactID)?.row.isInstalled == true
            services.modelInstallCoordinator.start(
                modelID: artifactID,
                purpose: destination.purpose,
                action: isInstalled ? .reinstall : .install
            )
        case let .cancel(attemptID):
            services.modelInstallCoordinator.cancel(attemptID: attemptID)
        case let .retry(attemptID):
            services.modelInstallCoordinator.retry(attemptID: attemptID)
        case let .verify(artifactID):
            selectExactArtifactForInspector(artifactID)
            verifySelectedArtifact()
        case let .reveal(artifactID):
            guard let artifact = exactArtifactPresentation(artifactID) else {
                return
            }
            revealCheckpointArtifact(artifact)
        case let .remove(artifactID):
            guard selectedExactArtifactID == artifactID else {
                return
            }
            beginSelectedRemoval()
        }
    }

    private func inspectCheckpoint(
        _ row: ModelCheckpointRowPresentation
    ) {
        expandedCheckpointID = nil
        let selection = ModelCatalogHierarchySelection
            .checkpoint(row.checkpointID)
        featureModel.hierarchyState.select(selection)
        featureModel.inspectorController.select(
            selection,
            in: featureModel.snapshot?.experience
                ?? services.modelCatalogExperience(
                    for: destination.purpose,
                    query: catalogQuery
                )
        )
        checkpointInspectorMode = preferredInspectorMode
        featureModel.showsInspector = true
    }

    private func inspectExactArtifact(_ artifactID: String) {
        guard exactArtifactPresentation(artifactID) != nil else {
            return
        }
        expandedCheckpointID = nil
        selectExactArtifactForInspector(artifactID)
        checkpointInspectorMode = preferredInspectorMode
        featureModel.showsInspector = true
    }

    private func chooseCheckpointArtifact(
        _ row: ModelCheckpointRowPresentation,
        _ artifact: ModelCatalogExactArtifactPresentation
    ) {
        chooseCheckpointArtifact(
            checkpointID: row.checkpointID,
            artifactID: artifact.id,
            followsSignedRecommendation:
                row.checkpoint.metadata.recommendedArtifactID
                    == artifact.id
        )
    }

    private func chooseCheckpointArtifact(
        checkpointID: String,
        artifactID: String,
        followsSignedRecommendation: Bool? = nil
    ) {
        let recommendation =
            followsSignedRecommendation
            ?? screenRow(checkpointID)?.versionOptions.first {
                $0.id == artifactID
            }?.isRecommended
            ?? false
        services.setModelArtifactOverride(
            checkpointID: checkpointID,
            artifactID: artifactID,
            purpose: destination.purpose,
            followsSignedRecommendation: recommendation
        )
    }

    private func useCheckpointArtifact(
        _ row: ModelCheckpointRowPresentation,
        _ artifact: ModelCatalogExactArtifactPresentation
    ) {
        if destination == .transcription,
           let mismatch = row.languageMismatch(for: artifact) {
            pendingLanguageMismatchUse = ModelCheckpointPendingLanguageUse(
                checkpointID: row.checkpointID,
                artifactID: artifact.id,
                artifactName:
                    artifact.metadata.presentation.displayName,
                mismatch: mismatch
            )
            return
        }
        performCheckpointUse(
            checkpointID: row.checkpointID,
            artifactID: artifact.id
        )
    }

    private func useCheckpointArtifact(
        checkpointID: String,
        artifactID: String
    ) {
        guard let row = screenRow(checkpointID) else {
            return
        }
        if destination == .transcription,
           let mismatch = row.languageMismatch(
               forArtifactID: artifactID
           ) {
            let artifactName =
                row.versionOptions.first { $0.id == artifactID }?
                    .displayName
                ?? row.selectedArtifactName
            pendingLanguageMismatchUse = ModelCheckpointPendingLanguageUse(
                checkpointID: checkpointID,
                artifactID: artifactID,
                artifactName: artifactName,
                mismatch: mismatch
            )
            return
        }
        performCheckpointUse(
            checkpointID: checkpointID,
            artifactID: artifactID
        )
    }

    private func performCheckpointUse(
        checkpointID: String,
        artifactID: String
    ) {
        guard let artifact = exactArtifactPresentation(artifactID) else {
            return
        }
        chooseCheckpointArtifact(
            checkpointID: checkpointID,
            artifactID: artifactID
        )
        activatingModelID = artifactID
        Task {
            let result = await services.useModel(
                artifactID,
                purpose: destination.purpose
            )
            let message = result.message(for: artifact.row.model)
            if result == .installQueued {
                modelMessage = nil
            } else {
                modelMessage = message
            }
            activatingModelID = nil
            announce(message)
        }
    }

    private func screenRow(
        _ checkpointID: String
    ) -> ModelCatalogScreenRow? {
        featureModel.snapshot?.screenProjection.rows.first {
            $0.checkpointID == checkpointID
        }
    }

    private func exactArtifactPresentation(
        _ artifactID: String
    ) -> ModelCatalogExactArtifactPresentation? {
        featureModel.snapshot?.experience.exactArtifact(id: artifactID)
    }

    private func richCheckpointRow(
        _ checkpointID: String
    ) -> ModelCheckpointRowPresentation? {
        guard let experience = featureModel.snapshot?.experience else {
            return nil
        }
        return ModelCheckpointListPresentation(
            experience: experience,
            purpose: destination.purpose,
            selectedLanguage:
                destination == .transcription
                    ? services.preferences.transcriptionLanguage.rawValue
                    : nil,
            browseAllLanguages: featureModel.browseAllLanguages,
            searchText: featureModel.discoveryQuery.searchText,
            artifactOverrides:
                featureModel.snapshot?.overrideResolution
                .legalArtifactIDsByCheckpoint ?? [:],
            stableCheckpointOrder: featureModel.checkpointOrderIDs
        ).rows.first {
            $0.checkpointID == checkpointID
        }
    }

    private var checkpointOrderContext: ModelCheckpointOrderContext {
        ModelCheckpointOrderContext(
            language:
                destination == .transcription
                    ? services.preferences.transcriptionLanguage.rawValue
                    : nil,
            browsesAllLanguages: featureModel.browseAllLanguages,
            searchText: featureModel.discoveryQuery.searchText
        )
    }

    private var activeArtifactIDForDestination: String? {
        switch destination {
        case .transcription:
            services.preferences.activeModelID
        case .voiceCleaning:
            services.preferences.activeVoiceCleaningModelID
        }
    }

    private func verifyCheckpointArtifact(
        _ artifact: ModelCatalogExactArtifactPresentation
    ) {
        selectExactArtifactForInspector(artifact.id)
        verifySelectedArtifact()
    }

    private func reinstallCheckpointArtifact(
        _ artifact: ModelCatalogExactArtifactPresentation
    ) {
        services.modelInstallCoordinator.start(
            modelID: artifact.id,
            purpose: destination.purpose,
            action: .reinstall
        )
    }

    private func revealCheckpointArtifact(
        _ artifact: ModelCatalogExactArtifactPresentation
    ) {
        guard let path = artifact.row.installedRecord?
            .localFilesByManifestFilename.values.sorted().first
        else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: path),
        ])
    }

    private func removeCheckpointArtifact(
        _ artifact: ModelCatalogExactArtifactPresentation
    ) {
        selectExactArtifactForInspector(artifact.id)
        beginSelectedRemoval()
    }

    private func selectExactArtifactForInspector(_ artifactID: String) {
        let selection = ModelCatalogHierarchySelection
            .exactArtifact(artifactID)
        featureModel.hierarchyState.select(selection)
        if let checkpointID =
            featureModel.snapshot?.screenProjection.rows.first(
                where: { $0.containsArtifact(artifactID) }
            )?.checkpointID {
            let rowID = ModelCatalogHierarchyRowID.checkpoint(
                checkpointID
            )
            featureModel.hierarchyState.focus(rowID)
            featureModel.hierarchyState.scroll(to: rowID)
        }
        featureModel.inspectorController.select(
            selection,
            in: featureModel.snapshot?.experience
                ?? services.modelCatalogExperience(
                    for: destination.purpose,
                    query: catalogQuery
                )
        )
    }

    private func disableVoiceCleaning() {
        Task {
            let disabled = await services.disableVoiceCleaning()
            let message = disabled
                ? String(localized: "Voice cleaning is off.")
                : String(
                    localized:
                        "Wait for the current dictation to finish, then try again."
                )
            modelMessage = message
            announce(message)
        }
    }

    @ViewBuilder
    private func catalogStatus(hasRows: Bool) -> some View {
        let coordinator = services.modelCatalogCoordinator
        if let issue = coordinator.securityIssue {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bundled model list failed verification")
                        .font(.callout.weight(.semibold))
                    Text(
                        "Security check: \(issue.reason.displayName). "
                            + "Reinstall or update Textify."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            switch coordinator.status {
            case .checking where coordinator.manifest == nil:
                EmptyView()
            case .checking, .checkingForUpdates, .updateAvailable, .offline:
                EmptyView()
            case let .requiresNewerTextify(manifestVersion):
                Label(
                    "The bundled model list uses version \(manifestVersion) and requires a newer Textify.",
                    systemImage: "arrow.down.app"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            case .unavailable:
                if hasRows {
                    Text("Textify could not reverify its bundled model list.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .trusted, .securityFailure:
                EmptyView()
            }
        }
    }

    private var catalogQuery: ModelCatalogQuery {
        var query = featureModel.discoveryQuery
        query.purpose = destination.purpose
        if services.settingsRouter.modelReveal?.purpose == destination.purpose {
            query.revealedArtifactID = services.settingsRouter.modelReveal?.artifactID
        }
        return query
    }

    private func resetCatalogQuery() {
        featureModel.discoveryQuery.resetDiscovery()
        services.settingsRouter.dismissModelReveal()
    }

    private var viewportRestoration:
        ModelCatalogViewportRestoration? {
        featureModel.hierarchyState.scrollAnchorID.map {
            ModelCatalogViewportRestoration(
                generation: featureModel.viewportRestorationGeneration,
                rowID: $0
            )
        }
    }

    private func verifyInstalledModels() {
        Task {
            _ = await services.dictation.refreshReadiness()
            services.refreshModelStorageInventory()
            modelMessage = services.dictation.readiness.model.settingsModelStatus
        }
    }

    private func verifySelectedArtifact() {
        guard case let .exactArtifact(artifact) =
                featureModel.inspectorController.presentation
        else {
            return
        }
        let record = services.installedModelRecords.first {
            $0.model.id == artifact.id
        }
        featureModel.verificationRestorationIDsByArtifact[artifact.id] =
            record.map {
                services.pendingRestorationVerificationIDs(for: $0)
            } ?? []
        featureModel.inspectorController.verifySelectedArtifact()
    }

    private func catalogSurface(
        _ catalogExperience: ModelCatalogExperience,
        lifecyclePresentation: ModelCatalogPaneLifecyclePresentation
    ) -> some View {
        ModelCatalogSurface(
            rows: lifecyclePresentation.hasUsefulProjection
                ? catalogExperience.rows
                : [],
            sizeLabel: catalogExperience.sizeLabel,
            hierarchyRows: lifecyclePresentation.hasUsefulProjection
                ? featureModel.hierarchyState.visibleRows(in: catalogExperience)
                : [],
            accessibilityRows: lifecyclePresentation.hasUsefulProjection
                ? featureModel.hierarchyState.accessibilityRows(in: catalogExperience)
                : [],
            selection: featureModel.hierarchyState.selection,
            focusedRowID: $focusedCatalogRowID,
            accessibilityFocusedRowID: $accessibilityFocusedCatalogRowID,
            onSelect: { selection in
                featureModel.hierarchyState.select(selection)
                featureModel.inspectorController.select(selection, in: catalogExperience)
                featureModel.showsInspector = true
            },
            onToggleCheckpoint: { checkpoint in
                let previousScrollAnchorID =
                    featureModel.hierarchyState.scrollAnchorID
                featureModel.hierarchyState.toggleExpansion(of: checkpoint)
                requestCatalogScrollIfChanged(
                    from: previousScrollAnchorID
                )
                featureModel.inspectorController.select(
                    featureModel.hierarchyState.selection,
                    in: catalogExperience
                )
            },
            onReset: performEmptyStateAction,
            emptyPresentation: lifecyclePresentation
                .showsInitialLoadingPlaceholder
                ? .checking
                : emptyPresentation
        ) { row, context in
            catalogRow(
                row,
                context: context,
                onInspect: context == nil ? {
                    let selection = ModelCatalogHierarchySelection
                        .exactArtifact(row.id)
                    featureModel.hierarchyState.select(selection)
                    featureModel.inspectorController.select(
                        selection,
                        in: catalogExperience
                    )
                    featureModel.showsInspector = true
                } : nil
            )
        }
    }

    private func handleCheckpointKeyPress(
        _ keyPress: KeyPress,
        in presentation: ModelCatalogScreenProjection,
        catalogExperience: ModelCatalogExperience
    ) -> KeyPress.Result {
        let command: ModelCatalogKeyboardCommand?
        switch keyPress.key {
        case .upArrow:
            command = .moveUp
        case .downArrow:
            command = .moveDown
        case .pageUp:
            command = .pageUp
        case .pageDown:
            command = .pageDown
        case .home:
            command = .home
        case .end:
            command = .end
        case .return:
            command = .activate
        case .leftArrow:
            command = .collapse
        case .rightArrow:
            command = .expand
        case .delete where keyPress.modifiers.contains(.command):
            command = .deleteSelection
        default:
            command = nil
        }
        guard let command else {
            return .ignored
        }
        let disallowedModifiers: EventModifiers = [
            .command,
            .control,
            .option,
        ]
        if command != .deleteSelection,
           !keyPress.modifiers.intersection(disallowedModifiers).isEmpty {
            return .ignored
        }

        let effectiveFocusedCheckpointID =
            focusedCheckpointID ?? presentation.rows.first?.checkpointID
        let focusedRow = presentation.rows.first {
            $0.checkpointID == effectiveFocusedCheckpointID
        }
        let focusedInspectionArtifactID =
            focusedRow?.containsArtifact(selectedExactArtifactID) == true
            ? selectedExactArtifactID
            : nil
        let deletionArtifactID =
            ModelCheckpointDeletionPolicy.artifactID(
                explicitlySelectedArtifactID:
                    selectedExactArtifactID,
                focusedCheckpointID:
                    effectiveFocusedCheckpointID,
                candidates:
                    presentation.rows.flatMap(\.deletionCandidates)
            )
        let result = ModelCheckpointKeyboardNavigation.result(
            for: command,
            focusedCheckpointID: effectiveFocusedCheckpointID,
            checkpointIDs: presentation.rows.map(\.id),
            expandedCheckpointID: expandedCheckpointID,
            expandableCheckpointIDs: Set(
                presentation.rows.filter {
                    $0.versionCount > 1
                }.map(\.checkpointID)
            ),
            inspectionArtifactID: focusedInspectionArtifactID,
            deletionArtifactID: deletionArtifactID
        )
        switch result {
        case .ignored:
            return command == .deleteSelection ? .handled : .ignored
        case let .focus(id):
            let rowID = ModelCatalogHierarchyRowID.checkpoint(id)
            featureModel.hierarchyState.focus(rowID)
            featureModel.hierarchyState.scroll(to: rowID)
            featureModel.viewportRestorationGeneration &+= 1
            catalogHasKeyboardFocus = true
            let selection = ModelCatalogHierarchySelection.checkpoint(id)
            featureModel.hierarchyState.select(selection)
            featureModel.inspectorController.select(
                selection,
                in: catalogExperience
            )
        case let .inspect(id):
            handleCatalogScreenCommand(.inspect(checkpointID: id))
        case let .inspectArtifact(artifactID):
            handleCatalogScreenCommand(
                .inspectArtifact(artifactID: artifactID)
            )
        case let .expand(checkpointID):
            handleCatalogScreenCommand(
                .setVersionDisclosure(
                    checkpointID: checkpointID,
                    isExpanded: true
                )
            )
        case let .collapse(checkpointID):
            handleCatalogScreenCommand(
                .setVersionDisclosure(
                    checkpointID: checkpointID,
                    isExpanded: false
                )
            )
        case let .deleteArtifact(artifactID):
            handleCatalogScreenCommand(
                .remove(artifactID: artifactID)
            )
        }
        return .handled
    }

    private func handleModelsKeyPress(
        _ keyPress: KeyPress,
        checkpointPresentation: ModelCatalogScreenProjection,
        catalogExperience: ModelCatalogExperience
    ) -> KeyPress.Result {
        if destination == .transcription {
            return handleCheckpointKeyPress(
                keyPress,
                in: checkpointPresentation,
                catalogExperience: catalogExperience
            )
        }
        return handleCatalogKeyPress(
            keyPress,
            in: catalogExperience
        )
    }

    private func handleCatalogKeyPress(
        _ keyPress: KeyPress,
        in catalogExperience: ModelCatalogExperience
    ) -> KeyPress.Result {
        let command: ModelCatalogKeyboardCommand?
        switch keyPress.key {
        case .upArrow:
            command = .moveUp
        case .downArrow:
            command = .moveDown
        case .pageUp:
            command = .pageUp
        case .pageDown:
            command = .pageDown
        case .home:
            command = .home
        case .end:
            command = .end
        case .return:
            command = .activate
        case .leftArrow:
            command = .collapse
        case .rightArrow:
            command = .expand
        case .delete where keyPress.modifiers.contains(.command):
            command = .deleteSelection
        default:
            command = nil
        }
        guard let command else {
            return .ignored
        }
        let disallowedModifiers: EventModifiers = [
            .command,
            .control,
            .option,
        ]
        if command != .deleteSelection,
           !keyPress.modifiers.intersection(disallowedModifiers).isEmpty {
            return .ignored
        }

        let previousScrollAnchorID = featureModel.hierarchyState.scrollAnchorID
        let action = featureModel.hierarchyState.handleKeyboardCommand(
            command,
            in: catalogExperience
        )
        requestCatalogScrollIfChanged(from: previousScrollAnchorID)
        focusedCatalogRowID = featureModel.hierarchyState.focusedRowID
        switch action {
        case .none:
            break
        case let .selectionChanged(selection):
            featureModel.inspectorController.select(selection, in: catalogExperience)
            featureModel.showsInspector = true
        case .disclosureChanged:
            featureModel.inspectorController.select(
                featureModel.hierarchyState.selection,
                in: catalogExperience
            )
        case .requestDeletion:
            beginSelectedRemoval(in: catalogExperience)
        }
        return .handled
    }

    private func requestCatalogScrollIfChanged(
        from previousScrollAnchorID: ModelCatalogHierarchyRowID?
    ) {
        guard featureModel.hierarchyState.scrollAnchorID != nil,
              featureModel.hierarchyState.scrollAnchorID != previousScrollAnchorID
        else {
            return
        }
        featureModel.viewportRestorationGeneration &+= 1
    }

    private func announce(_ message: String) {
        ModelCatalogAccessibilityAnnouncer.post(message)
    }

    private var emptyPresentation: ModelCatalogEmptyPresentation {
        let coordinator = services.modelCatalogCoordinator
        if coordinator.manifest == nil {
            if coordinator.securityIssue != nil {
                return .securityFailure(destination)
            }
            switch coordinator.status {
            case .checking, .checkingForUpdates:
                return .checking
            case let .requiresNewerTextify(manifestVersion):
                return .requiresNewerTextify(
                    manifestVersion: manifestVersion
                )
            case .unavailable, .offline:
                return .unavailable(destination)
            case .trusted, .updateAvailable, .securityFailure:
                break
            }
        }
        if ProductionModelInstallConfiguration.current == nil,
           coordinator.manifest == nil {
            return .unavailable(destination)
        }
        if catalogQuery.emptyState == .validCatalog {
            return .purpose(destination)
        }
        return .query(catalogQuery.emptyState)
    }

    private func performEmptyStateAction() {
        switch emptyPresentation {
        case let .query(state):
            switch state {
            case .installed:
                featureModel.discoveryQuery.scope = .all
                if featureModel.discoveryQuery.sort == .installedSize {
                    featureModel.discoveryQuery.sort = .catalog
                }
            case .search:
                featureModel.discoveryQuery.clearSearch()
            case .filters:
                featureModel.discoveryQuery.clearFilters()
            case .combined:
                featureModel.discoveryQuery.clearSearch()
                featureModel.discoveryQuery.clearFilters()
            case .validCatalog:
                break
            }
        case .purpose, .unavailable, .securityFailure:
            break
        case .checking, .requiresNewerTextify:
            break
        }
    }

    @ViewBuilder
    private func pinnedRevealView(
        _ reveal: ModelCatalogPinnedRevealPresentation,
        in catalogExperience: ModelCatalogExperience
    ) -> some View {
        switch reveal {
        case let .catalogArtifact(family, checkpoint, artifact):
            pinnedRevealCard(
                rowID: .exactArtifact(artifact.id),
                title: "\(family.metadata.presentation.displayName) → "
                    + "\(checkpoint.metadata.presentation.displayName) → "
                    + artifact.metadata.presentation.displayName
            ) {
                catalogRow(
                    artifact.row,
                    context: ModelCatalogArtifactRowContext(
                        title: artifact.metadata.presentation.displayName,
                        description: checkpoint.metadata.presentation.description,
                        variantLabel: nil,
                        isRecommended: checkpoint
                            .presentsRecommendation(artifact),
                        isFallback: checkpoint.presentsFallback(artifact),
                        isSelected: featureModel.hierarchyState.selection
                            == .exactArtifact(artifact.id),
                        indentation: 0,
                        comparison: nil,
                        onSelect: {
                            let selection = ModelCatalogHierarchySelection
                                .exactArtifact(artifact.id)
                            featureModel.hierarchyState.select(selection)
                            featureModel.inspectorController.select(
                                selection,
                                in: catalogExperience
                            )
                            featureModel.showsInspector = true
                        }
                    )
                )
            }
        case let .standaloneArtifact(row):
            pinnedRevealCard(
                rowID: .standaloneArtifact(row.id),
                title: "\(row.model.displayName) (\(row.id))"
            ) {
                catalogRow(
                    row,
                    context: nil,
                    onInspect: {
                        let selection = ModelCatalogHierarchySelection
                            .exactArtifact(row.id)
                        featureModel.hierarchyState.select(selection)
                        featureModel.inspectorController.select(
                            selection,
                            in: catalogExperience
                        )
                        featureModel.showsInspector = true
                    }
                )
            }
        case let .unavailableArtifact(artifactID):
            pinnedRevealCard(
                rowID: .standaloneArtifact(artifactID),
                title: artifactID
            ) {
                Label(
                    "This Exact Artifact is no longer in the signed catalog and is not installed on this Mac.",
                    systemImage: "questionmark.folder"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func pinnedRevealCard<Content: View>(
        rowID: ModelCatalogHierarchyRowID,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(TextifyVisualIdentity.voiceViolet)

                VStack(alignment: .leading, spacing: 2) {
                    Text("REVEALED EXACT ARTIFACT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button("Back to Filtered Results") {
                    services.settingsRouter.dismissModelReveal()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    services.settingsRouter.dismissModelReveal()
                } label: {
                    Label("Dismiss Reveal", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Dismiss Reveal")
            }
            .padding(12)

            Divider()

            content()
        }
        .background(TextifyVisualIdentity.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    TextifyVisualIdentity.voiceViolet.opacity(0.65),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned Exact Artifact reveal")
        .accessibilityValue(title)
        .accessibilityIdentifier("model-catalog-pinned-reveal")
        .focusable()
        .focused($focusedCatalogRowID, equals: rowID)
        .accessibilityFocused(
            $accessibilityFocusedCatalogRowID,
            equals: rowID
        )
    }

    @ViewBuilder
    private func catalogRow(
        _ row: ModelCatalogRowPresentation,
        context: ModelCatalogArtifactRowContext?,
        onInspect: (() -> Void)? = nil
    ) -> some View {
        let onUse: () -> Void = {
            activatingModelID = row.id
            Task {
                let result = await services.activateInstalledModel(row.id)
                let message = result.message(for: row.model)
                modelMessage = message
                activatingModelID = nil
                announce(message)
            }
        }
        let onDisable: () -> Void = {
            Task {
                let disabled = await services.disableVoiceCleaning()
                let message = disabled
                    ? "Voice cleaning is off."
                    : "Wait for the current dictation to finish, then try again."
                modelMessage = message
                announce(message)
            }
        }
        let onInstall: () -> Void = {
            services.modelInstallCoordinator.start(
                modelID: row.id,
                purpose: row.model.purpose,
                action: row.isInstalled ? .reinstall : .install
            )
        }
        let onCancelInstall: () -> Void = {
            guard let attemptID = row.install?.state.attemptID else {
                return
            }
            services.modelInstallCoordinator.cancel(attemptID: attemptID)
        }
        let onRetryInstall: () -> Void = {
            guard let attemptID = row.install?.state.attemptID else {
                return
            }
            services.modelInstallCoordinator.retry(attemptID: attemptID)
        }
        let onDelete: () -> Void = {
            featureModel.hierarchyState.select(.exactArtifact(row.id))
            beginSelectedRemoval()
        }
        let visibleActions = row.visibleActions(
            for: featureModel.hierarchyState.selection
        )

        if let context, let comparison = context.comparison {
            ModelCatalogVariantComparisonRow(
                model: row.model,
                presentation: comparison,
                isSelected: context.isSelected,
                isActivating: activatingModelID == row.id,
                isBusy: activatingModelID != nil
                    || isImporting
                    || !services.dictation.allowsModelTransactions,
                install: row.install,
                actions: visibleActions,
                onSelect: context.onSelect,
                onUse: onUse,
                onDisable: onDisable,
                onInstall: onInstall,
                onCancelInstall: onCancelInstall,
                onRetryInstall: onRetryInstall,
                onDelete: onDelete
            )
        } else {
            TextifyModelCard(
                model: row.model,
                sizeLabel: row.sizeLabel,
                sizeDescription: row.sizeDescription,
                hierarchyContext: context,
                compatibility: row.compatibility,
                placement: row.placement,
                isRevoked: row.isRevoked,
                isInstalled: row.isInstalled,
                isActive: row.isActive,
                isActivating: activatingModelID == row.id,
                isBusy: activatingModelID != nil
                    || isImporting
                    || !services.dictation.allowsModelTransactions,
                install: row.install,
                actions: visibleActions,
                onUse: onUse,
                onDisable: onDisable,
                onInstall: onInstall,
                onCancelInstall: onCancelInstall,
                onRetryInstall: onRetryInstall,
                onDelete: onDelete,
                onInspect: onInspect
            )
        }
    }

    private func beginSelectedRemoval(
        in experience: ModelCatalogExperience? = nil
    ) {
        let experience = experience ?? services.modelCatalogExperience(
            for: destination.purpose,
            query: catalogQuery
        )
        pendingRemoval = experience.removalConfirmation(
            for: featureModel.hierarchyState.selection
        )
    }

    func resolveRemoval(
        _ confirmation: ModelRemovalConfirmationPresentation,
        confirmed: Bool
    ) {
        pendingRemoval = nil
        guard confirmed else {
            return
        }
        Task {
            do {
                try await services.removeInstalledModel(
                    confirmation.artifactID,
                    activeResolution:
                        confirmation.activeResolution
                )
                let message =
                    "\(confirmation.exactArtifactName) was deleted."
                modelMessage = message
                announce(message)
            } catch {
                let message = error.localizedDescription
                modelMessage = message
                announce(message)
            }
        }
    }

    private func chooseCustomWhisperModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a Whisper-compatible GGML or GGUF model file."
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        pendingImportURL = url
        showsImportConfirmation = true
    }

    private func importPendingWhisperModel() {
        guard let url = pendingImportURL else {
            return
        }
        pendingImportURL = nil
        isImporting = true
        let didAccess = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                isImporting = false
            }
            do {
                let name = url.deletingPathExtension().lastPathComponent
                let model = try await services.importCustomWhisperModel(
                    from: url,
                    displayName: name.isEmpty ? "Imported Whisper Model" : name
                )
                modelMessage = "\(model.displayName) was validated, imported, and is ready."
            } catch {
                modelMessage = "Import failed: \(String(describing: error))"
            }
        }
    }
}

@MainActor
private enum ModelCatalogAccessibilityAnnouncer {
    static func post(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSNumber(
                    value: NSAccessibilityPriorityLevel.medium.rawValue
                ),
            ]
        )
    }
}

private struct VoiceCleaningDeck: View {
    let model: ProductionModelPresentation?
    let status: VoiceCleaningRuntimeStatus
    let onDisable: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.minus")
                .font(.title2)
                .foregroundStyle(statusTone)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("VOICE CLEANING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                Text(model?.displayName ?? "Off")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(statusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextifyStatusBadge(title: statusTitle, tone: statusBadgeTone)
            if model != nil {
                Button("Disable", action: onDisable)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private var statusTitle: String {
        switch status {
        case .disabled: "OFF"
        case .preparing: "PREPARING"
        case .ready: "ENABLED"
        case .warning: "RAW FALLBACK"
        }
    }

    private var statusDetail: String {
        switch status {
        case .disabled:
            "Install and enable a MossFormer2 model to reduce background noise before ASR."
        case .preparing:
            "Loading the local MLX cleaner on Metal."
        case .ready:
            "Recorded audio is cleaned locally before it reaches the dictation model."
        case .warning:
            "Cleaning was unavailable, so Textify continued with the original audio."
        }
    }

    private var statusTone: Color {
        switch status {
        case .ready: TextifyVisualIdentity.readyMint
        case .warning: TextifyVisualIdentity.recordCoral
        case .disabled, .preparing: TextifyVisualIdentity.voiceViolet
        }
    }

    private var statusBadgeTone: TextifyStatusBadge.Tone {
        switch status {
        case .ready: .success
        case .warning: .warning
        case .disabled, .preparing: .neutral
        }
    }
}

private struct ModelCommandDeck: View {
    let model: ProductionModelPresentation?
    let readiness: RuntimeModelReadiness
    let catalogCount: Int
    let installedCount: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(statusColor.opacity(0.15))
                TextifyVoiceMark(
                    state: readiness.isReady ? .ready : .processing,
                    height: 30,
                    animated: readiness.isPreparing
                )
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("ACTIVE SIGNAL PATH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.05)
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                }
                Text(model?.displayName ?? "Choose a local model")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Text(model.map { "\($0.engineName) • \($0.acceleratorName)" }
                    ?? "Install a signed model to start dictating.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 18) {
                ModelDeckFact(value: "\(catalogCount)", label: "LOCAL")
                ModelDeckFact(value: "\(installedCount)", label: "INSTALLED")
            }

            TextifyStatusBadge(
                title: readiness.settingsModelStatus.uppercased(),
                tone: readiness.isReady ? .success : .warning
            )
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    LinearGradient(
                        colors: [
                            TextifyVisualIdentity.voiceViolet.opacity(colorScheme == .dark ? 0.16 : 0.09),
                            TextifyVisualIdentity.readyMint.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
        }
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [TextifyVisualIdentity.voiceViolet, statusColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 46)
                .padding(.leading, 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        readiness.isReady ? TextifyVisualIdentity.readyMint : TextifyVisualIdentity.voiceViolet
    }
}

private struct ModelDeckFact: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ModelDownloadsPopover: View {
    @Environment(AppServices.self) private var services
    let onDismiss: () -> Void

    var body: some View {
        let presentation = ModelDownloadsPresentation(
            attempts: services.modelInstallCoordinator.attempts
        )

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Downloads")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Installations run one at a time in authorization order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                if presentation.nonterminalCount > 0 {
                    Text("\(presentation.nonterminalCount) pending")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                }
            }
            .padding(16)

            Divider()

            if presentation.active.isEmpty,
               presentation.pending.isEmpty,
               presentation.history.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text(
                        "Authorized model installations and their history appear here."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 230)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("No Downloads")
                .accessibilityValue(
                    "Authorized model installations and their history appear here."
                )
                .accessibilityIdentifier("model-downloads-empty-state")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        downloadsSection(
                            "Active",
                            rows: presentation.active
                        )
                        downloadsSection(
                            "Queue",
                            rows: presentation.pending
                        )
                        downloadsSection(
                            "History",
                            rows: Array(presentation.history.reversed())
                        )
                    }
                    .padding(16)
                }
            }

            if let persistenceErrorMessage =
                services.modelInstallCoordinator.persistenceErrorMessage {
                Divider()
                Label(
                    persistenceErrorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(TextifyVisualIdentity.warmWarning)
                .padding(12)
            }
        }
        .frame(
            minWidth: 390,
            idealWidth: 420,
            maxWidth: 520,
            minHeight: 420,
            idealHeight: 480,
            maxHeight: 620
        )
        .background(TextifyVisualIdentity.windowSurface)
    }

    @ViewBuilder
    private func downloadsSection(
        _ title: String,
        rows: [ModelDownloadAttemptPresentation]
    ) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.tertiary)

                ForEach(rows) { row in
                    ModelDownloadAttemptRow(
                        row: row,
                        onReveal: {
                            services.settingsRouter.revealModelArtifact(
                                id: row.revealRequest.artifactID,
                                purpose: row.revealRequest.purpose
                            )
                            onDismiss()
                        },
                        onPause: {
                            services.modelInstallCoordinator.pause(
                                attemptID: row.id
                            )
                        },
                        onResume: {
                            services.modelInstallCoordinator.resume(
                                attemptID: row.id
                            )
                        },
                        onCancel: {
                            services.modelInstallCoordinator.cancel(
                                attemptID: row.id
                            )
                        },
                        onRetry: {
                            services.modelInstallCoordinator.retry(
                                attemptID: row.id
                            )
                        },
                        onRemoveRetainedData: {
                            services.modelInstallCoordinator
                                .removeRetainedData(attemptID: row.id)
                        }
                    )
                }
            }
        }
    }
}

private struct ModelDownloadAttemptRow: View {
    let row: ModelDownloadAttemptPresentation
    let onReveal: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemoveRetainedData: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.artifactID)
                        .font(.callout.weight(.semibold))
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.statusTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 8)

                Text(row.attempt.action == .reinstall ? "Reinstall" : "Install")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if row.state.totalBytes > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: row.progressValue, total: 1)
                        .tint(statusColor)
                        .accessibilityLabel(row.statusTitle)
                        .accessibilityValue(row.accessibilityValue)
                    if let percentText = row.percentText {
                        Text(percentText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(row.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Show in Catalog", action: onReveal)
                        downloadAttemptActions
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            Button("Show in Catalog", action: onReveal)
                            Spacer(minLength: 0)
                            downloadAttemptActions
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Show in Catalog", action: onReveal)
                            downloadAttemptActions
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            reduceTransparency
                ? TextifyVisualIdentity.raisedSurface
                : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    colorSchemeContrast == .increased
                        ? Color.primary.opacity(0.7)
                        : TextifyVisualIdentity.separator,
                    lineWidth:
                        colorSchemeContrast == .increased ? 2 : 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.artifactID)
        .accessibilityValue(row.accessibilityValue)
        .accessibilityIdentifier("model-download-\(row.id)")
    }

    @ViewBuilder
    private var downloadAttemptActions: some View {
        HStack(spacing: 12) {
            if row.canPause {
                Button("Pause", action: onPause)
            }
            if row.canResume {
                Button("Resume", action: onResume)
            }
            if row.canRetry {
                Button("Retry", action: onRetry)
            }
            if row.canCancel {
                Button("Cancel", role: .destructive, action: onCancel)
            }
            if row.canRemoveRetainedData {
                Button(
                    "Remove Data",
                    role: .destructive,
                    action: onRemoveRetainedData
                )
            }
        }
    }

    private var statusImage: String {
        switch row.state.phase {
        case .queued:
            return "clock"
        case .paused:
            return "pause.circle.fill"
        case .waitingForNetwork:
            return "wifi.exclamationmark"
        case .waitingForCatalogCheck:
            return "checkmark.seal"
        case .checkingSpace, .downloading, .verifying, .installing:
            return "arrow.down.circle.fill"
        case .installed:
            return "checkmark.circle.fill"
        case .interrupted, .failed:
            return "exclamationmark.circle.fill"
        case .cancelled:
            return "xmark.circle"
        case .revoked:
            return "hand.raised.circle.fill"
        }
    }

    private var statusColor: Color {
        switch row.state.phase {
        case .installed:
            return TextifyVisualIdentity.readyMint
        case .interrupted, .failed, .revoked:
            return TextifyVisualIdentity.warmWarning
        case .cancelled:
            return .secondary
        case .queued, .paused, .waitingForNetwork, .waitingForCatalogCheck,
             .checkingSpace, .downloading, .verifying, .installing:
            return TextifyVisualIdentity.voiceViolet
        }
    }
}

private struct ModelCatalogToolbar: View {
    @Binding var query: ModelCatalogQuery
    @Binding var showsDownloads: Bool
    let filterOptions: ModelCatalogFilterOptions
    let onReset: () -> Void
    let onVerify: () -> Void
    let onImport: (() -> Void)?
    let onShowVariantHelp: () -> Void
    let downloadCount: Int
    let isImportDisabled: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                compactToolbar
            } else {
                ViewThatFits(in: .horizontal) {
                    wideToolbar
                    compactToolbar
                }
            }
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
    }

    private var wideToolbar: some View {
        HStack(spacing: 10) {
            scopePicker
            searchField
            sortMenu
            filterMenu
            Spacer(minLength: 0)
            downloadsButton
            overflowMenu
        }
    }

    private var compactToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                scopePicker
                searchField
            }
            HStack(spacing: 10) {
                sortMenu
                filterMenu
                Spacer(minLength: 0)
                downloadsButton
                overflowMenu
            }
        }
    }

    private var scopePicker: some View {
        Picker("Catalog scope", selection: scopeBinding) {
            ForEach(ModelCatalogScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 150, idealWidth: 180)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search models", text: $query.searchText)
                .textFieldStyle(.plain)
            if query.hasSearch {
                Button {
                    query.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 180, idealWidth: 280)
        .frame(minHeight: 28)
        .background(
            reduceTransparency
                ? TextifyVisualIdentity.raisedSurface
                : Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    colorSchemeContrast == .increased
                        ? Color.primary.opacity(0.7)
                        : TextifyVisualIdentity.separator,
                    lineWidth:
                        colorSchemeContrast == .increased ? 2 : 1
                )
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort models", selection: $query.sort) {
                ForEach(query.availableSorts) { option in
                    Text(option.title).tag(option)
                }
            }
            if query.sort != .catalog {
                Divider()
                Picker("Direction", selection: $query.sortDirection) {
                    ForEach(ModelCatalogSortDirection.allCases) { direction in
                        Label(
                            direction.title,
                            systemImage: direction.systemImage
                        )
                        .tag(direction)
                    }
                }
            }
        } label: {
            Label(
                query.sort.title,
                systemImage: query.sort == .catalog
                    ? "arrow.up.arrow.down"
                    : query.sortDirection.systemImage
            )
        }
        .fixedSize()
    }

    private var filterMenu: some View {
        Menu {
            Menu("Compatibility") {
                ForEach(ModelCatalogCompatibilityFilter.allCases) { value in
                    filterButton(
                        value,
                        at: \.compatibility,
                        title: value.title
                    )
                }
            }
            Menu("State") {
                ForEach(ModelCatalogStateFilter.allCases) { value in
                    filterButton(value, at: \.states, title: value.title)
                }
            }
            Menu("Artifact Format") {
                ForEach(
                    filterOptions.artifactFormats,
                    id: \.rawValue
                ) { value in
                    filterButton(
                        value,
                        at: \.artifactFormats,
                        title:
                            ModelCatalogVariantTerminology
                                .artifactFormat(value)
                    )
                }
            }
            Menu("Numeric Format") {
                ForEach(
                    filterOptions.numericFormats,
                    id: \.rawValue
                ) { value in
                    filterButton(
                        value,
                        at: \.numericFormats,
                        title: value.rawValue
                    )
                }
            }
            Menu("Runtime") {
                ForEach(filterOptions.runtimes, id: \.rawValue) { value in
                    filterButton(
                        value,
                        at: \.runtimes,
                        title:
                            ModelCatalogVariantTerminology.runtime(value)
                    )
                }
            }
            Menu("Compute Route") {
                ForEach(
                    filterOptions.computeRoutes,
                    id: \.rawValue
                ) { value in
                    filterButton(
                        value,
                        at: \.computeRoutes,
                        title:
                            ModelCatalogVariantTerminology
                                .computeRoute(value)
                    )
                }
            }
            Menu("Language") {
                ForEach(filterOptions.languages, id: \.self) { value in
                    filterButton(
                        value,
                        at: \.languages,
                        title: ModelCatalogQuery.languageName(value)
                    )
                }
            }
            Menu("Evidence") {
                ForEach(ModelCatalogEvidenceFilter.allCases) { value in
                    filterButton(
                        value,
                        at: \.evidence,
                        title: value.title
                    )
                }
            }
            if query.hasAppliedFilters {
                Divider()
                Button(
                    "Clear Filters",
                    systemImage: "line.3.horizontal.decrease.circle"
                ) {
                    query.clearFilters()
                }
            }
        } label: {
            Label(
                query.hasAppliedFilters
                    ? "Filters (\(query.appliedFilterTokens.count))"
                    : "Filters",
                systemImage: query.hasAppliedFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .fixedSize()
    }

    private var downloadsButton: some View {
        Button {
            showsDownloads = true
        } label: {
            HStack(spacing: 5) {
                Image(
                    systemName: downloadCount > 0
                        ? "arrow.down.circle.fill"
                        : "arrow.down.circle"
                )
                Text("Downloads")
                if downloadCount > 0 {
                    Text("\(downloadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(
                            TextifyVisualIdentity.voiceViolet,
                            in: Capsule()
                        )
                }
            }
        }
        .fixedSize()
        .accessibilityLabel(
            downloadCount == 0
                ? "Downloads"
                : "Downloads, \(downloadCount) pending"
        )
        .popover(isPresented: $showsDownloads) {
            ModelDownloadsPopover {
                showsDownloads = false
            }
        }
    }

    private var overflowMenu: some View {
        Menu {
            if hasChanges {
                Button(
                    "Reset Catalog View",
                    systemImage: "arrow.counterclockwise",
                    action: onReset
                )
            }
            Divider()
            Button(
                "About Model Variants…",
                systemImage: "questionmark.circle",
                action: onShowVariantHelp
            )
            Button(
                "Verify Installed",
                systemImage: "checkmark.seal",
                action: onVerify
            )
            if let onImport {
                Button(
                    "Import Whisper Model…",
                    systemImage: "square.and.arrow.down",
                    action: onImport
                )
                .disabled(isImportDisabled)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .frame(minWidth: 24)
        .accessibilityLabel("More catalog actions")
    }

    private var scopeBinding: Binding<ModelCatalogScope> {
        Binding(
            get: { query.scope },
            set: { scope in
                query.scope = scope
                if scope == .all, query.sort == .installedSize {
                    query.sort = .catalog
                }
            }
        )
    }

    private var hasChanges: Bool {
        query.scope != .all
            || query.hasSearch
            || query.hasAppliedFilters
            || query.sort != .catalog
    }

    private func filterButton<Value: Equatable>(
        _ value: Value,
        at keyPath: WritableKeyPath<ModelCatalogQuery, [Value]>,
        title: String
    ) -> some View {
        let isSelected = query[keyPath: keyPath].contains(value)
        return Button {
            if isSelected {
                query[keyPath: keyPath].removeAll { $0 == value }
            } else {
                query[keyPath: keyPath].append(value)
            }
        } label: {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

private struct ModelCatalogFilterTokens: View {
    let tokens: [ModelCatalogFilterToken]
    let onRemove: (ModelCatalogFilterToken) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("FILTERED BY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)

                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    Button {
                        onRemove(token)
                    } label: {
                        HStack(spacing: 5) {
                            Text(token.title)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            TextifyVisualIdentity.voiceViolet.opacity(0.14),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    TextifyVisualIdentity.voiceViolet.opacity(0.36),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(token.title) filter")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ModelCatalogStorageSummaryView: View {
    let presentation: ModelCatalogStorageSummaryPresentation

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    private let columns = [
        GridItem(.adaptive(minimum: 150), alignment: .topLeading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(
                Array(presentation.facts.enumerated()),
                id: \.offset
            ) { _, fact in
                VStack(alignment: .leading, spacing: 3) {
                    Text(fact.label.uppercased())
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(.tertiary)
                    Text(fact.value)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .background(
            reduceTransparency
                ? TextifyVisualIdentity.cardSurface
                : Color.primary.opacity(0.035)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ModelCatalogArtifactRowContext {
    let title: String
    let description: String
    let variantLabel: String?
    let isRecommended: Bool
    let isFallback: Bool
    let isSelected: Bool
    let indentation: CGFloat
    let comparison: ModelCatalogVariantComparisonPresentation?
    let onSelect: () -> Void
}

private struct ModelCatalogInspectorView: View {
    let presentation: ModelCatalogInspectorPresentation?
    let localDetailsState: ModelCatalogInspectorLocalDetailsState
    let verificationState: ModelCatalogInspectorVerificationState
    let onVerify: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(.secondary)

            switch presentation {
            case let .checkpoint(checkpoint):
                checkpointInspector(checkpoint)
            case let .exactArtifact(artifact):
                exactArtifactInspector(artifact)
            case nil:
                ContentUnavailableView {
                    Label("Nothing Selected", systemImage: "sidebar.right")
                } description: {
                    Text("Select a checkpoint or exact artifact to inspect its details.")
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TextifyVisualIdentity.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func checkpointInspector(
        _ checkpoint: ModelCatalogCheckpointInspectorPresentation
    ) -> some View {
        inspectorHeader(
            eyebrow: "CHECKPOINT",
            title: checkpoint.displayName,
            identity: checkpoint.id,
            description: checkpoint.description
        )

        ModelInspectorSection(title: "Reference Variant") {
            ModelInspectorFactRow(
                label: "Variant",
                value: checkpoint.referenceArtifactName
            )
            ModelInspectorFactRow(
                label: "Quality",
                value: checkpoint.referenceQuality
            )
            ModelInspectorFactRow(
                label: "Speed",
                value: checkpoint.referenceSpeed
            )
            ModelInspectorFactRow(
                label: "Quality Evidence",
                value: checkpoint.referenceQualityEvidence
            )
            ModelInspectorFactRow(
                label: "Speed Evidence",
                value: checkpoint.referenceSpeedEvidence
            )
            ModelInspectorFactRow(
                label: "Compatibility",
                value: checkpoint.referenceCompatibility
            )
            ModelInspectorFactRow(
                label: "Compatibility Detail",
                value: checkpoint.referenceCompatibilityExplanation
            )
            if let artifactName = checkpoint.defaultInstallArtifactName,
               let artifactID = checkpoint.defaultInstallArtifactID {
                ModelInspectorFactRow(
                    label: artifactID == checkpoint.referenceArtifactID
                        ? "Default Install"
                        : "Signed Fallback",
                    value: "\(artifactName) (\(artifactID))"
                )
            }
        }

        ModelInspectorSection(title: "Aggregate State") {
            ModelInspectorFactRow(label: "Variants", value: checkpoint.aggregateState)
            ModelInspectorFactRow(label: "Languages", value: checkpoint.languages)
            ModelInspectorFactRow(label: "Capabilities", value: checkpoint.capabilities)
        }
    }

    @ViewBuilder
    private func exactArtifactInspector(
        _ artifact: ModelCatalogExactArtifactInspectorPresentation
    ) -> some View {
        inspectorHeader(
            eyebrow: "EXACT ARTIFACT",
            title: "\(artifact.checkpointName) — \(artifact.displayName)",
            identity: artifact.id,
            description: artifact.description
        )

        ModelInspectorSection(title: "Operational Truth") {
            ModelInspectorFactRow(label: "Artifact Format", value: artifact.artifactFormat)
            ModelInspectorFactRow(label: "Numeric Format", value: artifact.numericFormat)
            ModelInspectorFactRow(label: "Runtime", value: artifact.runtime)
            ModelInspectorFactRow(label: "Compute Route", value: artifact.computeRoute)
            ModelInspectorFactRow(label: "Compatibility", value: artifact.compatibilityStatus)
            ModelInspectorFactRow(
                label: "Compatibility Detail",
                value: artifact.compatibilityExplanation
            )
            ModelInspectorFactRow(label: "Requirements", value: artifact.compatibility)
            ModelInspectorFactRow(label: "Download Size", value: artifact.transferSize)
            ModelInspectorFactRow(label: "Local State", value: artifact.localState)
        }

        ModelInspectorSection(title: "Signed Evidence") {
            ModelInspectorFactRow(label: "Quality", value: artifact.qualityEvidence)
            ModelInspectorFactRow(label: "Speed", value: artifact.speedEvidence)
        }

        ModelInspectorSection(title: "Source & License") {
            ModelInspectorFactRow(label: "Provenance", value: artifact.provenance)
                .textSelection(.enabled)
            ModelInspectorFactRow(label: "License", value: artifact.license)
            if let sourceAndLicense = artifact.sourceAndLicense {
                ModelSourceLicenseButton(presentation: sourceAndLicense)
            }
            if let sourceURL = artifact.sourceURL {
                Link(destination: sourceURL) {
                    Label("Open Upstream Source", systemImage: "arrow.up.right.square")
                }
                .font(.callout)
            }
        }

        ModelInspectorSection(title: "Local Files") {
            localDetails(for: artifact)
            if artifact.canVerify {
                Button(
                    verificationState == .verifying(artifactID: artifact.id)
                        ? "Verifying…"
                        : "Verify Integrity",
                    systemImage: "checkmark.seal",
                    action: onVerify
                )
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        verificationState == .verifying(artifactID: artifact.id)
                    )
                    .help("Hash installed model files only when you request verification.")
            }
        }
    }

    private func inspectorHeader(
        eyebrow: String,
        title: String,
        identity: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(TextifyVisualIdentity.voiceViolet)
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text(identity)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func localDetails(
        for artifact: ModelCatalogExactArtifactInspectorPresentation
    ) -> some View {
        switch localDetailsState {
        case let .loading(artifactID) where artifactID == artifact.id:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Calculating local file details…")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
        case let .loaded(details) where details.artifactID == artifact.id:
            ModelInspectorFactRow(
                label: "On Disk",
                value: details.allocatedBytes.map {
                    "About "
                        + ByteCountFormatter.string(
                            fromByteCount: $0,
                            countStyle: .file
                        )
                } ?? "Size Unavailable"
            )
            ModelInspectorFactRow(
                label: "Files",
                value: "\(details.presentFileCount) of \(details.expectedFileCount) present"
            )
            ModelInspectorFactRow(
                label: "Integrity",
                value: integrityDescription(
                    for: artifact,
                    localDetails: details
                )
            )
            if !details.missingRelativePaths.isEmpty {
                ModelInspectorFactRow(
                    label: "Missing",
                    value: details.missingRelativePaths.joined(separator: ", ")
                )
            }
            if !details.sizeMismatchRelativePaths.isEmpty {
                ModelInspectorFactRow(
                    label: "Unexpected Size",
                    value: details.sizeMismatchRelativePaths.joined(separator: ", ")
                )
            }
            if details.unexpectedFileCount > 0 {
                ModelInspectorFactRow(
                    label: "Unexpected Files",
                    value: String(details.unexpectedFileCount)
                )
            }
        case let .failed(artifactID) where artifactID == artifact.id:
            ModelInspectorFactRow(
                label: "On Disk",
                value: "Size Unavailable"
            )
        case .notApplicable, .loading, .loaded, .failed:
            Text(
                artifact.canVerify
                    ? "Local details have not been loaded."
                    : "Install this exact artifact to inspect local files."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func integrityDescription(
        for artifact: ModelCatalogExactArtifactInspectorPresentation,
        localDetails: ModelCatalogArtifactLocalDetails
    ) -> String {
        switch verificationState {
        case let .verified(artifactID) where artifactID == artifact.id:
            return "Verified"
        case let .failed(artifactID) where artifactID == artifact.id:
            return "Verification failed"
        case let .verifying(artifactID) where artifactID == artifact.id:
            return "Verifying…"
        case .unavailable, .available, .verifying, .verified, .failed:
            return localDetails.integrity == .notVerified
                ? "Not re-verified — use Verify Integrity to hash files"
                : "Needs attention"
        }
    }
}

private struct ModelInspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.55)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct ModelInspectorFactRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ModelCatalogSurface<Row: View>: View {
    let rows: [ModelCatalogRowPresentation]
    let sizeLabel: String
    let hierarchyRows: [ModelCatalogHierarchyRow]
    let accessibilityRows: [ModelCatalogAccessibilityRow]
    let selection: ModelCatalogHierarchySelection?
    let focusedRowID: FocusState<ModelCatalogHierarchyRowID?>.Binding
    let accessibilityFocusedRowID:
        AccessibilityFocusState<ModelCatalogHierarchyRowID?>.Binding
    let onSelect: (ModelCatalogHierarchySelection) -> Void
    let onToggleCheckpoint: (ModelCatalogCheckpointPresentation) -> Void
    let onReset: () -> Void
    let emptyPresentation: ModelCatalogEmptyPresentation
    let row: (ModelCatalogRowPresentation, ModelCatalogArtifactRowContext?) -> Row

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var hasEmittedFirstUsefulRow = false

    init(
        rows: [ModelCatalogRowPresentation],
        sizeLabel: String,
        hierarchyRows: [ModelCatalogHierarchyRow],
        accessibilityRows: [ModelCatalogAccessibilityRow],
        selection: ModelCatalogHierarchySelection?,
        focusedRowID: FocusState<ModelCatalogHierarchyRowID?>.Binding,
        accessibilityFocusedRowID:
            AccessibilityFocusState<ModelCatalogHierarchyRowID?>.Binding,
        onSelect: @escaping (ModelCatalogHierarchySelection) -> Void,
        onToggleCheckpoint: @escaping (ModelCatalogCheckpointPresentation) -> Void,
        onReset: @escaping () -> Void,
        emptyPresentation: ModelCatalogEmptyPresentation,
        @ViewBuilder row: @escaping (
            ModelCatalogRowPresentation,
            ModelCatalogArtifactRowContext?
        ) -> Row
    ) {
        self.rows = rows
        self.sizeLabel = sizeLabel
        self.hierarchyRows = hierarchyRows
        self.accessibilityRows = accessibilityRows
        self.selection = selection
        self.focusedRowID = focusedRowID
        self.accessibilityFocusedRowID = accessibilityFocusedRowID
        self.onSelect = onSelect
        self.onToggleCheckpoint = onToggleCheckpoint
        self.onReset = onReset
        self.emptyPresentation = emptyPresentation
        self.row = row
    }

    var body: some View {
        let accessibilityRowsByID = Dictionary(
            uniqueKeysWithValues: accessibilityRows.map {
                ($0.id, $0)
            }
        )

        VStack(spacing: 0) {
            ModelCatalogColumnHeader()
            Divider()
            if rows.isEmpty {
                ModelCatalogEmptyState(
                    presentation: emptyPresentation,
                    onAction: onReset
                )
                .onAppear {
                    if case .checking = emptyPresentation {
                        ModelCatalogPerformanceTrace.event(
                            "placeholder-visible"
                        )
                    }
                }
            } else {
                LazyVStack(spacing: 0) {
                    if hierarchyRows.isEmpty {
                        ForEach(rows) { catalogRow in
                            row(catalogRow, nil)
                                .id(ModelCatalogHierarchyRowID.standaloneArtifact(catalogRow.id))
                                .onAppear {
                                    ModelCatalogPerformanceTrace.event(
                                        "row-visible"
                                    )
                                    emitFirstUsefulRowIfNeeded()
                                }
                                .onDisappear {
                                    ModelCatalogPerformanceTrace.event(
                                        "row-recycled"
                                    )
                                }
                                .focusable()
                                .focused(
                                    focusedRowID,
                                    equals: .standaloneArtifact(catalogRow.id)
                                )
                                .accessibilityFocused(
                                    accessibilityFocusedRowID,
                                    equals: .standaloneArtifact(catalogRow.id)
                                )
                        }
                    } else {
                        ForEach(hierarchyRows) { hierarchyRow in
                            VStack(spacing: 0) {
                                switch hierarchyRow.content {
                                case let .family(family):
                                    ModelCatalogFamilyHeading(family: family)
                                case let .checkpoint(checkpoint):
                                    ModelCatalogCheckpointRow(
                                        checkpoint: checkpoint,
                                        isExpanded: hierarchyRow.isExpanded,
                                        isSelected: selection == .checkpoint(checkpoint.id),
                                        onSelect: {
                                            onSelect(.checkpoint(checkpoint.id))
                                        },
                                        onToggle: {
                                            withAnimation(
                                                reduceMotion ? nil : .easeInOut(duration: 0.16)
                                            ) {
                                                onToggleCheckpoint(checkpoint)
                                            }
                                        }
                                    )
                                    if hierarchyRow.isExpanded {
                                        ModelCatalogVariantComparisonHeader(
                                            sizeLabel: sizeLabel
                                        )
                                    }
                                case let .exactArtifact(checkpoint, artifact, isSingleVariant):
                                    row(
                                        artifact.row,
                                        ModelCatalogArtifactRowContext(
                                            title: isSingleVariant
                                                ? checkpoint.metadata.presentation.displayName
                                                : artifact.metadata.presentation.displayName,
                                            description: isSingleVariant
                                                ? checkpoint.metadata.presentation.description
                                                : "\(checkpoint.metadata.presentation.displayName) • \(artifact.row.model.engineName) • \(artifact.row.model.acceleratorName)",
                                            variantLabel: isSingleVariant
                                                ? artifact.metadata.presentation.displayName
                                                : nil,
                                            isRecommended: !isSingleVariant
                                                && checkpoint
                                                    .presentsRecommendation(
                                                        artifact
                                                    ),
                                            isFallback: !isSingleVariant
                                                && checkpoint
                                                    .presentsFallback(artifact),
                                            isSelected: selection == .exactArtifact(artifact.id),
                                            indentation: isSingleVariant ? 0 : 30,
                                            comparison: isSingleVariant
                                                ? nil
                                                : checkpoint.variantComparisons.first {
                                                    $0.id == artifact.id
                                                },
                                            onSelect: {
                                                onSelect(.exactArtifact(artifact.id))
                                            }
                                        )
                                    )
                                case let .standaloneArtifact(standaloneRow):
                                    row(standaloneRow, nil)
                                }
                            }
                            .id(hierarchyRow.id)
                            .onAppear {
                                ModelCatalogPerformanceTrace.event(
                                    "row-visible"
                                )
                                emitFirstUsefulRowIfNeeded()
                            }
                            .onDisappear {
                                ModelCatalogPerformanceTrace.event(
                                    "row-recycled"
                                )
                            }
                            .focusable()
                            .focused(focusedRowID, equals: hierarchyRow.id)
                            .accessibilityFocused(
                                accessibilityFocusedRowID,
                                equals: hierarchyRow.id
                            )
                            .modifier(
                                ModelCatalogRowAccessibilityModifier(
                                    presentation:
                                        accessibilityRowsByID[
                                            hierarchyRow.id
                                        ]
                                )
                            )
                        }
                    }
                }
            }
        }
        .background(TextifyVisualIdentity.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    colorSchemeContrast == .increased
                        ? Color.primary.opacity(0.7)
                        : TextifyVisualIdentity.separator,
                    lineWidth:
                        colorSchemeContrast == .increased ? 2 : 1
                )
        }
    }

    private func emitFirstUsefulRowIfNeeded() {
        guard !hasEmittedFirstUsefulRow else {
            return
        }
        hasEmittedFirstUsefulRow = true
        ModelCatalogPerformanceTrace.event("first-useful-row")
    }
}

private struct ModelCatalogRowAccessibilityModifier: ViewModifier {
    let presentation: ModelCatalogAccessibilityRow?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let presentation {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(presentation.label)
                .accessibilityValue(presentation.value)
                .accessibilityCustomContent(
                    LocalizedStringKey("Outline level"),
                    String(presentation.outlineLevel),
                    importance: .high
                )
                .accessibilityCustomContent(
                    LocalizedStringKey("Logical position"),
                    "\(presentation.logicalPosition) of \(presentation.logicalCount)",
                    importance: .high
                )
                .accessibilityAddTraits(
                    presentation.role == .familyHeading ? .isHeader : []
                )
                .accessibilityIdentifier(
                    presentation.id.accessibilityIdentifier
                )
                .modifier(
                    ModelCatalogDisclosureAccessibilityModifier(
                        state: presentation.disclosureState
                    )
                )
        } else {
            content
        }
    }
}

private struct ModelCatalogDisclosureAccessibilityModifier: ViewModifier {
    let state: ModelCatalogAccessibilityDisclosureState?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let state {
            content.accessibilityCustomContent(
                LocalizedStringKey("Disclosure"),
                Text(LocalizedStringKey(state.accessibilityLabel)),
                importance: .high
            )
        } else {
            content
        }
    }
}

enum ModelCatalogEmptyPresentation {
    case checking
    case query(ModelCatalogQueryEmptyState)
    case purpose(ModelCatalogPurposeDestination)
    case unavailable(ModelCatalogPurposeDestination)
    case securityFailure(ModelCatalogPurposeDestination)
    case requiresNewerTextify(manifestVersion: Int)

    var icon: String {
        switch self {
        case let .query(state):
            switch state {
            case .installed:
                return "internaldrive"
            case .search:
                return "magnifyingglass"
            case .filters:
                return "line.3.horizontal.decrease.circle"
            case .combined:
                return "magnifyingglass.circle"
            case .validCatalog:
                return "shippingbox"
            }
        case .checking:
            return "clock.arrow.circlepath"
        case .purpose:
            return "shippingbox"
        case .unavailable:
            return "exclamationmark.triangle"
        case .securityFailure:
            return "exclamationmark.shield"
        case .requiresNewerTextify:
            return "arrow.down.app"
        }
    }

    var title: String {
        switch self {
        case .checking:
            return "Loading model list"
        case let .query(state):
            return state.title
        case let .purpose(destination):
            return destination.emptyTitle
        case let .unavailable(destination):
            return destination.unavailableTitle
        case .securityFailure:
            return "Catalog security check failed"
        case .requiresNewerTextify:
            return "Update Textify to view this catalog"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "Textify is preparing the model list included with this app."
        case let .query(state):
            return state.detail
        case let .purpose(destination):
            return destination.emptyDetail
        case let .unavailable(destination):
            return destination.unavailableDetail
        case .securityFailure:
            return String(
                localized:
                    "Textify could not verify the model list included with this app. Reinstall or update Textify. Existing local dictation may continue with an already loaded model; no catalog actions are available."
            )
        case let .requiresNewerTextify(manifestVersion):
            return "The bundled model list uses schema version \(manifestVersion), which this version of Textify cannot present."
        }
    }

    var actionTitle: String? {
        switch self {
        case .checking, .requiresNewerTextify, .securityFailure:
            return nil
        case let .query(state):
            return state.actionTitle
        case let .purpose(destination),
             let .unavailable(destination):
            return destination.unavailableActionTitle
        }
    }
}

private struct ModelCatalogFamilyHeading: View {
    let family: ModelCatalogFamilyPresentation

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                familyIdentity
                Spacer(minLength: 12)
                checkpointCount
            }
            VStack(alignment: .leading, spacing: 8) {
                familyIdentity
                checkpointCount
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 62, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var familyIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            ModelProviderTile(provider: provider, isActive: false)

            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        familyTitle
                        providerName
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        familyTitle
                        providerName
                    }
                }
                Text(family.metadata.presentation.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var familyTitle: some View {
        Text(family.metadata.presentation.displayName)
            .font(.headline.bold())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var providerName: some View {
        Text(family.metadata.presentation.provider.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var checkpointCount: some View {
        Text(
            "\(family.checkpoints.count) "
                + (
                    family.checkpoints.count == 1
                        ? "checkpoint"
                        : "checkpoints"
                )
        )
        .font(.caption)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var provider: ModelProviderIdentity {
        .resolve(
            from: family.metadata.presentation.provider.id,
            family.metadata.presentation.provider.displayName
        )
    }
}

private struct ModelCatalogCheckpointRow: View {
    let checkpoint: ModelCatalogCheckpointPresentation
    let isExpanded: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 18, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(isExpanded ? "Collapse" : "Expand") \(checkpoint.metadata.presentation.displayName)"
            )

            Button(action: onSelect) {
                if dynamicTypeSize.isAccessibilitySize {
                    checkpointContent(isCompact: true)
                } else {
                    ViewThatFits(in: .horizontal) {
                        checkpointContent(isCompact: false)
                            .frame(
                                minWidth:
                                    ModelCatalogPrimaryRowLayout
                                        .wideMinimumWidth
                            )
                        checkpointContent(isCompact: true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(checkpoint.metadata.presentation.displayName)
            .accessibilityValue(
                "\(checkpoint.metadata.artifactIDs.count) variants, "
                    + "\(isExpanded ? "expanded" : "collapsed")"
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 78)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 40)
        }
    }

    @ViewBuilder
    private func checkpointContent(
        isCompact: Bool
    ) -> some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 10) {
                checkpointIdentity(allowsWrapping: true)
                if let reference = recommendedArtifact {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 130),
                                alignment: .topLeading
                            ),
                        ],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        checkpointField("Quality") {
                            ModelSignalMetric(
                                level:
                                    reference.row.model
                                        .qualitySignalLevel,
                                label: reference.row.model.qualityLabel
                            )
                        }
                        checkpointField("Speed") {
                            ModelSignalMetric(
                                level:
                                    reference.row.model
                                        .speedSignalLevel,
                                label: reference.row.model.speedLabel
                            )
                        }
                        checkpointField("State") {
                            checkpointState
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 12) {
                checkpointIdentity(allowsWrapping: false)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let reference = recommendedArtifact {
                    ModelSignalMetric(
                        level: reference.row.model.qualitySignalLevel,
                        label: reference.row.model.qualityLabel
                    )
                    .frame(width: 86, alignment: .leading)
                    ModelSignalMetric(
                        level: reference.row.model.speedSignalLevel,
                        label: reference.row.model.speedLabel
                    )
                    .frame(width: 86, alignment: .leading)
                    checkpointState
                        .frame(width: 138, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func checkpointIdentity(
        allowsWrapping: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    checkpointTitle
                    checkpointVariantCount
                }
                VStack(alignment: .leading, spacing: 4) {
                    checkpointTitle
                    checkpointVariantCount
                }
            }
            Text(checkpoint.metadata.presentation.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(allowsWrapping ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checkpointTitle: some View {
        Text(checkpoint.metadata.presentation.displayName)
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var checkpointVariantCount: some View {
        Text("\(checkpoint.metadata.artifactIDs.count) VARIANTS")
            .font(.caption2.bold().monospaced())
            .foregroundStyle(.secondary)
    }

    private func checkpointField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.bold().monospaced())
                .foregroundStyle(.secondary)
            content()
        }
        .accessibilityElement(children: .combine)
    }

    private var recommendedArtifact: ModelCatalogExactArtifactPresentation? {
        checkpoint.presentedReferenceArtifact
    }

    private var checkpointState: some View {
        let installedCount = checkpoint.artifacts.filter(\.row.isInstalled).count
        let activeArtifact = checkpoint.artifacts.first(where: \.row.isActive)
        return VStack(alignment: .leading, spacing: 4) {
            if let activeArtifact {
                Label("Active", systemImage: "waveform.badge.checkmark")
                    .foregroundStyle(TextifyVisualIdentity.readyMint)
                Text(activeArtifact.metadata.presentation.displayName)
            } else if installedCount > 0 {
                Label("\(installedCount) installed", systemImage: "internaldrive")
            } else if let resolution = checkpoint.resolution,
                      resolution.recommendedCompatibility != .compatible {
                Label(
                    resolution.fallback == nil
                        ? resolution.recommendedCompatibility.catalogTitle
                        : "Signed fallback",
                    systemImage: resolution.fallback == nil
                        ? "exclamationmark.triangle"
                        : "arrow.triangle.branch"
                )
                if let fallback = checkpoint.defaultInstallArtifact {
                    Text(fallback.metadata.presentation.displayName)
                }
            } else {
                Label("Not installed", systemImage: "arrow.down.circle")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help(
            checkpoint.resolution?.recommendedCompatibility.catalogExplanation
                ?? "Signed recommendation"
        )
    }

    private var rowBackground: Color {
        guard isSelected else {
            return .clear
        }
        return colorScheme == .dark
            ? TextifyVisualIdentity.consoleSelection
            : TextifyVisualIdentity.voiceViolet.opacity(0.075)
    }
}

private struct ModelCatalogEmptyState: View {
    let presentation: ModelCatalogEmptyPresentation
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: presentation.icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(TextifyVisualIdentity.voiceViolet)
            Text(presentation.title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Text(presentation.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle = presentation.actionTitle {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .accessibilityElement(children: .contain)
    }
}

private struct ModelCatalogColumnHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                header(for: .compact)
            } else {
                ViewThatFits(in: .horizontal) {
                    header(for: .wide)
                        .frame(
                            minWidth:
                                ModelCatalogPrimaryRowLayout.wideMinimumWidth
                        )
                    header(for: .compact)
                }
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .tracking(0.9)
        .foregroundStyle(.secondary)
        .background(Color.white.opacity(0.015))
        .accessibilityLabel("Model catalog table headers")
        .accessibilityElement(children: .contain)
        .accessibilityChildren {
            ForEach(
                ModelCatalogAccessibilityTableHeader.allCases
            ) { header in
                Text(LocalizedStringKey(header.label))
                    .accessibilityLabel(
                        LocalizedStringKey(header.accessibilityLabel)
                    )
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(
                        "model-catalog-header-\(header.id)"
                    )
            }
        }
    }

    @ViewBuilder
    private func header(
        for layout: ModelCatalogPrimaryRowLayout
    ) -> some View {
        if layout.showsTableHeader {
            HStack(spacing: 12) {
                Text("MODEL")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("QUALITY")
                    .frame(width: 86, alignment: .leading)
                Text("SPEED")
                    .frame(width: 86, alignment: .leading)
                Text("FEATURES")
                    .frame(width: 138, alignment: .leading)
            }
            .padding(.leading, 94)
            .padding(.trailing, 14)
            .frame(minHeight: 38)
            .accessibilityHidden(true)
        } else {
            Text("MODEL DETAILS")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .accessibilityHidden(true)
        }
    }
}

private struct TextifyModelCard: View {
    let model: ProductionModelPresentation
    let sizeLabel: String
    let sizeDescription: String
    let hierarchyContext: ModelCatalogArtifactRowContext?
    let compatibility: ModelCatalogCompatibility
    let placement: ModelArtifactPlacement?
    let isRevoked: Bool
    let isInstalled: Bool
    let isActive: Bool
    let isActivating: Bool
    let isBusy: Bool
    let install: ModelCatalogInstallPresentation?
    let actions: Set<ModelCatalogRowAction>
    let onUse: () -> Void
    let onDisable: () -> Void
    let onInstall: () -> Void
    let onCancelInstall: () -> Void
    let onRetryInstall: () -> Void
    let onDelete: () -> Void
    let onInspect: (() -> Void)?

    @State private var showsDetails = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            adaptiveSummary

            HStack(spacing: 10) {
                Spacer()
                    .frame(width: hierarchyContext == nil ? 76 : 28)

                Text("ACTIONS")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)

                if isActivating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Preparing model")
                } else if isActive {
                    Label(model.activeLabel, systemImage: "waveform.badge.checkmark")
                        .foregroundStyle(TextifyVisualIdentity.readyMint)
                    if actions.contains(.disable) {
                        Button("Disable", systemImage: "power", action: onDisable)
                            .disabled(isBusy)
                    }
                } else if actions.contains(.use) {
                    Button(model.useLabel, systemImage: "waveform", action: onUse)
                        .disabled(isBusy || !compatibility.allowsModelOperations)
                        .help(compatibility.catalogExplanation)
                }

                if actions.contains(.reinstall) {
                    Button("Reinstall", systemImage: "arrow.clockwise", action: onInstall)
                        .disabled(
                            isBusy
                                || !compatibility.allowsModelOperations
                                || ProductionModelInstallConfiguration.current == nil
                        )
                        .help(compatibility.catalogExplanation)
                        .foregroundStyle(.secondary)
                } else if actions.contains(.install) {
                    Button(model.installLabel, systemImage: "arrow.down.circle", action: onInstall)
                        .disabled(
                            isBusy
                                || !compatibility.allowsModelOperations
                                || ProductionModelInstallConfiguration.current == nil
                        )
                        .help(compatibility.catalogExplanation)
                }

                if actions.contains(.delete) {
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        .disabled(isActive || isBusy)
                        .foregroundStyle(TextifyVisualIdentity.recordCoral)
                }

                if actions.contains(.details) {
                    Button(
                        hierarchyContext == nil
                            ? onInspect == nil
                                ? (showsDetails ? "Hide Details" : "Details")
                                : "Inspect"
                            : "Inspect",
                        systemImage: "info.circle"
                    ) {
                        if let hierarchyContext {
                            hierarchyContext.onSelect()
                        } else if let onInspect {
                            onInspect()
                        } else {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                showsDetails.toggle()
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .font(.callout)
            .buttonStyle(.borderless)

            if compatibility != .compatible {
                Label(
                    "\(compatibility.catalogTitle): \(compatibility.catalogExplanation)",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(TextifyVisualIdentity.warmWarning)
                .padding(.leading, hierarchyContext == nil ? 76 : 28)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let install {
                ModelCardInstallProgress(
                    install: install,
                    actions: actions,
                    isActionable: compatibility.allowsModelOperations,
                    onCancel: onCancelInstall,
                    onRetry: onRetryInstall
                )
                .padding(.leading, 76)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showsDetails, hierarchyContext == nil {
                ModelDetailGrid(model: model)
                    .padding(.leading, 76)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .padding(.leading, hierarchyContext?.indentation ?? 0)
        .frame(minHeight: 102, alignment: .topLeading)
        .background(activeBackground)
        .overlay {
            if accessibleAppearance.requiresSelectionBorder,
               hierarchyContext?.isSelected == true || showsSelectedTreatment {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary, lineWidth: 2)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 94)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            hierarchyContext?.onSelect()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(
            hierarchyContext?.isSelected == true ? .isSelected : []
        )
    }

    @ViewBuilder
    private var adaptiveSummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            modelSummary(for: .compact)
        } else {
            ViewThatFits(in: .horizontal) {
                modelSummary(for: .wide)
                    .frame(
                        minWidth:
                            ModelCatalogPrimaryRowLayout.wideMinimumWidth
                    )
                modelSummary(for: .compact)
            }
        }
    }

    @ViewBuilder
    private func modelSummary(
        for layout: ModelCatalogPrimaryRowLayout
    ) -> some View {
        switch layout {
        case .wide:
            HStack(alignment: .center, spacing: 12) {
                identitySummary(allowsCompactText: false)
                ModelSignalMetric(
                    level: model.qualitySignalLevel,
                    label: model.qualityLabel
                )
                .frame(width: 86, alignment: .leading)
                ModelSignalMetric(
                    level: model.speedSignalLevel,
                    label: model.speedLabel
                )
                .frame(width: 86, alignment: .leading)
                ModelFeaturesMetric(
                    model: model,
                    sizeLabel: sizeLabel,
                    sizeDescription: sizeDescription
                )
                .frame(width: 138, alignment: .leading)
            }
        case .compact:
            VStack(alignment: .leading, spacing: 12) {
                identitySummary(allowsCompactText: true)
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 130),
                            alignment: .topLeading
                        ),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    labeledRowField("Quality") {
                        ModelSignalMetric(
                            level: model.qualitySignalLevel,
                            label: model.qualityLabel
                        )
                    }
                    labeledRowField("Speed") {
                        ModelSignalMetric(
                            level: model.speedSignalLevel,
                            label: model.speedLabel
                        )
                    }
                    labeledRowField("Features") {
                        ModelFeaturesMetric(
                            model: model,
                            sizeLabel: sizeLabel,
                            sizeDescription: sizeDescription
                        )
                    }
                    labeledRowField("State") {
                        Text(accessibilityStateDescription)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, hierarchyContext == nil ? 76 : 28)
            }
        }
    }

    private func identitySummary(
        allowsCompactText: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ModelSelectionIndicator(
                isInstalled: isInstalled,
                isActive: showsSelectedTreatment
            )

            if hierarchyContext == nil {
                ModelProviderTile(
                    provider: model.provider,
                    isActive: showsSelectedTreatment
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        modelTitle
                        statusBadges
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        modelTitle
                        statusBadges
                    }
                }
                Text(hierarchyContext?.description ?? model.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(allowsCompactText ? nil : 2)
                    .fixedSize(
                        horizontal: false,
                        vertical: allowsCompactText
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modelTitle: some View {
        HStack(spacing: 7) {
            Text(hierarchyContext?.title ?? model.catalogDisplayName)
                .font(.body.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if let variantLabel = hierarchyContext?.variantLabel {
                Text(variantLabel.uppercased())
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusBadges: some View {
        HStack(spacing: 6) {
            if isRevoked {
                TextifyStatusBadge(title: "REVOKED", tone: .warning)
            }
            if hierarchyContext?.isRecommended == true {
                TextifyStatusBadge(title: "RECOMMENDED", tone: .accent)
            }
            if hierarchyContext?.isFallback == true {
                TextifyStatusBadge(title: "SIGNED FALLBACK", tone: .warning)
            }
            TextifyStatusBadge(
                title: model.supportTier.uppercased(),
                tone: tierTone
            )
            if let placement, placement != .curated {
                TextifyStatusBadge(
                    title: placement.title.uppercased(),
                    tone: placement == .custom ? .neutral : .warning
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func labeledRowField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.bold().monospaced())
                .foregroundStyle(.secondary)
            content()
        }
        .accessibilityElement(children: .combine)
    }

    private var accessibilityStateDescription: String {
        if isRevoked {
            return "Revoked"
        }
        if isActivating {
            return "Preparing"
        }
        if isActive {
            return "Active"
        }
        if let install {
            return install.accessibilityValue
        }
        return isInstalled ? "Installed" : "Not installed"
    }

    private var accessibleAppearance: ModelCatalogAccessibleAppearance {
        ModelCatalogAccessibleAppearance(
            increaseContrast: colorSchemeContrast == .increased,
            differentiateWithoutColor: differentiateWithoutColor
        )
    }

    private var tierTone: TextifyStatusBadge.Tone {
        switch model.supportTier {
        case "Recommended": .accent
        case "Fast", "Accurate": .success
        case "Experimental": .neutral
        default: .neutral
        }
    }

    private var activeBackground: Color {
        if hierarchyContext?.isSelected == true {
            return colorScheme == .dark
                ? TextifyVisualIdentity.consoleSelection
                : TextifyVisualIdentity.voiceViolet.opacity(0.075)
        }
        guard showsSelectedTreatment else {
            return .clear
        }
        return colorScheme == .dark
            ? TextifyVisualIdentity.consoleSelection
            : TextifyVisualIdentity.voiceViolet.opacity(0.075)
    }

    private var showsSelectedTreatment: Bool {
        isActive && model.purpose == .transcription
    }
}

private struct ModelCardInstallProgress: View {
    let install: ModelCatalogInstallPresentation
    let actions: Set<ModelCatalogRowAction>
    let isActionable: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(install.title, systemImage: phaseIcon)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(statusColor)

                if let percentText = install.percentText {
                    Text(percentText)
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 8)

                if actions.contains(.retryInstall) {
                    Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
                        .disabled(!isActionable)
                }
                if actions.contains(.cancelInstall) {
                    Button("Cancel", systemImage: "xmark.circle", action: onCancel)
                }
            }

            if install.state.totalBytes > 0 {
                ProgressView(value: install.progressValue, total: 1)
                    .tint(statusColor)
                    .accessibilityLabel(install.title)
                    .accessibilityValue(install.accessibilityValue)
            } else if install.state.isActive {
                ProgressView()
                    .controlSize(.small)
                    .tint(statusColor)
                    .accessibilityLabel(install.title)
                    .accessibilityValue(install.accessibilityValue)
            }

            Text(install.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(statusColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(statusColor)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(statusColor.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(install.title)
        .accessibilityValue(install.accessibilityValue)
    }

    private var statusColor: Color {
        switch install.state.phase {
        case .paused, .waitingForNetwork, .waitingForCatalogCheck,
             .interrupted, .failed, .revoked:
            return TextifyVisualIdentity.recordCoral
        case .cancelled:
            return TextifyVisualIdentity.slate
        case .queued, .checkingSpace, .downloading, .verifying, .installing,
             .installed:
            return TextifyVisualIdentity.voiceViolet
        }
    }

    private var phaseIcon: String {
        switch install.state.phase {
        case .queued:
            return "list.number"
        case .paused:
            return "pause.circle"
        case .waitingForNetwork:
            return "wifi.exclamationmark"
        case .waitingForCatalogCheck:
            return "checkmark.shield"
        case .checkingSpace:
            return "internaldrive"
        case .downloading:
            return "arrow.down.circle.fill"
        case .interrupted:
            return "wifi.exclamationmark"
        case .verifying:
            return "checkmark.seal"
        case .installing:
            return "shippingbox"
        case .installed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .cancelled:
            return "xmark.circle"
        case .revoked:
            return "hand.raised.fill"
        }
    }
}

private struct ModelSelectionIndicator: View {
    let isInstalled: Bool
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(indicatorColor.opacity(isInstalled ? 0.9 : 0.42), lineWidth: 2)
            if isActive {
                Circle()
                    .fill(indicatorColor)
                    .padding(4)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private var indicatorColor: Color {
        isActive ? TextifyVisualIdentity.voiceViolet : TextifyVisualIdentity.slate
    }
}

private struct ModelProviderTile: View {
    let provider: ModelProviderIdentity
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.12 : 0.055))

            if let logoAssetName = provider.logoAssetName {
                Image(logoAssetName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .padding(provider.logoInset)
            } else if let systemImage = provider.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(provider.accent)
            } else {
                Text(provider.mark)
                    .font(.system(size: provider.mark.count > 1 ? 10 : 16, weight: .bold))
                    .foregroundStyle(provider.accent)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(provider.accent.opacity(isActive ? 0.48 : 0.24), lineWidth: 1)
        }
        .accessibilityLabel(provider.name)
    }
}

private struct ModelSignalMetric: View {
    let level: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(1 ... 5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(index <= level ? signalColor : Color.primary.opacity(0.13))
                        .frame(width: 4, height: CGFloat(5 + index * 3))
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level == 0 ? label : "\(label), \(level) of 5")
    }

    private var signalColor: Color {
        level >= 5 ? TextifyVisualIdentity.readyMint : TextifyVisualIdentity.voiceViolet
    }
}

private struct ModelFeaturesMetric: View {
    let model: ProductionModelPresentation
    let sizeLabel: String
    let sizeDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                "\(sizeLabel): \(sizeDescription)",
                systemImage: "internaldrive"
            )
            Label(model.languageDescription, systemImage: "character.bubble")
            Label(model.acceleratorName, systemImage: "cpu")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

private struct ModelDetailGrid: View {
    let model: ProductionModelPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    ModelFactRow(label: "Runtime", value: "\(model.engineName) • \(model.acceleratorName)")
                    ModelFactRow(label: "Finalization", value: model.expectedFinalization)
                    ModelFactRow(label: "Accuracy", value: model.accuracyTradeoff)
                    ModelFactRow(label: "Requires", value: model.requirements)
                    if let qualityEvidence = model.qualityEvidenceDescription {
                        ModelFactRow(label: "Quality test", value: qualityEvidence)
                        ModelFactRow(label: "WER", value: model.wordErrorRateDescription)
                        ModelFactRow(
                            label: "No-speech",
                            value: model.noSpeechEvidenceDescription
                        )
                    } else {
                        ModelFactRow(
                            label: "Ratings",
                            value: "Unrated — no signed comparable benchmark evidence"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ModelFactRow(label: "Artifact", value: model.artifactName)
                    ModelFactRow(label: "License", value: model.licenseDescription)
                    if let checksum = model.checksum {
                        ModelFactRow(label: "SHA-256", value: checksum)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    if let speedEvidence = model.speedEvidenceDescription {
                        ModelFactRow(label: "Speed test", value: speedEvidence)
                    }
                    if let provenance = model.benchmarkProvenanceDescription {
                        ModelFactRow(
                            label: "Test runtime",
                            value: model.benchmarkRuntimeDescription
                        )
                        ModelFactRow(label: "Measured", value: provenance)
                        ModelFactRow(
                            label: "Policy",
                            value: model.benchmarkPolicyDescription
                        )
                    }
                    if let sourceURL = model.sourceURL {
                        Link(destination: sourceURL) {
                            Label("Open \(model.sourceName)", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
            .font(.caption)
        }
    }
}

private struct ModelFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PrivacySettingsPane: View {
    @Environment(AppServices.self) private var services
    @State private var permissionMessage: String?
    @State private var isRequestingPermissions = false
    @State private var permissionRequestTask: Task<Void, Never>?

    var body: some View {
        SettingsPaneLayout(title: "Privacy") {
            SettingsSection("Permissions") {
                PermissionSetupGuide(
                    presentation: permissionSetupPresentation,
                    isWorking: isRequestingPermissions,
                    action: performPrimaryPermissionAction
                )

                Divider()

                PermissionRow(
                    name: "Microphone",
                    status: services.dictation.readiness.permissions.microphone.settingsStatusLabel,
                    actionTitle: microphoneActionTitle,
                    isDisabled: isRequestingPermissions
                ) {
                    performMicrophoneAction(continuesSetup: false)
                }

                Divider()

                PermissionRow(
                    name: "Accessibility",
                    status: services.dictation.readiness.permissions.accessibility.settingsStatusLabel,
                    actionTitle: accessibilityActionTitle,
                    isDisabled: isRequestingPermissions
                ) {
                    performAccessibilityAction()
                }

                if services.dictation.readiness.permissions.accessibility != .granted {
                    Divider()
                    AccessibilityAppDragSource(
                        isSetupDisabled: isRequestingPermissions
                    )
                }

                if let permissionMessage {
                    Text(permissionMessage)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Data") {
                PrivacyPromiseRow(
                    icon: "waveform",
                    title: "Audio stays in memory",
                    detail: "Recordings are processed for dictation and are not saved."
                )
                Divider()
                PrivacyPromiseRow(
                    icon: "clock.arrow.circlepath",
                    title: "No dictation history",
                    detail: "Textify does not keep a searchable record of what you say."
                )
                Divider()
                PrivacyPromiseRow(
                    icon: "network.slash",
                    title: "Offline after setup",
                    detail: "Dictation runs locally; network access is reserved for model downloads."
                )
            }

            SettingsSection("Excluded Apps") {
                if services.preferences.excludedApps.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "app.dashed")
                            .font(.title2)
                            .foregroundStyle(TextifyVisualIdentity.slate)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No excluded apps")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                            Text("Textify is available wherever the focused field is safe to use.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(services.preferences.excludedApps) { app in
                        HStack(spacing: 10) {
                            ExcludedAppIcon(app: app)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName)
                                Text(app.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Button("Remove") {
                                removeExcludedApp(bundleIdentifier: app.bundleIdentifier)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Menu("Add Running App") {
                        let candidates = ExcludedAppsSettingsModel.runningCandidates()
                            .filter { candidate in
                                !services.preferences.excludedApps.contains {
                                    $0.bundleIdentifier == candidate.bundleIdentifier
                                }
                            }
                        if candidates.isEmpty {
                            Text("No available running apps")
                        } else {
                            ForEach(candidates) { candidate in
                                Button(candidate.displayName) {
                                    addExcludedApp(candidate)
                                }
                            }
                        }
                    }

                    Button("Add Application…") {
                        chooseExcludedApplication()
                    }
                }
                .padding(.top, 2)
            }
        }
        .task {
            await monitorAccessibilityPermission()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task {
                _ = await refreshPermissions()
            }
        }
        .onDisappear {
            permissionRequestTask?.cancel()
            permissionRequestTask = nil
        }
    }

    private func monitorAccessibilityPermission() async {
        var displayedState = (await refreshPermissions()).accessibility

        while !Task.isCancelled {
            do {
                _ = try await AccessibilityPermissionMonitor.live.nextChange(from: displayedState)
            } catch {
                return
            }
            displayedState = (await refreshPermissions()).accessibility
        }
    }

    private func refreshPermissions() async -> RuntimePermissionSnapshot {
        let previous = services.dictation.readiness.permissions
        let snapshot = await services.dictation.refreshReadiness()
        let updated = snapshot.permissions

        if previous != updated {
            permissionMessage = PermissionSetupPresentation(
                permissions: updated
            ).statusMessage
        }
        return updated
    }

    private var permissionSetupPresentation: PermissionSetupPresentation {
        PermissionSetupPresentation(
            permissions: services.dictation.readiness.permissions
        )
    }

    private var microphoneActionTitle: String? {
        switch services.dictation.readiness.permissions.microphone {
        case .unknown:
            return "Allow Microphone"
        case .denied:
            return "Open Microphone Settings"
        case .granted:
            return nil
        }
    }

    private var accessibilityActionTitle: String? {
        services.dictation.readiness.permissions.accessibility == .granted
            ? nil
            : "Allow Accessibility"
    }

    private func performPrimaryPermissionAction() {
        switch permissionSetupPresentation.primaryAction {
        case .requestMicrophoneThenAccessibility:
            performMicrophoneAction(continuesSetup: true)
        case .openMicrophoneSettings:
            openMicrophoneSettings()
        case .requestAccessibility:
            performAccessibilityAction()
        case .complete:
            break
        }
    }

    private func performMicrophoneAction(continuesSetup: Bool) {
        guard !isRequestingPermissions else {
            return
        }

        if services.dictation.readiness.permissions.microphone == .denied {
            openMicrophoneSettings()
            return
        }

        isRequestingPermissions = true
        permissionRequestTask?.cancel()
        permissionRequestTask = Task {
            defer {
                isRequestingPermissions = false
            }

            let state = await ProductionPermissionRequester.requestMicrophone()
            guard !Task.isCancelled else {
                return
            }

            let permissions = await refreshPermissions()
            guard !Task.isCancelled else {
                return
            }

            guard state == .granted else {
                permissionMessage = state.permissionRequestMessage(
                    for: "Microphone"
                )
                return
            }

            if continuesSetup, permissions.accessibility != .granted {
                permissionMessage =
                    "Microphone is ready. Continue in macOS to allow Accessibility."
                ProductionPermissionRequester.requestAccessibilityPrompt()
            }
        }
    }

    private func openMicrophoneSettings() {
        if SystemPrivacySettingsOpener.open(.microphone) {
            permissionMessage =
                "Turn on Microphone for Textify in System Settings, then return here."
        } else {
            permissionMessage =
                "Open System Settings → Privacy & Security → Microphone, then turn on Textify."
        }
    }

    private func performAccessibilityAction() {
        ProductionPermissionRequester.requestAccessibilityPrompt()
        permissionMessage =
            "Turn on Textify under Accessibility in System Settings."

        Task {
            _ = await refreshPermissions()
        }
    }

    private func addExcludedApp(_ candidate: ExcludedAppCandidate) {
        let cachedIconData = candidate.path.flatMap {
            ExcludedAppsSettingsModel.compactIconData(for: URL(fileURLWithPath: $0))
        }
        services.preferences.excludedApps = ExcludedAppsSettingsModel.adding(
            candidate,
            to: services.preferences.excludedApps,
            cachedIconData: cachedIconData
        )
        services.savePreferences()
    }

    private func removeExcludedApp(bundleIdentifier: String) {
        services.preferences.excludedApps.removeAll {
            $0.bundleIdentifier == bundleIdentifier
        }
        services.savePreferences()
    }

    private func chooseExcludedApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application to exclude"
        panel.prompt = "Exclude"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK,
              let url = panel.url,
              let candidate = ExcludedAppsSettingsModel.candidate(for: url) else {
            return
        }
        addExcludedApp(candidate)
    }
}

enum PermissionSetupAction: Equatable {
    case requestMicrophoneThenAccessibility
    case openMicrophoneSettings
    case requestAccessibility
    case complete
}

struct PermissionSetupPresentation: Equatable {
    let permissions: RuntimePermissionSnapshot

    var completedCount: Int {
        [
            permissions.microphone,
            permissions.accessibility,
        ].count { $0 == .granted }
    }

    var primaryAction: PermissionSetupAction {
        switch permissions.microphone {
        case .unknown:
            return .requestMicrophoneThenAccessibility
        case .denied:
            return .openMicrophoneSettings
        case .granted:
            return permissions.accessibility == .granted
                ? .complete
                : .requestAccessibility
        }
    }

    var actionTitle: String? {
        switch primaryAction {
        case .requestMicrophoneThenAccessibility:
            return permissions.accessibility == .granted
                ? "Allow Microphone"
                : "Allow Permissions"
        case .openMicrophoneSettings:
            return "Open Microphone Settings"
        case .requestAccessibility:
            return "Allow Accessibility"
        case .complete:
            return nil
        }
    }

    var title: String {
        primaryAction == .complete
            ? "Permissions are ready"
            : "Allow Textify to listen and type"
    }

    var detail: String {
        switch primaryAction {
        case .requestMicrophoneThenAccessibility:
            if permissions.accessibility == .granted {
                return "Allow Microphone so Textify can listen only while your trigger is held."
            }
            return "macOS asks for Microphone first, then Accessibility. Textify guides you through both."
        case .openMicrophoneSettings:
            return "Microphone was previously denied. Turn it on in System Settings, then return here."
        case .requestAccessibility:
            return "Microphone is ready. Allow Accessibility so Textify can type into the active app."
        case .complete:
            return "Textify can listen while your trigger is held and type the result into the active app."
        }
    }

    var statusMessage: String {
        switch primaryAction {
        case .complete:
            return "Both permissions are granted."
        case .requestAccessibility:
            return "Microphone is ready. Accessibility still needs attention."
        case .requestMicrophoneThenAccessibility, .openMicrophoneSettings:
            return "Microphone still needs attention."
        }
    }
}

private struct PermissionSetupGuide: View {
    let presentation: PermissionSetupPresentation
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(guideColor.opacity(0.13))

                    Image(
                        systemName: presentation.primaryAction == .complete
                            ? "checkmark.shield.fill"
                            : "checklist"
                    )
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(guideColor)
                    .accessibilityHidden(true)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Text(presentation.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 14)

                if let actionTitle = presentation.actionTitle {
                    Button(action: action) {
                        HStack(spacing: 7) {
                            if isWorking {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(actionTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isWorking)
                }
            }

            HStack(spacing: 10) {
                PermissionSetupStep(
                    number: 1,
                    title: "Microphone",
                    isGranted: presentation.permissions.microphone == .granted,
                    isCurrent: presentation.permissions.microphone != .granted
                )

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                PermissionSetupStep(
                    number: 2,
                    title: "Accessibility",
                    isGranted: presentation.permissions.accessibility == .granted,
                    isCurrent:
                        presentation.permissions.microphone == .granted
                            && presentation.permissions.accessibility != .granted
                )
            }
            .accessibilityElement(children: .contain)
        }
        .padding(14)
        .background(
            TextifyVisualIdentity.raisedSurface.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(guideColor.opacity(0.22), lineWidth: 1)
        }
    }

    private var guideColor: Color {
        presentation.primaryAction == .complete
            ? TextifyVisualIdentity.readyMint
            : TextifyVisualIdentity.voiceViolet
    }
}

private struct PermissionSetupStep: View {
    let number: Int
    let title: String
    let isGranted: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(stepColor.opacity(0.16))

                if isGranted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                } else {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
            .frame(width: 24, height: 24)
            .foregroundStyle(stepColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(stepStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TextifyVisualIdentity.cardSurface.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number), \(title)")
        .accessibilityValue(stepStatus)
    }

    private var stepColor: Color {
        if isGranted {
            return TextifyVisualIdentity.readyMint
        }
        return isCurrent
            ? TextifyVisualIdentity.voiceViolet
            : TextifyVisualIdentity.slate
    }

    private var stepStatus: String {
        if isGranted {
            return "Granted"
        }
        return isCurrent ? "Next" : "Waiting"
    }
}

struct AccessibilityAppDragSource: View {
    private let appURL = Bundle.main.bundleURL
    let isSetupDisabled: Bool

    init(isSetupDisabled: Bool = false) {
        self.isSetupDisabled = isSetupDisabled
    }

    var body: some View {
        HStack(spacing: 12) {
            TextifyDraggableAppIcon(size: 44)
                .shadow(color: .black.opacity(0.28), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Add Textify directly")
                    .font(.system(size: 14, weight: .semibold))
                Text("Drag this app icon into the Accessibility list, then turn Textify on.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Label("Drag app", systemImage: "hand.draw")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    TextifyVisualIdentity.voiceViolet.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .overlay {
            AppBundleDragSurface(appURL: appURL)
                .allowsHitTesting(!isSetupDisabled)
                .accessibilityHidden(true)
        }
        .opacity(isSetupDisabled ? 0.55 : 1)
        .help("Drag Textify into the Accessibility apps list")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drag Textify into the Accessibility apps list")
        .accessibilityHint(
            isSetupDisabled
                ? "Wait for the Microphone request to finish."
                : "Press to ask macOS for access, or drop Textify in System Settings."
        )
        .accessibilityAction {
            guard !isSetupDisabled else {
                return
            }
            ProductionPermissionRequester.requestAccessibilityPrompt()
        }
    }
}

private struct TextifyDraggableAppIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.08, blue: 0.24),
                            Color(red: 0.035, green: 0.04, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: size * 0.07) {
                TextifyVoiceMark(state: .processing, height: size * 0.45)

                Text("I")
                    .font(.system(size: size * 0.48, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct AppBundleDragSurface: NSViewRepresentable {
    let appURL: URL

    func makeNSView(context: Context) -> AppBundleDragSourceView {
        AppBundleDragSourceView(appURL: appURL)
    }

    func updateNSView(_ nsView: AppBundleDragSourceView, context: Context) {
        nsView.appURL = appURL
    }
}

@MainActor
private final class AppBundleDragSourceView: NSView, NSDraggingSource {
    var appURL: URL

    init(appURL: URL) {
        self.appURL = appURL
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(
            pasteboardWriter: TextifyAppDragSource.pasteboardItem(for: appURL)
        )
        let location = convert(event.locationInWindow, from: nil)
        let previewSize = NSSize(width: 64, height: 64)
        let previewFrame = NSRect(
            x: location.x - (previewSize.width / 2),
            y: location.y - (previewSize.height / 2),
            width: previewSize.width,
            height: previewSize.height
        )
        item.setDraggingFrame(
            previewFrame,
            contents: NSWorkspace.shared.icon(forFile: appURL.path)
        )

        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}

private struct PrivacyPromiseRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                .frame(width: 26, height: 26)
                .background(TextifyVisualIdentity.voiceViolet.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ExcludedAppCandidate: Equatable, Identifiable {
    var id: String { bundleIdentifier }

    let bundleIdentifier: String
    let displayName: String
    let path: String?
}

enum ExcludedAppsSettingsModel {
    static func adding(
        _ candidate: ExcludedAppCandidate,
        to apps: [ExcludedApp],
        cachedIconData: Data? = nil
    ) -> [ExcludedApp] {
        guard !apps.contains(where: { $0.bundleIdentifier == candidate.bundleIdentifier }) else {
            return apps
        }
        return apps + [
            ExcludedApp(
                bundleIdentifier: candidate.bundleIdentifier,
                displayName: candidate.displayName,
                cachedIconData: cachedIconData,
                lastKnownPath: candidate.path
            )
        ]
    }

    @MainActor
    static func runningCandidates(workspace: NSWorkspace = .shared) -> [ExcludedAppCandidate] {
        var seen = Set<String>()
        return workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application -> ExcludedAppCandidate? in
                guard let bundleIdentifier = application.bundleIdentifier,
                      bundleIdentifier != Bundle.main.bundleIdentifier,
                      seen.insert(bundleIdentifier).inserted else {
                    return nil
                }
                return ExcludedAppCandidate(
                    bundleIdentifier: bundleIdentifier,
                    displayName: application.localizedName ?? bundleIdentifier,
                    path: application.bundleURL?.path
                )
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    @MainActor
    static func candidate(for applicationURL: URL) -> ExcludedAppCandidate? {
        guard let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier else {
            return nil
        }
        let displayName = FileManager.default.displayName(atPath: applicationURL.path)
            .replacingOccurrences(of: ".app", with: "")
        return ExcludedAppCandidate(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            path: applicationURL.path
        )
    }

    @MainActor
    static func compactIconData(for applicationURL: URL) -> Data? {
        let pixelSize = 64
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        representation.size = NSSize(width: pixelSize, height: pixelSize)
        let sourceImage = NSWorkspace.shared.icon(forFile: applicationURL.path)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        sourceImage.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return representation.representation(using: .png, properties: [:])
    }
}

private struct ExcludedAppIcon: View {
    let app: ExcludedApp

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "app")
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: 28, height: 28)
    }

    private var resolvedImage: NSImage? {
        if let cachedIconData = app.cachedIconData,
           let image = NSImage(data: cachedIconData) {
            return image
        }
        if let path = app.lastKnownPath,
           FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }
}

private struct LogsSettingsPane: View {
    @Environment(AppServices.self) private var services
    @State private var entries: [DiagnosticsLogEntry] = []
    @State private var diagnosticsMessage: String?
    @State private var isWorking = false

    var body: some View {
        SettingsPaneLayout(title: "Logs", maxContentWidth: .infinity) {
            SettingsSection("Privacy Guard") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(TextifyVisualIdentity.readyMint)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Technical metadata only")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Logs never include dictated text, audio, clipboard contents, vocabulary, or target-app identifiers.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSection("Recent Activity") {
                HStack(spacing: 10) {
                    Text(entries.isEmpty ? "No events" : "\(entries.count) recent events")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Refresh") {
                        refreshLogs()
                    }
                    .disabled(isWorking)

                    Button("Export...") {
                        Task {
                            await exportDiagnostics()
                        }
                    }
                    .disabled(isWorking)

                    Button("Open Folder") {
                        NSWorkspace.shared.open(services.diagnosticsLogger.directory)
                    }
                    .disabled(isWorking)

                    Button("Clear") {
                        Task {
                            await clearDiagnostics()
                        }
                    }
                    .disabled(isWorking)
                }

                if let diagnosticsMessage {
                    Text(diagnosticsMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No diagnostic events", systemImage: "doc.text")
                    } description: {
                        Text("Use Textify, then refresh to inspect runtime activity.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            DiagnosticsLogEntryRow(entry: entry)
                            if entry.id != entries.last?.id {
                                Divider()
                                    .padding(.leading, 15)
                            }
                        }
                    }
                }
            }
        }
        .task { refreshLogs() }
    }

    @MainActor
    private func exportDiagnostics() async {
        isWorking = true
        defer {
            isWorking = false
        }

        do {
            let document = try DiagnosticsExporter().exportRedactedLogs(
                from: services.diagnosticsLogger.directory
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)

            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Textify-Diagnostics.json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else {
                diagnosticsMessage = "Diagnostics export cancelled."
                return
            }

            try data.write(to: url, options: [.atomic])
            diagnosticsMessage = "Diagnostics exported."
        } catch {
            diagnosticsMessage = "Diagnostics export failed."
        }
    }

    @MainActor
    private func clearDiagnostics() async {
        isWorking = true
        defer {
            isWorking = false
        }

        do {
            try await services.diagnosticsLogger.clear()
            diagnosticsMessage = "Diagnostics log cleared."
            refreshLogs()
        } catch {
            diagnosticsMessage = "Diagnostics could not be cleared."
        }
    }

    @MainActor
    private func refreshLogs() {
        do {
            entries = try DiagnosticsLogReader().recentEntries(
                from: services.diagnosticsLogger.directory
            )
            if diagnosticsMessage == "Diagnostics could not be loaded." {
                diagnosticsMessage = nil
            }
        } catch {
            entries = []
            diagnosticsMessage = "Diagnostics could not be loaded."
        }
    }
}

private struct DiagnosticsLogEntryRow: View {
    let entry: DiagnosticsLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tone)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let modelID = entry.modelID {
                        Text(modelID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Text(entry.timestamp ?? "Earlier log")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let reasonCode = entry.reasonCode {
                    Text(reasonCode.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tone)
                }

                Text(entry.json)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }

    private var title: String {
        switch entry.event {
        case "app_started":
            return "App started"
        case "dictation_blocked_excluded_app":
            return "Dictation blocked"
        case "insertion_attempt":
            return "Insertion attempt"
        case "model_load":
            return "Model preparation"
        case "runtime_failure":
            return "Runtime failure"
        case "speech_recognition_completed":
            return "Transcription completed"
        case "speech_recognition_discarded":
            return "Transcription discarded"
        case "voice_cleaning":
            return "Voice cleaning"
        default:
            return entry.event.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var tone: Color {
        switch entry.event {
        case "runtime_failure":
            return TextifyVisualIdentity.warmWarning
        case "speech_recognition_completed":
            return TextifyVisualIdentity.readyMint
        default:
            return TextifyVisualIdentity.voiceViolet
        }
    }
}

private struct AdvancedSettingsPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        SettingsPaneLayout(title: "Advanced") {
            SettingsSection("Runtime Status") {
                RuntimeStatusRow(
                    title: "Dictation",
                    value: services.dictation.status.menuStatusTitle,
                    isHealthy: services.dictation.status == .idle
                )
                Divider()
                RuntimeStatusRow(
                    title: "Model",
                    value: services.dictation.readiness.model.settingsModelStatus,
                    isHealthy: services.dictation.readiness.model.isReady
                )
                Divider()
                RuntimeStatusRow(
                    title: "Microphone",
                    value: services.dictation.readiness.permissions.microphone.settingsStatusLabel,
                    isHealthy: services.dictation.readiness.permissions.microphone == .granted
                )
                Divider()
                RuntimeStatusRow(
                    title: "Accessibility",
                    value: services.dictation.readiness.permissions.accessibility.settingsStatusLabel,
                    isHealthy: services.dictation.readiness.permissions.accessibility == .granted
                )
            }

            SettingsSection("Diagnostic Data") {
                Text("Diagnostics use redacted duration values and length buckets only.")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            _ = await services.dictation.refreshReadiness()
        }
    }
}

private struct RuntimeStatusRow: View {
    let title: String
    let value: String
    let isHealthy: Bool

    var body: some View {
        LabeledContent(title) {
            TextifyStatusBadge(
                title: value.uppercased(),
                tone: isHealthy ? .success : .warning
            )
        }
    }
}

extension ModelProviderIdentity {
    var logoAssetName: String? {
        switch self {
        case .nyra: nil
        case .openAI: "VendorOpenAI"
        case .nvidia: "VendorNVIDIA"
        case .cohere: "VendorCohere"
        case .qwen: "VendorQwen"
        case .alibaba, .mossFormer: "VendorAlibabaCloud"
        case .reazon: "VendorReazon"
        case .apple, .mlx, .community: nil
        }
    }

    var logoInset: CGFloat {
        switch self {
        case .nvidia: 2
        case .qwen: 4
        default: 5
        }
    }

    var mark: String {
        switch self {
        case .nyra: "NY"
        case .openAI: "AI"
        case .nvidia: "N"
        case .cohere: "C"
        case .qwen: "Q"
        case .alibaba: "Q"
        case .apple: "A"
        case .mlx: "MLX"
        case .reazon: "R"
        case .mossFormer: "M"
        case .community: "•"
        }
    }

    var systemImage: String? {
        switch self {
        case .apple, .mlx: "apple.logo"
        case .community: "cube.transparent"
        default: nil
        }
    }

    var accent: Color {
        switch self {
        case .nyra: Color(red: 0.125, green: 0.557, blue: 0.596)
        case .openAI: Color(red: 0.063, green: 0.639, blue: 0.498)
        case .nvidia: Color(red: 0.463, green: 0.725, blue: 0.000)
        case .cohere: Color(red: 0.875, green: 0.478, blue: 0.443)
        case .qwen: Color(red: 0.337, green: 0.251, blue: 0.941)
        case .alibaba: Color(red: 0.980, green: 0.455, blue: 0.173)
        case .apple: Color.primary
        case .mlx: TextifyVisualIdentity.voiceViolet
        case .reazon: Color(red: 0.247, green: 0.565, blue: 0.969)
        case .mossFormer: Color(red: 0.710, green: 0.384, blue: 0.922)
        case .community: TextifyVisualIdentity.slate
        }
    }
}

struct ProductionModelInstallConfiguration: Equatable {
    let trustedKeys: [TrustedModelManifestKey]

    init(trustedKeys: [TrustedModelManifestKey]) {
        self.trustedKeys = trustedKeys
    }

    static let current: ProductionModelInstallConfiguration? = ProductionModelInstallConfiguration(
        trustedKeys: ProductionModelCatalogTrust.trustedKeys
    )
}

enum SystemPrivacySettingsDestination: String, Equatable {
    case microphone =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    case accessibility =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    var url: URL {
        URL(string: rawValue)!
    }
}

struct SystemPrivacySettingsOpener {
    @discardableResult
    static func open(
        _ destination: SystemPrivacySettingsDestination,
        workspace: NSWorkspace = .shared
    ) -> Bool {
        workspace.open(destination.url)
    }
}

enum ProductionPermissionRequester {
    private static let accessibilityPromptOption = "AXTrustedCheckOptionPrompt"

    static func requestMicrophone() async -> RuntimePermissionState {
        await MicrophonePermissionClient.live.requestAccess().runtimeState
    }

    static func requestAccessibilityPrompt() {
        let options = [
            accessibilityPromptOption: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func accessibilityState() -> RuntimePermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }
}

struct AccessibilityPermissionMonitor {
    let wait: () async throws -> Void
    let currentState: () -> RuntimePermissionState

    static let live = AccessibilityPermissionMonitor(
        wait: {
            try await Task.sleep(for: .seconds(1))
        },
        currentState: ProductionPermissionRequester.accessibilityState
    )

    func nextChange(from displayedState: RuntimePermissionState) async throws -> RuntimePermissionState {
        while true {
            try Task.checkCancellation()
            try await wait()
            let observedState = currentState()
            if observedState != displayedState {
                return observedState
            }
        }
    }
}

enum TextifyAppDragSource {
    static func pasteboardItem(for appURL: URL = Bundle.main.bundleURL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(appURL.dataRepresentation, forType: .fileURL)
        return item
    }
}

extension RuntimeModelReadiness {
    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    var isPreparing: Bool {
        switch self {
        case .loading, .warming:
            return true
        default:
            return false
        }
    }

    var settingsModelStatus: String {
        switch self {
        case .noActiveModel:
            return "Not selected"
        case .missing:
            return "Not installed"
        case .loading:
            return "Loading"
        case .warming:
            return "Preparing"
        case .ready:
            return "Ready"
        case .failed:
            return "Unavailable"
        case .revoked:
            return "Revoked"
        }
    }
}

extension RuntimePermissionState {
    var settingsStatusLabel: String {
        switch self {
        case .unknown:
            return "Not Granted"
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        }
    }

    func permissionRequestMessage(for name: String) -> String {
        switch self {
        case .unknown:
            return "\(name) permission is still pending."
        case .granted:
            return "\(name) permission granted."
        case .denied:
            return "\(name) permission is denied."
        }
    }
}

extension MicrophonePermissionStatus {
    var runtimeState: RuntimePermissionState {
        switch self {
        case .granted:
            return .granted
        case .notDetermined:
            return .unknown
        case .denied, .restricted:
            return .denied
        }
    }
}

private struct ModelCatalogSettingsPaneLayout<Content: View>: View {
    let title: String
    let subtitle: String
    let maxContentWidth: CGFloat
    let catalogViewportRestoration: ModelCatalogViewportRestoration?
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String,
        maxContentWidth: CGFloat,
        catalogViewportRestoration:
            ModelCatalogViewportRestoration?,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.maxContentWidth = maxContentWidth
        self.catalogViewportRestoration =
            catalogViewportRestoration
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TextifyPaneHeader(
                        title: title,
                        subtitle: subtitle
                    )
                    .padding(.bottom, 4)

                    content
                }
                .frame(
                    maxWidth: maxContentWidth,
                    alignment: .leading
                )
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 36)
                .frame(
                    maxWidth: .infinity,
                    alignment: .top
                )
            }
            .scrollContentBackground(.hidden)
            .background {
                TextifyAcousticBackdrop()
            }
            .task(id: catalogViewportRestoration) {
                guard let request = catalogViewportRestoration
                else {
                    return
                }
                await Task.yield()
                proxy.scrollTo(request.rowID, anchor: .top)
            }
        }
    }
}

private struct SettingsPaneLayout<Content: View>: View {
    let title: String
    let subtitleOverride: String?
    let maxContentWidth: CGFloat
    let catalogViewportRestoration: ModelCatalogViewportRestoration?
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String? = nil,
        maxContentWidth: CGFloat = TextifyWindowMetrics.readableContentWidth,
        catalogViewportRestoration:
            ModelCatalogViewportRestoration? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitleOverride = subtitle
        self.maxContentWidth = maxContentWidth
        self.catalogViewportRestoration = catalogViewportRestoration
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            paneScrollView
                .onChange(
                    of: catalogViewportRestoration?.generation
                ) { _, _ in
                    guard let request =
                            catalogViewportRestoration
                    else {
                        return
                    }
                    proxy.scrollTo(request.rowID, anchor: .top)
                }
        }
    }

    private var paneScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TextifyPaneHeader(title: title, subtitle: subtitle)
                    .padding(.bottom, 4)

                content
            }
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .background {
            TextifyAcousticBackdrop()
        }
    }

    private var subtitle: String {
        subtitleOverride
            ?? SettingsPane.productionVisiblePanes.first { $0.title == title }?.productionSubtitle
            ?? ""
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextifySectionLabel(title: title)
                .padding(.leading, 5)

            TextifyCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .labeledContentStyle(SettingsValueColumnStyle())
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct SettingsValueColumnStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 20) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)

            configuration.content
                .frame(width: 220, alignment: .trailing)
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let status: String
    let actionTitle: String?
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                .frame(width: 30, height: 30)
                .background(
                    TextifyVisualIdentity.voiceViolet.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            TextifyStatusBadge(
                title: status.uppercased(),
                tone: status == "Granted" ? .success : .warning
            )

            if status != "Granted", let actionTitle {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .disabled(isDisabled)
            }
        }
    }

    private var systemImage: String {
        name == "Microphone" ? "mic.fill" : "cursorarrow.rays"
    }

    private var detail: String {
        if name == "Microphone" {
            return "Captures speech only while your trigger is held."
        }
        return "Types completed dictation into the active app."
    }
}

private struct TriggerTestSummary: View {
    let result: TriggerTestSessionResult

    var body: some View {
        HStack(spacing: 8) {
            TriggerTestCheckpoint(title: "Key down", isComplete: result.sawDown)
            TriggerTestCheckpoint(
                title: "Recording",
                isComplete: result.sawBeginRecording
            )
            TriggerTestCheckpoint(title: "Released", isComplete: result.sawUp)
        }
    }
}

private struct TriggerTestCheckpoint: View {
    let title: String
    let isComplete: Bool

    var body: some View {
        Label(
            title,
            systemImage: isComplete ? "checkmark.circle.fill" : "circle"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(
            isComplete ? TextifyVisualIdentity.readyMint : Color.secondary
        )
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            isComplete
                ? TextifyVisualIdentity.readyMint.opacity(0.1)
                : TextifyVisualIdentity.raisedSurface.opacity(0.7),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
        }
    }
}
