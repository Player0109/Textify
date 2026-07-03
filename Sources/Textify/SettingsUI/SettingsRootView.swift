import SwiftUI

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
                Toggle("Launch at Login", isOn: $services.preferences.launchAtLoginRequestedByOnboarding)
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
                if let activeModelID = services.modelCatalog.activeModelID {
                    LabeledContent("Active Model ID", value: activeModelID)
                } else {
                    Text("No model installed.")
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Curated Models") {
                ForEach(services.modelCatalog.curatedModels) { model in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.tier)
                                .font(.headline)
                            Text(model.name)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(model.size)
                            .foregroundStyle(.secondary)

                        Button("Download") {}
                            .disabled(true)
                    }
                }
            }
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
                LabeledContent("Active Runtime", value: "Mock")
                LabeledContent("Metal Acceleration", value: "Not loaded")
                LabeledContent("Thread Count", value: "Automatic")
                LabeledContent("Mock Dictation", value: services.mockDictationStatus.menuTitle ?? "Idle")
            }

            SettingsSection("Developer Mode") {
                Toggle("Developer Mode", isOn: $developerMode)
            }
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
