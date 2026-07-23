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
            if services.startupIssue != nil {
                PersistentStorageUnavailableView()
            } else {
                HStack(spacing: 0) {
                    SettingsSidebar(selection: $router.selectedPane)

                    Divider()

                    paneView(for: router.selectedPane)
                        .id(router.selectedPane)
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
    }

    @ViewBuilder
    private func paneView(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsPane()
        case .dictation:
            DictationSettingsPane()
        case .models:
            ModelsSettingsPane()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TextifyVoiceMark(state: .processing, height: 22)

                Text("Textify")
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.horizontal, 24)
            .padding(.top, 45)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(SettingsPane.productionVisiblePanes) { pane in
                    Button {
                        selection = pane
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: pane.productionSystemImage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(selection == pane ? TextifyVisualIdentity.voiceViolet : Color.white.opacity(0.62))
                                .frame(width: 18)
                            Text(pane.sidebarTitle)
                                .font(.system(size: 15, weight: selection == pane ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selection == pane ? Color.white : Color.white.opacity(0.62))
                        .padding(.horizontal, 10)
                        .frame(height: 35)
                        .background(
                            selection == pane ? TextifyVisualIdentity.consoleSelection : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == pane ? .isSelected : [])

                    if pane == .models {
                        Divider()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.leading, 15)
            .padding(.trailing, 8)

            Spacer(minLength: 20)

            sidebarStatus
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: TextifyWindowMetrics.sidebarWidth)
        .background(TextifyVisualIdentity.sidebarSurface)
    }

    private var sidebarStatus: some View {
        let canDictate = services.dictation.readiness.canDictate
        return HStack(spacing: 8) {
            Circle()
                .fill(canDictate ? TextifyVisualIdentity.readyMint : TextifyVisualIdentity.warmWarning)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(TextifyReadinessPresentation.title(canDictate: canDictate))
                    .font(.system(size: 13, weight: .medium))
                Text(canDictate ? services.preferences.trigger.displayName : "Review setup requirements")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PersistentStorageUnavailableView: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

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

                    Text("Textify storage is unavailable")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(AppRuntimeIssue.persistentStorageUnavailable.userMessage)
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
}

extension SettingsPane {
    static let productionVisiblePanes: [SettingsPane] = [
        .general,
        .dictation,
        .models,
        .privacy,
        .logs,
        .advanced
    ]

    var productionSystemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .dictation:
            return "mic"
        case .models:
            return "externaldrive"
        case .privacy:
            return "hand.raised"
        case .logs:
            return "doc.text.magnifyingglass"
        case .advanced:
            return "slider.horizontal.3"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .general:
            return "General Settings"
        case .dictation:
            return "Dictation"
        case .models:
            return "Dictation Models"
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
            title: "General Preferences",
            subtitle: "Configure Textify to match your workflow and preferences."
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
            .padding(.top, 15)

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
                LabeledContent("Microphone", value: "System Default")
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
                if services.runtimeIssue == .hotkeyMonitorUnavailable {
                    Text(AppRuntimeIssue.hotkeyMonitorUnavailable.userMessage)
                        .foregroundStyle(.orange)
                    Button("Retry Trigger") {
                        services.startRuntime()
                    }
                }
            }
        }
        .onDisappear {
            triggerTest.stop()
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

private struct ModelsSettingsPane: View {
    @Environment(AppServices.self) private var services
    @State private var modelMessage: String?
    @State private var activatingModelID: String?
    @State private var pendingImportURL: URL?
    @State private var showsImportConfirmation = false
    @State private var isImporting = false
    @State private var pendingRemovalModel: ProductionModelPresentation?
    @State private var catalogSort: ModelCatalogSort = .catalog
    @State private var catalogFormat: ModelArtifactFormat?
    @State private var catalogPrecision: ModelArtifactPrecision?

    var body: some View {
        let installedModels = services.installedModels
        let completeCatalog = makeCatalog(installedModels: installedModels)
        let visibleCatalog = catalogQuery.apply(to: completeCatalog)
        let installedModelIDs = Set(installedModels.map(\.id))

        return SettingsPaneLayout(
            title: "Dictation Models",
            subtitle: "Choose how transcription runs on your Mac.",
            maxContentWidth: 1_360
        ) {
            if services.modelCatalogCoordinator.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading signed catalog")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else if let message = services.modelCatalogCoordinator.errorMessage ?? modelMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if ProductionModelInstallConfiguration.current == nil {
                Text("Signed catalog unavailable in this build")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ModelCatalogSurface(
                models: visibleCatalog,
                onReset: resetCatalogQuery
            ) { model in
                TextifyModelCard(
                    model: model,
                    isInstalled: installedModelIDs.contains(model.id),
                    isActive: services.isModelActive(model.id),
                    isActivating: activatingModelID == model.id,
                    isBusy: activatingModelID != nil || isInstalling || isImporting,
                    installState: ModelInstallRowPresentation.state(
                        for: model.id,
                        from: services.modelInstallCoordinator.state
                    ),
                    onUse: {
                        activatingModelID = model.id
                        Task {
                            let activated = await services.activateInstalledModel(model.id)
                            modelMessage = activated
                                ? model.activationMessage
                                : "Textify kept the previous model because \(model.displayName) could not be prepared."
                            activatingModelID = nil
                        }
                    },
                    onDisable: {
                        Task {
                            await services.disableVoiceCleaning()
                            modelMessage = "Voice cleaning is off."
                        }
                    },
                    onInstall: {
                        services.modelInstallCoordinator.start(modelID: model.id)
                    },
                    onCancelInstall: {
                        services.modelInstallCoordinator.cancel()
                    },
                    onRetryInstall: {
                        services.modelInstallCoordinator.retry()
                    },
                    onDelete: {
                        pendingRemovalModel = model
                    }
                )
            }

        }
        .overlay(alignment: .topTrailing) {
            ModelCatalogToolbar(
                sort: $catalogSort,
                format: $catalogFormat,
                precision: $catalogPrecision,
                onReset: resetCatalogQuery,
                onVerify: {
                    Task {
                        _ = await services.dictation.refreshReadiness()
                        modelMessage = services.dictation.readiness.model.settingsModelStatus
                    }
                },
                onImport: chooseCustomWhisperModel,
                isImportDisabled: isInstalling || isImporting
            )
            .padding(.top, 48)
            .padding(.trailing, 24)
        }
        .task {
            _ = await services.dictation.refreshReadiness()
            await services.modelCatalogCoordinator.refresh()
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
            "Delete installed model?",
            isPresented: Binding(
                get: { pendingRemovalModel != nil },
                set: { if !$0 { pendingRemovalModel = nil } }
            ),
            presenting: pendingRemovalModel
        ) { model in
            Button("Cancel", role: .cancel) {
                pendingRemovalModel = nil
            }
            Button("Delete", role: .destructive) {
                pendingRemovalModel = nil
                Task {
                    do {
                        try await services.removeInstalledModel(model.id)
                        modelMessage = "\(model.displayName) was deleted."
                    } catch {
                        modelMessage = error.localizedDescription
                    }
                }
            }
        } message: { model in
            Text("This removes \(model.displayName) from this Mac. You can download it again later.")
        }
    }

    private var isInstalling: Bool {
        services.modelInstallCoordinator.isActive
    }

    private func makeCatalog(installedModels: [ModelEntry]) -> [ProductionModelPresentation] {
        let models = services.modelCatalogCoordinator.models
        let signedCatalog = models.isEmpty
            ? ProductionModelPresentation.visibleCatalog
            : models.map { ProductionModelPresentation(model: $0) }
        let signedIDs = Set(signedCatalog.map(\.id))
        let completeCatalog = signedCatalog + installedModels
            .filter { !signedIDs.contains($0.id) }
            .map { ProductionModelPresentation(model: $0, isCurated: false) }
        let activeIDs = [
            services.preferences.activeModelID,
            services.preferences.activeVoiceCleaningModelID,
        ].compactMap { $0 }
        var orderedCatalog = completeCatalog
        for activeID in activeIDs.reversed() {
            guard let activeIndex = orderedCatalog.firstIndex(where: { $0.id == activeID }) else {
                continue
            }
            let activeModel = orderedCatalog.remove(at: activeIndex)
            orderedCatalog.insert(activeModel, at: 0)
        }
        return orderedCatalog
    }

    private var catalogQuery: ModelCatalogQuery {
        ModelCatalogQuery(
            sort: catalogSort,
            format: catalogFormat,
            precision: catalogPrecision
        )
    }

    private func resetCatalogQuery() {
        catalogSort = .catalog
        catalogFormat = nil
        catalogPrecision = nil
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

private struct ModelCatalogToolbar: View {
    @Binding var sort: ModelCatalogSort
    @Binding var format: ModelArtifactFormat?
    @Binding var precision: ModelArtifactPrecision?
    let onReset: () -> Void
    let onVerify: () -> Void
    let onImport: () -> Void
    let isImportDisabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Picker("Sort models", selection: $sort) {
                ForEach(ModelCatalogSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 210)

            Menu {
                Menu("Format") {
                    Picker("Format", selection: $format) {
                        Text("All formats").tag(ModelArtifactFormat?.none)
                        ForEach(ModelArtifactFormat.filterOptions) { option in
                            Text(option.title).tag(Optional(option))
                        }
                    }
                }
                Menu("Precision") {
                    Picker("Precision", selection: $precision) {
                        Text("All precision").tag(ModelArtifactPrecision?.none)
                        ForEach(ModelArtifactPrecision.filterOptions) { option in
                            Text(option.title).tag(Optional(option))
                        }
                    }
                }
                if hasChanges {
                    Button("Reset Filters", systemImage: "arrow.counterclockwise", action: onReset)
                }
                Divider()
                Button("Verify Installed", systemImage: "checkmark.seal", action: onVerify)
                Button("Import Whisper Model…", systemImage: "square.and.arrow.down", action: onImport)
                    .disabled(isImportDisabled)
            } label: {
                Image(systemName: hasFilters ? "ellipsis.circle.fill" : "ellipsis.circle")
                    .font(.system(size: 15, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
    }

    private var hasFilters: Bool {
        format != nil || precision != nil
    }

    private var hasChanges: Bool {
        sort != .catalog || hasFilters
    }
}

private struct ModelCatalogSurface<Row: View>: View {
    let models: [ProductionModelPresentation]
    let onReset: () -> Void
    let row: (ProductionModelPresentation) -> Row

    init(
        models: [ProductionModelPresentation],
        onReset: @escaping () -> Void,
        @ViewBuilder row: @escaping (ProductionModelPresentation) -> Row
    ) {
        self.models = models
        self.onReset = onReset
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ModelCatalogColumnHeader()
            Divider()
            if models.isEmpty {
                ModelCatalogEmptyState(onReset: onReset)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(models) { model in
                        row(model)
                    }
                }
            }
        }
        .background(TextifyVisualIdentity.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
        }
    }
}

private struct ModelCatalogEmptyState: View {
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(TextifyVisualIdentity.voiceViolet)
            Text("No models match these filters")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Text("Reset the catalog controls to see every local model.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Reset Filters", action: onReset)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .accessibilityElement(children: .contain)
    }
}

private struct ModelCatalogColumnHeader: View {
    var body: some View {
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
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .tracking(0.9)
        .foregroundStyle(.secondary)
        .padding(.leading, 94)
        .padding(.trailing, 14)
        .frame(height: 38)
        .background(Color.white.opacity(0.015))
        .accessibilityHidden(true)
    }
}

private struct TextifyModelCard: View {
    let model: ProductionModelPresentation
    let isInstalled: Bool
    let isActive: Bool
    let isActivating: Bool
    let isBusy: Bool
    let installState: DownloadState?
    let onUse: () -> Void
    let onDisable: () -> Void
    let onInstall: () -> Void
    let onCancelInstall: () -> Void
    let onRetryInstall: () -> Void
    let onDelete: () -> Void

    @State private var showsDetails = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ModelSelectionIndicator(isInstalled: isInstalled, isActive: showsSelectedTreatment)

                ModelProviderTile(provider: model.provider, isActive: showsSelectedTreatment)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(model.catalogDisplayName)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        TextifyStatusBadge(title: model.supportTier.uppercased(), tone: tierTone)
                        if !model.isCurated {
                            TextifyStatusBadge(title: "NO LONGER CURATED", tone: .warning)
                        }
                    }
                    Text(model.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ModelSignalMetric(level: model.qualitySignalLevel, label: model.qualityLabel)
                    .frame(width: 86, alignment: .leading)
                ModelSignalMetric(level: model.speedSignalLevel, label: model.speedLabel)
                    .frame(width: 86, alignment: .leading)
                ModelFeaturesMetric(model: model)
                    .frame(width: 138, alignment: .leading)
            }

            HStack(spacing: 10) {
                Spacer()
                    .frame(width: 76)

                if isActivating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Preparing model")
                } else if isActive {
                    Label(model.activeLabel, systemImage: "waveform.badge.checkmark")
                        .foregroundStyle(TextifyVisualIdentity.readyMint)
                    if model.purpose == .voiceCleaning {
                        Button("Disable", systemImage: "power", action: onDisable)
                            .disabled(isBusy)
                    }
                } else if isInstalled {
                    Button(model.useLabel, systemImage: "waveform", action: onUse)
                        .disabled(isBusy)
                }

                if installState == nil {
                    if isInstalled {
                        Button("Reinstall", systemImage: "arrow.clockwise", action: onInstall)
                            .disabled(isBusy || ProductionModelInstallConfiguration.current == nil)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(model.installLabel, systemImage: "arrow.down.circle", action: onInstall)
                            .disabled(isBusy || ProductionModelInstallConfiguration.current == nil)
                    }
                }

                if isInstalled {
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        .disabled(isActive || isBusy)
                        .foregroundStyle(TextifyVisualIdentity.recordCoral)
                }

                Button(showsDetails ? "Hide Details" : "Details", systemImage: "info.circle") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        showsDetails.toggle()
                    }
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .font(.callout)
            .buttonStyle(.borderless)

            if let installState {
                ModelCardInstallProgress(
                    state: installState,
                    onCancel: onCancelInstall,
                    onRetry: onRetryInstall
                )
                .padding(.leading, 76)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showsDetails {
                ModelDetailGrid(model: model)
                    .padding(.leading, 76)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 102, alignment: .topLeading)
        .background(activeBackground)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 94)
        }
        .accessibilityElement(children: .contain)
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

enum ModelInstallRowPresentation {
    static func state(for modelID: String, from state: DownloadState?) -> DownloadState? {
        guard let state, state.modelID == modelID, state.phase != .installed else {
            return nil
        }
        return state
    }

    static func offersCancel(for state: DownloadState) -> Bool {
        state.isActive
    }

    static func offersRetry(for state: DownloadState) -> Bool {
        switch state.phase {
        case .interrupted, .failed, .cancelled:
            return true
        case .checkingSpace, .downloading, .verifying, .installing, .installed:
            return false
        }
    }
}

private struct ModelCardInstallProgress: View {
    let state: DownloadState
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(ModelInstallProgressPresentation.title(for: state), systemImage: phaseIcon)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(statusColor)

                if let percentText = ModelInstallProgressPresentation.percentText(for: state) {
                    Text(percentText)
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 8)

                if ModelInstallRowPresentation.offersCancel(for: state) {
                    Button("Cancel", systemImage: "xmark.circle", action: onCancel)
                } else if ModelInstallRowPresentation.offersRetry(for: state) {
                    Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
                }
            }

            if state.totalBytes > 0 {
                ProgressView(value: ModelInstallProgressPresentation.progressValue(for: state), total: 1)
                    .tint(statusColor)
            } else if state.isActive {
                ProgressView()
                    .controlSize(.small)
                    .tint(statusColor)
            }

            Text(ModelInstallProgressPresentation.detailText(for: state))
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
    }

    private var statusColor: Color {
        switch state.phase {
        case .interrupted, .failed:
            return TextifyVisualIdentity.recordCoral
        case .cancelled:
            return TextifyVisualIdentity.slate
        case .checkingSpace, .downloading, .verifying, .installing, .installed:
            return TextifyVisualIdentity.voiceViolet
        }
    }

    private var phaseIcon: String {
        switch state.phase {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(model.sizeDescription, systemImage: "internaldrive")
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

    var body: some View {
        SettingsPaneLayout(title: "Privacy") {
            SettingsSection("Permissions") {
                PermissionRow(
                    name: "Microphone",
                    status: services.dictation.readiness.permissions.microphone.settingsStatusLabel,
                    actionTitle: "Request Access"
                ) {
                    Task {
                        let state = await ProductionPermissionRequester.requestMicrophone()
                        permissionMessage = state.permissionRequestMessage(for: "Microphone")
                        _ = await services.dictation.refreshReadiness()
                    }
                }

                Divider()

                PermissionRow(
                    name: "Accessibility",
                    status: services.dictation.readiness.permissions.accessibility.settingsStatusLabel,
                    actionTitle: "Open Prompt"
                ) {
                    ProductionPermissionRequester.requestAccessibilityPrompt()
                    Task {
                        _ = await services.dictation.refreshReadiness()
                        permissionMessage = services.dictation.readiness.permissions.accessibility
                            .permissionRequestMessage(for: "Accessibility")
                    }
                }

                if services.dictation.readiness.permissions.accessibility != .granted {
                    Divider()
                    AccessibilityAppDragSource()
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
    }

    private func monitorAccessibilityPermission() async {
        var displayedState = await refreshPermissionState()

        while !Task.isCancelled {
            do {
                _ = try await AccessibilityPermissionMonitor.live.nextChange(from: displayedState)
            } catch {
                return
            }
            displayedState = await refreshPermissionState()
        }
    }

    private func refreshPermissionState() async -> RuntimePermissionState {
        let previousState = services.dictation.readiness.permissions.accessibility
        let snapshot = await services.dictation.refreshReadiness()
        let updatedState = snapshot.permissions.accessibility

        if previousState != updatedState,
           permissionMessage?.hasPrefix("Accessibility") == true {
            permissionMessage = updatedState.permissionRequestMessage(for: "Accessibility")
        }
        return updatedState
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

private struct AccessibilityAppDragSource: View {
    private let appURL = Bundle.main.bundleURL

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
                .accessibilityHidden(true)
        }
        .help("Drag Textify into the Accessibility apps list")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drag Textify into the Accessibility apps list")
        .accessibilityHint("Drop Textify in System Settings, then turn it on.")
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
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                if let reasonCode = entry.reasonCode {
                    Text(reasonCode.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tone)
                }

                Text(entry.json)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
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

            SettingsSection("Timing") {
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

enum ModelCatalogSort: String, CaseIterable, Identifiable {
    case catalog
    case quality
    case speed

    var id: Self { self }

    var title: String {
        switch self {
        case .catalog: "Catalog"
        case .quality: "Quality"
        case .speed: "Speed"
        }
    }
}

enum ModelArtifactFormat: String, CaseIterable, Identifiable {
    case mlx
    case gguf
    case other

    static let filterOptions: [ModelArtifactFormat] = [.mlx, .gguf]

    var id: Self { self }

    var title: String {
        switch self {
        case .mlx: "MLX"
        case .gguf: "GGUF"
        case .other: "Other"
        }
    }
}

enum ModelArtifactPrecision: String, CaseIterable, Identifiable {
    case thirtyTwoBit
    case sixteenBit
    case eightBit
    case fiveBit
    case fourBit
    case other

    static let filterOptions: [ModelArtifactPrecision] = [
        .thirtyTwoBit,
        .sixteenBit,
        .eightBit,
        .fiveBit,
        .fourBit,
    ]

    var id: Self { self }

    var title: String {
        switch self {
        case .thirtyTwoBit: "32-bit"
        case .sixteenBit: "16-bit"
        case .eightBit: "8-bit"
        case .fiveBit: "5-bit"
        case .fourBit: "4-bit"
        case .other: "Other"
        }
    }
}

struct ModelCatalogQuery: Equatable {
    var sort: ModelCatalogSort = .catalog
    var format: ModelArtifactFormat?
    var precision: ModelArtifactPrecision?

    func apply(to models: [ProductionModelPresentation]) -> [ProductionModelPresentation] {
        let matches = models.enumerated().filter { _, model in
            (format == nil || model.artifactFormat == format)
                && (precision == nil || model.artifactPrecision == precision)
        }

        switch sort {
        case .catalog:
            return matches.map(\.element)
        case .quality:
            return matches.sorted { lhs, rhs in
                if lhs.element.qualityScore != rhs.element.qualityScore {
                    return (lhs.element.qualityScore ?? -1)
                        > (rhs.element.qualityScore ?? -1)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        case .speed:
            return matches.sorted { lhs, rhs in
                if lhs.element.speedScore != rhs.element.speedScore {
                    return (lhs.element.speedScore ?? -1)
                        > (rhs.element.speedScore ?? -1)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        }
    }
}

enum ModelProviderIdentity: String, Equatable {
    case openAI
    case nvidia
    case cohere
    case qwen
    case alibaba
    case apple
    case mlx
    case reazon
    case mossFormer
    case community

    var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .nvidia: "NVIDIA"
        case .cohere: "Cohere"
        case .qwen: "Qwen by Alibaba Cloud"
        case .alibaba: "Alibaba Cloud"
        case .apple: "Apple"
        case .mlx: "Apple MLX"
        case .reazon: "Reazon Human Interaction Lab"
        case .mossFormer: "Alibaba Speech Lab"
        case .community: "Open model"
        }
    }

    var logoAssetName: String? {
        switch self {
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

struct ProductionModelPresentation: Equatable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let details: String?
    let isCurated: Bool
    let supportTier: String
    let expectedFinalization: String
    let accuracyTradeoff: String
    let requirements: String
    let artifactFormat: ModelArtifactFormat
    let artifactPrecision: ModelArtifactPrecision
    let engineName: String
    let engineIcon: String
    let acceleratorName: String
    let sizeDescription: String
    let languageDescription: String
    let licenseDescription: String
    let sourceName: String
    let sourceURL: URL?
    let artifactName: String
    let checksum: String?
    let purpose: ModelPurpose
    let benchmark: ModelBenchmarkRating?

    init(
        id: String,
        displayName: String,
        description: String,
        details: String?,
        isCurated: Bool = true,
        supportTier: String = "Custom",
        expectedFinalization: String = "Varies by model",
        accuracyTradeoff: String = "See model description",
        requirements: String = "Apple Silicon",
        artifactFormat: ModelArtifactFormat = .other,
        artifactPrecision: ModelArtifactPrecision = .other,
        engineName: String = "Local runtime",
        engineIcon: String = "waveform.circle",
        acceleratorName: String = "Apple Silicon",
        sizeDescription: String = "Local",
        languageDescription: String = "Varies",
        licenseDescription: String = "See source",
        sourceName: String = "Model source",
        sourceURL: URL? = nil,
        artifactName: String = "Local model",
        checksum: String? = nil,
        purpose: ModelPurpose = .transcription,
        benchmark: ModelBenchmarkRating? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.details = details
        self.isCurated = isCurated
        self.supportTier = supportTier
        self.expectedFinalization = expectedFinalization
        self.accuracyTradeoff = accuracyTradeoff
        self.requirements = requirements
        self.artifactFormat = artifactFormat
        self.artifactPrecision = artifactPrecision
        self.engineName = engineName
        self.engineIcon = engineIcon
        self.acceleratorName = acceleratorName
        self.sizeDescription = sizeDescription
        self.languageDescription = languageDescription
        self.licenseDescription = licenseDescription
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.artifactName = artifactName
        self.checksum = checksum
        self.purpose = purpose
        self.benchmark = benchmark
    }

    static let v1_1 = ProductionModelPresentation(
        id: ProductionModelPolicy.requiredModelID,
        displayName: "Balanced - Whisper small.en q5_1",
        description: "Local English dictation model for Textify V1.1.",
        details: "Whisper.cpp • Metal GPU • English",
        supportTier: "Recommended",
        expectedFinalization: "Near-instant after release",
        accuracyTradeoff: "Balanced English speed and accuracy",
        requirements: "Apple Silicon • about 182 MB download",
        artifactPrecision: .fiveBit,
        engineName: "Whisper.cpp",
        engineIcon: "waveform.circle",
        acceleratorName: "Metal GPU",
        sizeDescription: "182 MB",
        languageDescription: "English",
        licenseDescription: "MIT",
        sourceName: "ggerganov/whisper.cpp",
        artifactName: "ggml-small.en-q5_1.bin"
    )

    static let visibleCatalog: [ProductionModelPresentation] = [v1_1]

    init(model: ModelEntry, isCurated: Bool = true) {
        id = model.id
        displayName = model.displayName
        description = model.description
        purpose = model.purpose
        self.isCurated = isCurated
        artifactFormat = Self.artifactFormat(for: model)
        artifactPrecision = Self.artifactPrecision(for: model)
        let enginePresentation = switch model.runtime.engine {
        case .whisperCpp: ("Whisper.cpp", "waveform.circle")
        case .fluidAudioParakeet: ("Parakeet", "bolt.horizontal.circle")
        case .fluidAudioParaformer: ("Paraformer", "character.waveform")
        case .sherpaOnnx: ("sherpa-onnx", "point.3.connected.trianglepath.dotted")
        case .transcribeCpp: ("transcribe.cpp", "cpu")
        case .mlxAudio: ("MLX Audio", "sparkles.rectangle.stack")
        case .liteRTLM: ("LiteRT-LM", "cube.transparent")
        }
        engineName = enginePresentation.0
        engineIcon = enginePresentation.1
        acceleratorName = switch model.runtime.accelerator {
        case .metalGPU: "Metal GPU"
        case .coreMLNeuralEngine: "Core ML / Neural Engine"
        case .cpu: "Apple Silicon CPU"
        }
        languageDescription = Self.languageDescription(for: model.capabilities.languages)
        sizeDescription = ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
        let license = model.licenses.first?.name ?? "License metadata unavailable"
        details = "\(engineName) • \(acceleratorName) • \(languageDescription) • \(sizeDescription) • \(license)"
        licenseDescription = model.licenses.map(\.spdxId).joined(separator: " + ")
        sourceName = model.provenance.sourceName
        sourceURL = Self.publicSourceURL(from: model.provenance.sourceUrl)
        artifactName = model.files.count == 1
            ? (model.files.first?.filename ?? "Model artifact")
            : "\(model.files.count) signed files"
        checksum = model.files.first?.sha256
        supportTier = Self.supportTier(for: model.tier)
        expectedFinalization = model.presentation?.expectedFinalization
            ?? Self.fallbackFinalization(for: model.tier)
        accuracyTradeoff = model.presentation?.accuracyTradeoff ?? model.description
        requirements = model.presentation?.requirements ?? "Apple Silicon • \(acceleratorName)"
        benchmark = model.benchmark
    }

    var qualitySignalLevel: Int {
        benchmark?.quality.level ?? 0
    }

    var catalogDisplayName: String {
        let parts = displayName.split(separator: "-", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let tierPrefixes = ["Accurate", "Balanced", "Experimental", "Fast", "Recommended", "Specialist"]
        guard parts.count == 2, tierPrefixes.contains(parts[0]) else {
            return displayName
        }
        return parts[1]
    }

    var provider: ModelProviderIdentity {
        let identity = "\(displayName) \(sourceName) \(engineName)".lowercased()
        if identity.contains("cohere") {
            return .cohere
        }
        if identity.contains("parakeet") || identity.contains("canary") || identity.contains("nemotron") {
            return .nvidia
        }
        if identity.contains("whisper") {
            return .openAI
        }
        if identity.contains("qwen") {
            return .qwen
        }
        if identity.contains("paraformer") || identity.contains("sensevoice") || identity.contains("mossformer") {
            return .alibaba
        }
        if identity.contains("reazon") {
            return .reazon
        }
        if identity.contains("apple") {
            return .apple
        }
        if identity.contains("mlx") {
            return .mlx
        }
        return .community
    }

    var activationMessage: String {
        purpose == .voiceCleaning
            ? "\(displayName) is enabled before dictation."
            : "\(displayName) is active and ready."
    }

    var activeLabel: String {
        purpose == .voiceCleaning ? "Cleaning Enabled" : "Active"
    }

    var useLabel: String {
        purpose == .voiceCleaning ? "Use Cleaner" : "Use Model"
    }

    var installLabel: String {
        purpose == .voiceCleaning ? "Install & Enable" : "Install"
    }

    var speedSignalLevel: Int {
        benchmark?.speed?.level ?? 0
    }

    var qualityLabel: String {
        benchmark?.quality.label ?? "Unrated"
    }

    var speedLabel: String {
        benchmark?.speed?.label ?? "Unrated"
    }

    var qualityScore: Int? {
        benchmark?.quality.score
    }

    var speedScore: Int? {
        benchmark?.speed?.score
    }

    var qualityEvidenceDescription: String? {
        guard let quality = benchmark?.quality else {
            return nil
        }
        return "\(quality.score)/100 • \(quality.label) • \(quality.speechItems) speech cases"
    }

    var wordErrorRateDescription: String {
        benchmark?.quality.components.map {
            "\(Self.benchmarkComponentName($0.id)) \(Self.percent($0.wordErrorRate))"
        }.joined(separator: " • ") ?? "Unrated"
    }

    var noSpeechEvidenceDescription: String {
        guard let quality = benchmark?.quality else {
            return "Unrated"
        }
        return "\(quality.noSpeechItems) cases • \(Self.percent(quality.noSpeechFalsePositiveRate)) false positives"
    }

    var speedEvidenceDescription: String? {
        guard let speed = benchmark?.speed else {
            if benchmark?.speedUnratedReason != nil {
                return "Unrated — repeated-run p95 was unstable"
            }
            return nil
        }
        return "\(speed.score)/100 • p50 \(speed.p50ReleaseToFinalMs) ms • p95 \(speed.p95ReleaseToFinalMs) ms • p95 RTF \(String(format: "%.3f", speed.p95RealTimeFactor))"
    }

    var benchmarkProvenanceDescription: String? {
        guard let benchmark else {
            return nil
        }
        return "\(benchmark.measuredAt) • \(benchmark.referenceHost.chip) • \(benchmark.referenceHost.operatingSystem)"
    }

    var benchmarkPolicyDescription: String {
        guard let benchmark else {
            return "Unrated"
        }
        return "\(benchmark.policyID) • \(benchmark.runCount) runs • suite \(benchmark.suiteIndexSHA256.prefix(12)) • source \(benchmark.sourceRevision.prefix(12))"
    }

    var benchmarkRuntimeDescription: String {
        guard let benchmark else {
            return "Unrated"
        }
        return "\(benchmark.engine) • \(benchmark.engineVersion) • \(benchmark.computeBackend)"
    }

    private static func supportTier(for tier: String) -> String {
        switch tier.lowercased() {
        case "balanced", "recommended": "Recommended"
        case "fast": "Fast"
        case "accurate": "Accurate"
        case "specialist": "Specialist"
        case "experimental": "Experimental"
        case "custom": "Custom"
        default: "Experimental"
        }
    }

    private static func benchmarkComponentName(_ id: String) -> String {
        switch id {
        case "open-asr-english-nightly-v1": "Open ASR"
        case "edacc-english-nightly-v1": "EdAcc"
        case "berst-english-nightly-v1": "BERSt"
        default: id
        }
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private static func fallbackFinalization(for tier: String) -> String {
        switch tier.lowercased() {
        case "fast": "Fastest available tier"
        case "balanced", "recommended": "Near-instant after release"
        case "accurate": "May take longer for higher accuracy"
        case "specialist": "Varies by specialist model"
        default: "Experimental; benchmark data incomplete"
        }
    }

    private static func artifactFormat(for model: ModelEntry) -> ModelArtifactFormat {
        if model.runtime.engine == .mlxAudio {
            return .mlx
        }
        if model.files.contains(where: { $0.filename.lowercased().hasSuffix(".gguf") }) {
            return .gguf
        }
        return .other
    }

    private static func artifactPrecision(for model: ModelEntry) -> ModelArtifactPrecision {
        let searchableMetadata = ([
            model.id,
            model.displayName,
            model.description,
            model.runtime.variant,
            model.provenance.sourceFile,
        ] + model.files.map(\.filename))
            .joined(separator: " ")
            .lowercased()

        let precisionPatterns: [(ModelArtifactPrecision, [String])] = [
            (.thirtyTwoBit, ["fp32", "f32", "32-bit", "32bit"]),
            (.sixteenBit, ["fp16", "bf16", "f16", "16-bit", "16bit"]),
            (.eightBit, ["q8", "int8", "8-bit", "8bit"]),
            (.fiveBit, ["q5", "5-bit", "5bit"]),
            (.fourBit, ["q4", "int4", "4-bit", "4bit"]),
        ]

        return precisionPatterns.first { _, patterns in
            patterns.contains(where: searchableMetadata.contains)
        }?.0 ?? .other
    }

    private static func languageDescription(for languageCodes: [String]) -> String {
        if languageCodes == ["*"] {
            return "Language agnostic"
        }
        guard languageCodes.count == 1, let code = languageCodes.first else {
            return "\(languageCodes.count) languages"
        }
        return switch code.lowercased() {
        case "en": "English"
        case "ja": "Japanese"
        case "zh": "Chinese"
        default: code.uppercased()
        }
    }

    private static func publicSourceURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        return url
    }
}

struct ProductionModelInstallConfiguration: Equatable {
    let manifestURL: URL
    let signatureURL: URL
    let trustedKeys: [TrustedModelManifestKey]

    static let current: ProductionModelInstallConfiguration? = ProductionModelInstallConfiguration(
        manifestURL: URL(string: "https://player0109.github.io/Textify/models/manifest.json")!,
        signatureURL: URL(string: "https://player0109.github.io/Textify/models/manifest.json.sig")!,
        trustedKeys: [
            TrustedModelManifestKey(
                keyId: "textify-model-manifest-2026-primary",
                publicKeyBase64: "mLO7nEpXKrM6LkuQrMrpXtGDaJFEQWQivS9Hxm8RWY0="
            ),
            TrustedModelManifestKey(
                keyId: "textify-model-manifest-2026-reserve",
                publicKeyBase64: "4U2qV+TakjtL2HleKRPAhpd9LTTIfhGEmvZR4Opc1ZM="
            ),
            TrustedModelManifestKey(
                keyId: "textify-model-manifest-2026-huggingface",
                publicKeyBase64: "eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="
            )
        ]
    )
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

private struct SettingsPaneLayout<Content: View>: View {
    let title: String
    let subtitleOverride: String?
    let maxContentWidth: CGFloat
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String? = nil,
        maxContentWidth: CGFloat = TextifyWindowMetrics.readableContentWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitleOverride = subtitle
        self.maxContentWidth = maxContentWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextifyPaneHeader(title: title, subtitle: subtitle)
                    .padding(.bottom, 6)

                content
            }
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 19)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .background(TextifyVisualIdentity.windowSurface)
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
        VStack(alignment: .leading, spacing: 22) {
            TextifySectionLabel(title: title)
                .padding(.leading, 10)

            TextifyCard(padding: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
    }
}

private struct PermissionRow: View {
    let name: String
    let status: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            TextifyStatusBadge(
                title: status.uppercased(),
                tone: status == "Granted" ? .success : .warning
            )
            Button(actionTitle, action: action)
        }
    }
}

private struct TriggerTestSummary: View {
    let result: TriggerTestSessionResult

    var body: some View {
        HStack(spacing: 14) {
            Label("Down", systemImage: result.sawDown ? "checkmark.circle.fill" : "circle")
            Label("Start", systemImage: result.sawBeginRecording ? "checkmark.circle.fill" : "circle")
            Label("Release", systemImage: result.sawUp ? "checkmark.circle.fill" : "circle")
        }
        .foregroundStyle(result.passed ? .green : .secondary)
    }
}
