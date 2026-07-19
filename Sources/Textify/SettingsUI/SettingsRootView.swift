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
                TabView(selection: $router.selectedPane) {
                    ForEach(SettingsPane.productionVisiblePanes) { pane in
                        paneView(for: pane)
                            .tabItem {
                                Label(pane.title, systemImage: pane.productionSystemImage)
                            }
                            .tag(pane)
                    }
                }
            }
        }
        .frame(width: 680, height: 500)
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
        case .advanced:
            AdvancedSettingsPane()
        }
    }
}

struct PersistentStorageUnavailableView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("Textify Storage Is Unavailable")
                .font(.title2.bold())
            Text(AppRuntimeIssue.persistentStorageUnavailable.userMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Button("Quit Textify") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(32)
    }
}

extension SettingsPane {
    static let productionVisiblePanes: [SettingsPane] = [
        .general,
        .dictation,
        .models,
        .privacy,
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
        case .advanced:
            return "slider.horizontal.3"
        }
    }
}

private struct GeneralSettingsPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var services = services

        SettingsPaneLayout(title: "General") {
            SettingsSection("Startup") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .disabled(!services.canChangeLaunchAtLogin)
                Text(launchAtLoginStatusText)
                    .foregroundStyle(.secondary)
                launchAtLoginAction
            }

            SettingsSection("Dock") {
                Toggle(
                    DockPreferencePresentation.title,
                    isOn: $services.preferences.keepTextifyInDock
                )
                Text("Quit and reopen Textify to apply this change.")
                    .foregroundStyle(.secondary)
                Button("Quit Textify") {
                    NSApplication.shared.terminate(nil)
                }
            }

            SettingsSection("Version") {
                LabeledContent("App Version", value: appVersion)
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
                Picker("Dictation Trigger", selection: triggerBinding) {
                    ForEach(TextifySettings.TriggerPreference.allCases, id: \.self) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }
                Picker("Language", selection: languageBinding) {
                    ForEach(services.availableTranscriptionLanguages, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                LabeledContent("Microphone", value: "System Default")
            }

            SettingsSection("Trigger Test") {
                HStack(spacing: 12) {
                    Button(triggerTest.isRunning ? "Restart Test" : "Start Test") {
                        triggerTest.start(suspending: services)
                    }

                    Button("Stop Test") {
                        triggerTest.stop()
                    }
                    .disabled(!triggerTest.isRunning)
                }

                TriggerTestSummary(result: triggerTest.result)
                Text(triggerTest.statusText)
                    .foregroundStyle(triggerTest.result.passed ? .green : .secondary)
            }

            SettingsSection("Runtime") {
                LabeledContent("Status", value: services.dictation.status.menuStatusTitle)
                LabeledContent("Readiness", value: services.dictation.readiness.canDictate ? "Ready" : "Setup Required")
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

    var body: some View {
        SettingsPaneLayout(title: "Models") {
            SettingsSection("Active Model") {
                LabeledContent("Model", value: activeModel?.displayName ?? "None")
                LabeledContent("Identifier", value: services.preferences.activeModelID ?? "Not selected")
                LabeledContent("Status", value: services.dictation.readiness.model.settingsModelStatus)
            }

            SettingsSection("Curated Models") {
                ForEach(catalog) { model in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.displayName)
                            .font(.headline)
                        Text(model.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.description)
                            .foregroundStyle(.secondary)

                        Text(model.supportTier)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let details = model.details {
                            Text(details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("Finalization", value: model.expectedFinalization)
                            .font(.caption)
                        LabeledContent("Accuracy", value: model.accuracyTradeoff)
                            .font(.caption)
                        LabeledContent("Requires", value: model.requirements)
                            .font(.caption)

                        HStack(spacing: 10) {
                            if services.isModelInstalled(model.id) {
                                Button(services.preferences.activeModelID == model.id ? "Active" : "Use") {
                                    activatingModelID = model.id
                                    Task {
                                        let activated = await services.activateInstalledModel(model.id)
                                        modelMessage = activated
                                            ? "\(model.displayName) is active and ready."
                                            : "Textify kept the previous model because \(model.displayName) could not be prepared."
                                        activatingModelID = nil
                                    }
                                }
                                .disabled(
                                    services.preferences.activeModelID == model.id
                                        || activatingModelID != nil
                                        || isInstalling
                                )
                            }

                            Button(services.isModelInstalled(model.id) ? "Reinstall" : "Install") {
                                services.modelInstallCoordinator.start(modelID: model.id)
                            }
                            .disabled(isInstalling || ProductionModelInstallConfiguration.current == nil)

                            if services.isModelInstalled(model.id) {
                                Button("Delete", role: .destructive) {
                                    pendingRemovalModel = model
                                }
                                .disabled(
                                    services.preferences.activeModelID == model.id
                                        || isInstalling
                                        || isImporting
                                )
                            }
                        }
                    }
                }

                if services.modelCatalogCoordinator.isLoading {
                    ProgressView("Loading signed catalog")
                        .controlSize(.small)
                } else if let errorMessage = services.modelCatalogCoordinator.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Install") {
                HStack(spacing: 12) {
                    Button("Verify Installed Model") {
                        Task {
                            _ = await services.dictation.refreshReadiness()
                            modelMessage = services.dictation.readiness.model.settingsModelStatus
                        }
                    }

                    Button(isImporting ? "Importing" : "Import Whisper GGML/GGUF") {
                        chooseCustomWhisperModel()
                    }
                    .disabled(isInstalling || isImporting)

                    if isInstalling {
                        Button("Cancel") {
                            services.modelInstallCoordinator.cancel()
                        }
                    } else if services.modelInstallCoordinator.state?.phase == .failed
                        || services.modelInstallCoordinator.state?.phase == .cancelled {
                        Button("Retry") {
                            services.modelInstallCoordinator.retry()
                        }
                    }
                }

                if ProductionModelInstallConfiguration.current == nil {
                    Text("Signed model manifest is not configured in this build.")
                        .foregroundStyle(.secondary)
                }

                if let modelDownloadState = services.modelInstallCoordinator.state {
                    ModelInstallProgressView(state: modelDownloadState)
                }

                if let modelMessage {
                    Text(modelMessage)
                        .foregroundStyle(.secondary)
                }
            }
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

    private var catalog: [ProductionModelPresentation] {
        let models = services.modelCatalogCoordinator.models
        let signedCatalog = models.isEmpty
            ? ProductionModelPresentation.visibleCatalog
            : models.map(ProductionModelPresentation.init(model:))
        let signedIDs = Set(signedCatalog.map(\.id))
        return signedCatalog + services.installedModels
            .filter { !signedIDs.contains($0.id) }
            .map(ProductionModelPresentation.init(model:))
    }

    private var activeModel: ProductionModelPresentation? {
        guard let activeModelID = services.preferences.activeModelID else {
            return nil
        }
        return catalog.first { $0.id == activeModelID }
            ?? ProductionModelPresentation(
                id: activeModelID,
                displayName: activeModelID,
                description: "Installed local model.",
                details: nil
            )
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

                if let permissionMessage {
                    Text(permissionMessage)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Data") {
                Text("Textify keeps normal dictation content in memory only.")
                    .foregroundStyle(.secondary)
            }

            SettingsSection("Excluded Apps") {
                if services.preferences.excludedApps.isEmpty {
                    Text("No excluded apps.")
                        .foregroundStyle(.secondary)
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
            }
        }
        .task {
            _ = await services.dictation.refreshReadiness()
        }
    }

    private func addExcludedApp(_ candidate: ExcludedAppCandidate) {
        services.preferences.excludedApps = ExcludedAppsSettingsModel.adding(
            candidate,
            to: services.preferences.excludedApps
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

struct ExcludedAppCandidate: Equatable, Identifiable {
    var id: String { bundleIdentifier }

    let bundleIdentifier: String
    let displayName: String
    let iconData: Data?
    let path: String?
}

enum ExcludedAppsSettingsModel {
    static func adding(
        _ candidate: ExcludedAppCandidate,
        to apps: [ExcludedApp]
    ) -> [ExcludedApp] {
        guard !apps.contains(where: { $0.bundleIdentifier == candidate.bundleIdentifier }) else {
            return apps
        }
        return apps + [
            ExcludedApp(
                bundleIdentifier: candidate.bundleIdentifier,
                displayName: candidate.displayName,
                cachedIconData: candidate.iconData,
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
                    iconData: application.bundleURL.flatMap(iconData),
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
            iconData: iconData(applicationURL),
            path: applicationURL.path
        )
    }

    @MainActor
    private static func iconData(_ applicationURL: URL) -> Data? {
        NSWorkspace.shared.icon(forFile: applicationURL.path).tiffRepresentation
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

private struct AdvancedSettingsPane: View {
    @Environment(AppServices.self) private var services
    @State private var diagnosticsMessage: String?
    @State private var isWorking = false

    var body: some View {
        SettingsPaneLayout(title: "Advanced") {
            SettingsSection("Diagnostics") {
                HStack(spacing: 12) {
                    Button("Export Diagnostics...") {
                        Task {
                            await exportDiagnostics()
                        }
                    }
                    .disabled(isWorking)

                    Button("Clear Diagnostics Log") {
                        Task {
                            await clearDiagnostics()
                        }
                    }
                    .disabled(isWorking)
                }

                if let diagnosticsMessage {
                    Text(diagnosticsMessage)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Runtime Status") {
                LabeledContent("Dictation", value: services.dictation.status.menuStatusTitle)
                LabeledContent("Model", value: services.dictation.readiness.model.settingsModelStatus)
                LabeledContent("Microphone", value: services.dictation.readiness.permissions.microphone.settingsStatusLabel)
                LabeledContent("Accessibility", value: services.dictation.readiness.permissions.accessibility.settingsStatusLabel)
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
            diagnosticsMessage = "Diagnostics export failed: \(String(describing: error))"
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
        } catch {
            diagnosticsMessage = "Diagnostics clear failed: \(String(describing: error))"
        }
    }
}

struct ProductionModelPresentation: Equatable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let details: String?
    let supportTier: String
    let expectedFinalization: String
    let accuracyTradeoff: String
    let requirements: String

    init(
        id: String,
        displayName: String,
        description: String,
        details: String?,
        supportTier: String = "Custom",
        expectedFinalization: String = "Varies by model",
        accuracyTradeoff: String = "See model description",
        requirements: String = "Apple Silicon"
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.details = details
        self.supportTier = supportTier
        self.expectedFinalization = expectedFinalization
        self.accuracyTradeoff = accuracyTradeoff
        self.requirements = requirements
    }

    static let v1_1 = ProductionModelPresentation(
        id: ProductionModelPolicy.requiredModelID,
        displayName: "Balanced - Whisper small.en q5_1",
        description: "Local English dictation model for Textify V1.1.",
        details: "Whisper.cpp • Metal GPU • English",
        supportTier: "Recommended",
        expectedFinalization: "Near-instant after release",
        accuracyTradeoff: "Balanced English speed and accuracy",
        requirements: "Apple Silicon • about 182 MB download"
    )

    static let visibleCatalog: [ProductionModelPresentation] = [v1_1]

    init(model: ModelEntry) {
        id = model.id
        displayName = model.displayName
        description = model.description
        let engine = switch model.runtime.engine {
        case .whisperCpp: "Whisper.cpp"
        case .fluidAudioParakeet: "Parakeet"
        case .fluidAudioParaformer: "Paraformer"
        case .sherpaOnnx: "sherpa-onnx"
        case .transcribeCpp: "transcribe.cpp"
        }
        let accelerator = switch model.runtime.accelerator {
        case .metalGPU: "Metal GPU"
        case .coreMLNeuralEngine: "Core ML / Neural Engine"
        case .cpu: "Apple Silicon CPU"
        }
        let languages = model.capabilities.languages.count == 1
            ? model.capabilities.languages[0]
            : "\(model.capabilities.languages.count) languages"
        let size = ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
        let license = model.licenses.first?.name ?? "License metadata unavailable"
        details = "\(engine) • \(accelerator) • \(languages) • \(size) • \(license)"
        supportTier = Self.supportTier(for: model.tier)
        expectedFinalization = model.presentation?.expectedFinalization
            ?? Self.fallbackFinalization(for: model.tier)
        accuracyTradeoff = model.presentation?.accuracyTradeoff ?? model.description
        requirements = model.presentation?.requirements ?? "Apple Silicon • \(accelerator)"
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

    private static func fallbackFinalization(for tier: String) -> String {
        switch tier.lowercased() {
        case "fast": "Fastest available tier"
        case "balanced", "recommended": "Near-instant after release"
        case "accurate": "May take longer for higher accuracy"
        case "specialist": "Varies by specialist model"
        default: "Experimental; benchmark data incomplete"
        }
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
}

extension RuntimeModelReadiness {
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
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                content
            } header: {
                Text(title)
                    .font(.title2)
            }
        }
        .formStyle(.grouped)
        .padding(20)
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
        Section {
            content
        } header: {
            Text(title)
        }
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
            Text(status)
                .foregroundStyle(.secondary)
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
