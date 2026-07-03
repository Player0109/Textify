import AppKit
import ApplicationServices
import SwiftUI
import TextifyAudio
import TextifyDiagnostics
import TextifyHotkeys
import TextifyModels
import TextifyRuntime

struct SettingsRootView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var router = services.settingsRouter

        TabView(selection: $router.selectedPane) {
            ForEach(SettingsPane.productionVisiblePanes) { pane in
                paneView(for: pane)
                    .tabItem {
                        Label(pane.title, systemImage: pane.productionSystemImage)
                    }
                    .tag(pane)
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
                Toggle("Show in Dock", isOn: $services.preferences.showInDock)
                Text("Quit and reopen Textify to apply Dock changes.")
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
                LabeledContent("Dictation Trigger", value: "Right Command")
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
            }
        }
        .onDisappear {
            triggerTest.stop()
        }
    }
}

private struct ModelsSettingsPane: View {
    @Environment(AppServices.self) private var services
    @State private var modelDownloadState: DownloadState?
    @State private var modelMessage: String?

    var body: some View {
        SettingsPaneLayout(title: "Models") {
            SettingsSection("Active Model") {
                LabeledContent("Model", value: ProductionModelPresentation.v1_1.displayName)
                LabeledContent("Identifier", value: ProductionModelPresentation.v1_1.id)
                LabeledContent("Status", value: services.dictation.readiness.model.settingsModelStatus)
            }

            SettingsSection("Curated Model") {
                ForEach(ProductionModelPresentation.visibleCatalog) { model in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.displayName)
                            .font(.headline)
                        Text(model.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.description)
                            .foregroundStyle(.secondary)
                    }
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

                    Button(isInstalling ? "Installing" : "Install Model") {
                        Task {
                            await installModel()
                        }
                    }
                    .disabled(isInstalling || ProductionModelInstallConfiguration.current == nil)
                }

                if ProductionModelInstallConfiguration.current == nil {
                    Text("Signed model manifest is not configured in this build.")
                        .foregroundStyle(.secondary)
                }

                if let modelDownloadState {
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
        }
    }

    private var isInstalling: Bool {
        modelDownloadState?.isActive ?? false
    }

    @MainActor
    private func installModel() async {
        guard !isInstalling else {
            return
        }

        guard let configuration = ProductionModelInstallConfiguration.current else {
            modelMessage = "Signed model manifest is not configured in this build."
            return
        }

        modelMessage = nil
        modelDownloadState = DownloadState(
            modelID: ProductionModelPolicy.requiredModelID,
            phase: .checkingSpace,
            message: "Preparing model download."
        )

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
            ) { state in
                Task { @MainActor in
                    modelDownloadState = state
                }
            }
            services.preferences.activeModelID = ProductionModelPolicy.requiredModelID
            services.savePreferences()
            _ = await services.dictation.refreshReadiness()
            modelMessage = nil
        } catch {
            modelDownloadState = DownloadState(
                modelID: ProductionModelPolicy.requiredModelID,
                phase: .failed,
                message: "Model install failed: \(String(describing: error))"
            )
            modelMessage = nil
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

                PermissionRow(
                    name: "Input Monitoring",
                    status: services.dictation.readiness.permissions.inputMonitoring.settingsStatusLabel,
                    actionTitle: "Request Access"
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
            }

            SettingsSection("Data") {
                Text("Textify keeps normal dictation content in memory only.")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            _ = await services.dictation.refreshReadiness()
        }
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
                LabeledContent("Input Monitoring", value: services.dictation.readiness.permissions.inputMonitoring.settingsStatusLabel)
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

    static let v1_1 = ProductionModelPresentation(
        id: ProductionModelPolicy.requiredModelID,
        displayName: "Balanced - Whisper small.en q5_1",
        description: "Local English dictation model for Textify V1.1."
    )

    static let visibleCatalog: [ProductionModelPresentation] = [v1_1]
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
            )
        ]
    )
}

enum ProductionPermissionRequester {
    private static let accessibilityPromptOption = "AXTrustedCheckOptionPrompt"

    static func requestMicrophone() async -> RuntimePermissionState {
        await MicrophonePermissionClient.live.requestAccess().runtimeState
    }

    static func requestInputMonitoring() async -> RuntimePermissionState {
        await InputMonitoringPermissionClient.live.requestAccess().runtimeState
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

extension InputMonitoringPermissionStatus {
    var runtimeState: RuntimePermissionState {
        switch self {
        case .granted:
            return .granted
        case .unknown:
            return .unknown
        case .denied:
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
