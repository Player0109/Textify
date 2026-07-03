import SwiftUI
import TextifyRuntime

struct SettingsRootView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var router = services.settingsRouter

        TabView(selection: $router.selectedPane) {
            GeneralSettingsPane()
                .tabItem {
                    Label(SettingsPane.general.title, systemImage: SettingsPane.general.systemImage)
                }
                .tag(SettingsPane.general)

            DictationSettingsPane()
                .tabItem {
                    Label(SettingsPane.dictation.title, systemImage: SettingsPane.dictation.systemImage)
                }
                .tag(SettingsPane.dictation)

            ModelsSettingsPane()
                .tabItem {
                    Label(SettingsPane.models.title, systemImage: SettingsPane.models.systemImage)
                }
                .tag(SettingsPane.models)

            VocabularySettingsPane()
                .tabItem {
                    Label(SettingsPane.vocabulary.title, systemImage: SettingsPane.vocabulary.systemImage)
                }
                .tag(SettingsPane.vocabulary)

            PrivacySettingsPane()
                .tabItem {
                    Label(SettingsPane.privacy.title, systemImage: SettingsPane.privacy.systemImage)
                }
                .tag(SettingsPane.privacy)

            AdvancedSettingsPane()
                .tabItem {
                    Label(SettingsPane.advanced.title, systemImage: SettingsPane.advanced.systemImage)
                }
                .tag(SettingsPane.advanced)
        }
        .frame(width: 640, height: 460)
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
                Toggle("Show in Dock", isOn: $services.preferences.showInDock)
            }

            SettingsSection("Updates") {
                Toggle("Automatically check for updates", isOn: $services.preferences.automaticallyCheckForUpdates)
                Button("Check for Updates Now") {}
                    .disabled(true)
            }

            SettingsSection("Version") {
                LabeledContent("App Version", value: "0.1.0")
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
                services.launchAtLoginStatus == .enabled
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
}

private struct DictationSettingsPane: View {
    @State private var trigger = "Right Command"
    @State private var microphone = "System Default"

    var body: some View {
        SettingsPaneLayout(title: "Dictation") {
            SettingsSection("Input") {
                Picker("Dictation Trigger", selection: $trigger) {
                    Text("Right Command").tag("Right Command")
                    Text("Right Option").tag("Right Option")
                    Text("Right Control").tag("Right Control")
                    Text("Control-Space").tag("Control-Space")
                }

                Picker("Microphone", selection: $microphone) {
                    Text("System Default").tag("System Default")
                }
            }

            SettingsSection("Trigger Test") {
                HStack {
                    Text("Mechanical trigger test")
                    Spacer()
                    Button("Test Trigger") {}
                        .disabled(true)
                }
            }
        }
    }
}

private struct ModelsSettingsPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        SettingsPaneLayout(title: "Models") {
            SettingsSection("Installed Model") {
                LabeledContent("Readiness", value: modelReadinessText)
                LabeledContent("Active Model ID", value: services.preferences.activeModelID ?? "None")
            }

            SettingsSection("Curated Models") {
                EmptySettingsRow("No curated model manifest loaded.")
            }
        }
    }

    private var modelReadinessText: String {
        switch services.dictation.readiness.model {
        case .noActiveModel:
            return "No active model"
        case let .missing(modelID):
            return "Missing \(modelID)"
        case let .loading(modelID):
            return "Loading \(modelID)"
        case let .warming(modelID):
            return "Preparing \(modelID)"
        case let .ready(modelID):
            return "Ready \(modelID)"
        case let .failed(modelID, _):
            return "Failed \(modelID)"
        }
    }
}

private struct VocabularySettingsPane: View {
    var body: some View {
        SettingsPaneLayout(title: "Vocabulary") {
            SettingsSection("Custom Words") {
                EmptySettingsRow("No custom words.")
                HStack {
                    Button("Add") {}
                    Button("Remove") {}
                }
                .disabled(true)
            }

            SettingsSection("Replacement Pairs") {
                EmptySettingsRow("No replacement pairs.")
                HStack {
                    Button("Add") {}
                    Button("Remove") {}
                }
                .disabled(true)
            }
        }
    }
}

private struct PrivacySettingsPane: View {
    var body: some View {
        SettingsPaneLayout(title: "Privacy") {
            SettingsSection("Permissions") {
                PermissionRow(name: "Microphone", status: "Not checked")
                PermissionRow(name: "Accessibility", status: "Not checked")
                PermissionRow(name: "Input Monitoring", status: "Not checked")
            }

            SettingsSection("Excluded Apps") {
                EmptySettingsRow("No excluded apps.")
                HStack {
                    Button("Add Current App") {}
                    Button("Remove") {}
                }
                .disabled(true)
            }

            SettingsSection("Diagnostics") {
                HStack {
                    Button("Export Diagnostics...") {}
                    Button("Clear Diagnostics Log") {}
                }
                .disabled(true)
            }
        }
    }
}

private struct AdvancedSettingsPane: View {
    @Environment(AppServices.self) private var services
    @State private var developerMode = false

    var body: some View {
        SettingsPaneLayout(title: "Advanced") {
            SettingsSection("Reset") {
                HStack {
                    Button("Reset Onboarding") {}
                    Button("Reset All Settings") {}
                }
                .disabled(true)
            }

            SettingsSection("Diagnostics") {
                Button("Open Diagnostics Folder") {}
                    .disabled(true)
            }

            SettingsSection("Runtime Status") {
                LabeledContent("Active Runtime", value: "Whisper")
                LabeledContent("Metal Acceleration", value: "Not loaded")
                LabeledContent("Thread Count", value: "Automatic")
                LabeledContent("Dictation", value: dictationStatusText)
            }

            SettingsSection("Developer Mode") {
                Toggle("Developer Mode", isOn: $developerMode)
            }
        }
    }

    private var dictationStatusText: String {
        switch services.dictation.status {
        case .idle:
            return "Idle"
        case .waitingForActivation:
            return "Waiting"
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .inserting:
            return "Inserting"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .blocked:
            return "Blocked"
        case .failed:
            return "Failed"
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

private struct EmptySettingsRow: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .foregroundStyle(.secondary)
    }
}

private struct PermissionRow: View {
    let name: String
    let status: String

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(status)
                .foregroundStyle(.secondary)
            Button("Open Settings") {}
                .disabled(true)
        }
    }
}
