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
        .onAppear {
            if let purpose = router.selectedPane.modelPurpose {
                services.modelCatalogCoordinator.destinationOpened(purpose)
            }
        }
        .onChange(of: router.selectedPane) { previousPane, nextPane in
            services.modelCatalogCoordinator.destinationChanged(
                from: previousPane.modelPurpose,
                to: nextPane.modelPurpose
            )
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
            ModelsSettingsPane(destination: .transcription)
        case .voiceCleaning:
            ModelsSettingsPane(destination: .voiceCleaning)
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
                            Image(systemName: pane.systemImage)
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

                    if pane == .voiceCleaning {
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
        .transcriptionModels,
        .voiceCleaning,
        .privacy,
        .logs,
        .advanced
    ]

    var sidebarTitle: String {
        switch self {
        case .general:
            return "General Settings"
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
    let destination: ModelCatalogPurposeDestination

    @State private var modelMessage: String?
    @State private var activatingModelID: String?
    @State private var pendingImportURL: URL?
    @State private var showsImportConfirmation = false
    @State private var isImporting = false
    @State private var pendingRemovalModel: ProductionModelPresentation?
    @State private var discoveryQuery = ModelCatalogQuery()
    @State private var hierarchyState = ModelCatalogHierarchyState()
    @State private var inspectorController = ModelCatalogInspectorController()
    @State private var verificationRestorationIDsByArtifact:
        [String: [String]] = [:]
    @State private var showsInspector = false
    @State private var showsModelVariantsHelp = false
    @State private var showsDownloads = false
    @FocusState private var focusedCatalogRowID: ModelCatalogHierarchyRowID?

    var body: some View {
        let catalogExperience = services.modelCatalogExperience(
            for: destination.purpose,
            query: catalogQuery
        )

        return SettingsPaneLayout(
            title: destination.title,
            subtitle: destination.subtitle,
            maxContentWidth: 1_360,
            scrollPosition: Binding(
                get: { hierarchyState.scrollAnchorID },
                set: { hierarchyState.scroll(to: $0) }
            )
        ) {
            catalogStatus(hasRows: !catalogExperience.rows.isEmpty)

            if services.settingsRouter.modelReplacementPurpose
                == destination.purpose {
                Label(
                    "The previous selection was revoked. Choose and explicitly activate a replacement.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }

            if let modelMessage {
                Text(modelMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if ProductionModelInstallConfiguration.current == nil,
                      services.modelCatalogCoordinator.manifest == nil {
                Text("Signed catalog unavailable in this build")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !isInitialCatalogCheck {
                ModelCatalogToolbar(
                    query: $discoveryQuery,
                    showsDownloads: $showsDownloads,
                    filterOptions: catalogExperience.filterOptions,
                    onReset: resetCatalogQuery,
                    onVerify: verifyInstalledModels,
                    onImport: destination == .transcription
                        ? chooseCustomWhisperModel
                        : nil,
                    onShowVariantHelp: {
                        showsModelVariantsHelp = true
                    },
                    downloadCount: services.modelInstallCoordinator
                        .hasNonterminalAttempts
                        ? ModelDownloadsPresentation(
                            attempts: services.modelInstallCoordinator.attempts
                        ).nonterminalCount
                        : 0,
                    isImportDisabled: hasPendingDownloads || isImporting
                )

                if !discoveryQuery.appliedFilterTokens.isEmpty {
                    ModelCatalogFilterTokens(
                        tokens: discoveryQuery.appliedFilterTokens
                    ) { token in
                        discoveryQuery.removeFilter(token)
                    }
                }

                if discoveryQuery.scope == .installed {
                    ModelCatalogStorageSummaryView(
                        presentation: ModelCatalogStorageSummaryPresentation(
                            state: services.modelStorageInventory.state,
                            installedCount: services.installedModelRecords.count
                        )
                    )
                }

                if let pinnedReveal = catalogExperience.pinnedReveal {
                    pinnedRevealView(
                        pinnedReveal,
                        in: catalogExperience
                    )
                }
            }

            catalogSurface(catalogExperience)
        }
        .inspector(isPresented: $showsInspector) {
            ScrollView {
                ModelCatalogInspectorView(
                    presentation: inspectorController.presentation,
                    localDetailsState: inspectorController.localDetailsState,
                    verificationState: inspectorController.verificationState,
                    onVerify: verifySelectedArtifact
                )
            }
            .scrollContentBackground(.hidden)
            .inspectorColumnWidth(min: 280, ideal: 320, max: 360)
        }
        .popover(isPresented: $showsModelVariantsHelp) {
            ModelCatalogVariantsAboutView()
        }
        .task {
            services.refreshModelStorageInventory()
            _ = await services.dictation.refreshReadiness()
            await services.modelCatalogCoordinator.refresh()
        }
        .onChange(of: catalogExperience) { _, updatedExperience in
            hierarchyState.reconcile(with: updatedExperience)
            focusedCatalogRowID = hierarchyState.focusedRowID
            inspectorController.select(
                hierarchyState.selection,
                in: updatedExperience
            )
            if hierarchyState.selection == nil {
                showsInspector = false
            }
        }
        .onChange(of: focusedCatalogRowID) { _, rowID in
            hierarchyState.focus(rowID)
        }
        .onChange(of: inspectorController.verificationState) { _, state in
            switch state {
            case let .verified(artifactID):
                let expectedRestorationIDs =
                    verificationRestorationIDsByArtifact[artifactID]
                        ?? []
                verificationRestorationIDsByArtifact[artifactID] = nil
                Task {
                    await services.acknowledgeRestoredModelIntegrity(
                        artifactID,
                        expectedRestorationIDs:
                            expectedRestorationIDs
                    )
                    services.refreshModelStorageInventory()
                }
            case let .failed(artifactID):
                verificationRestorationIDsByArtifact[artifactID] = nil
                services.refreshModelStorageInventory()
            case .unavailable, .available, .verifying:
                break
            }
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

    private var hasPendingDownloads: Bool {
        services.modelInstallCoordinator.hasNonterminalAttempts
    }

    private var isInitialCatalogCheck: Bool {
        services.modelCatalogCoordinator.manifest == nil
            && services.modelCatalogCoordinator.status == .checking
    }

    @ViewBuilder
    private func catalogStatus(hasRows: Bool) -> some View {
        let coordinator = services.modelCatalogCoordinator
        if coordinator.stagedRevision != nil {
            HStack(spacing: 10) {
                Label(
                    "A verified catalog update is ready.",
                    systemImage: "checkmark.shield"
                )
                .font(.callout)
                Spacer(minLength: 12)
                Button("Apply Now") {
                    coordinator.applyStagedUpdate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .background(TextifyVisualIdentity.voiceViolet.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        if let issue = coordinator.securityIssue {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed catalog update rejected")
                        .font(.callout.weight(.semibold))
                    Text(
                        "Security check: \(issue.reason.displayName). "
                            + "The last trusted catalog remains available."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("Check Again") {
                    Task {
                        await coordinator.refresh()
                    }
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            switch coordinator.status {
            case .checking where coordinator.manifest == nil:
                EmptyView()
            case .checking, .checkingForUpdates:
                Label("Checking for signed catalog updates", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .updateAvailable:
                EmptyView()
            case .offline:
                Label(
                    "Offline — using the last trusted catalog.",
                    systemImage: "network.slash"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            case let .requiresNewerTextify(manifestVersion):
                Label(
                    "Catalog version \(manifestVersion) requires a newer Textify.",
                    systemImage: "arrow.down.app"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            case .unavailable:
                if hasRows {
                    Text(coordinator.errorMessage ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .trusted, .securityFailure:
                EmptyView()
            }
        }
    }

    private var catalogQuery: ModelCatalogQuery {
        var query = discoveryQuery
        query.purpose = destination.purpose
        if services.settingsRouter.modelReveal?.purpose == destination.purpose {
            query.revealedArtifactID = services.settingsRouter.modelReveal?.artifactID
        }
        return query
    }

    private func resetCatalogQuery() {
        discoveryQuery.resetDiscovery()
        services.settingsRouter.dismissModelReveal()
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
                inspectorController.presentation
        else {
            return
        }
        let record = services.installedModelRecords.first {
            $0.model.id == artifact.id
        }
        verificationRestorationIDsByArtifact[artifact.id] =
            record.map {
                services.pendingRestorationVerificationIDs(for: $0)
            } ?? []
        inspectorController.verifySelectedArtifact()
    }

    private func catalogSurface(
        _ catalogExperience: ModelCatalogExperience
    ) -> some View {
        ModelCatalogSurface(
            rows: isInitialCatalogCheck ? [] : catalogExperience.rows,
            sizeLabel: catalogExperience.sizeLabel,
            hierarchyRows: isInitialCatalogCheck
                ? []
                : hierarchyState.visibleRows(in: catalogExperience),
            selection: hierarchyState.selection,
            focusedRowID: $focusedCatalogRowID,
            onSelect: { selection in
                hierarchyState.select(selection)
                inspectorController.select(selection, in: catalogExperience)
                showsInspector = true
            },
            onToggleCheckpoint: { checkpoint in
                hierarchyState.toggleExpansion(of: checkpoint)
                inspectorController.select(
                    hierarchyState.selection,
                    in: catalogExperience
                )
            },
            onReset: performEmptyStateAction,
            emptyPresentation: emptyPresentation
        ) { row, context in
            catalogRow(
                row,
                context: context,
                onInspect: context == nil ? {
                    let selection = ModelCatalogHierarchySelection
                        .exactArtifact(row.id)
                    hierarchyState.select(selection)
                    inspectorController.select(
                        selection,
                        in: catalogExperience
                    )
                    showsInspector = true
                } : nil
            )
        }
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
                discoveryQuery.scope = .all
                if discoveryQuery.sort == .installedSize {
                    discoveryQuery.sort = .catalog
                }
            case .search:
                discoveryQuery.clearSearch()
            case .filters:
                discoveryQuery.clearFilters()
            case .combined:
                discoveryQuery.clearSearch()
                discoveryQuery.clearFilters()
            case .validCatalog:
                Task {
                    await services.modelCatalogCoordinator.refresh()
                }
            }
        case .purpose, .unavailable, .securityFailure:
            Task {
                await services.modelCatalogCoordinator.refresh()
            }
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
                        isSelected: hierarchyState.selection
                            == .exactArtifact(artifact.id),
                        indentation: 0,
                        comparison: nil,
                        onSelect: {
                            let selection = ModelCatalogHierarchySelection
                                .exactArtifact(artifact.id)
                            hierarchyState.select(selection)
                            inspectorController.select(
                                selection,
                                in: catalogExperience
                            )
                            showsInspector = true
                        }
                    )
                )
            }
        case let .standaloneArtifact(row):
            pinnedRevealCard(
                title: "\(row.model.displayName) (\(row.id))"
            ) {
                catalogRow(
                    row,
                    context: nil,
                    onInspect: {
                        let selection = ModelCatalogHierarchySelection
                            .exactArtifact(row.id)
                        hierarchyState.select(selection)
                        inspectorController.select(
                            selection,
                            in: catalogExperience
                        )
                        showsInspector = true
                    }
                )
            }
        case let .unavailableArtifact(artifactID):
            pinnedRevealCard(title: artifactID) {
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
                modelMessage = result.message(for: row.model)
                activatingModelID = nil
            }
        }
        let onDisable: () -> Void = {
            Task {
                let disabled = await services.disableVoiceCleaning()
                modelMessage = disabled
                    ? "Voice cleaning is off."
                    : "Wait for the current dictation to finish, then try again."
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
            pendingRemovalModel = row.model
        }

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
                actions: row.actions,
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
                actions: row.actions,
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
        .frame(width: 390, height: 420)
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
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
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
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                .lineLimit(2)

            HStack(spacing: 12) {
                Button("Show in Catalog", action: onReveal)

                Spacer(minLength: 0)

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
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
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

    var body: some View {
        HStack(spacing: 10) {
            Picker("Catalog scope", selection: scopeBinding) {
                ForEach(ModelCatalogScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

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
            .frame(height: 28)
            .background(
                Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
            }

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
                            Label(direction.title, systemImage: direction.systemImage)
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
                    ForEach(filterOptions.artifactFormats, id: \.rawValue) { value in
                        filterButton(
                            value,
                            at: \.artifactFormats,
                            title: ModelCatalogVariantTerminology.artifactFormat(value)
                        )
                    }
                }
                Menu("Numeric Format") {
                    ForEach(filterOptions.numericFormats, id: \.rawValue) { value in
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
                            title: ModelCatalogVariantTerminology.runtime(value)
                        )
                    }
                }
                Menu("Compute Route") {
                    ForEach(filterOptions.computeRoutes, id: \.rawValue) { value in
                        filterButton(
                            value,
                            at: \.computeRoutes,
                            title: ModelCatalogVariantTerminology.computeRoute(value)
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
                        filterButton(value, at: \.evidence, title: value.title)
                    }
                }
                if query.hasAppliedFilters {
                    Divider()
                    Button("Clear Filters", systemImage: "line.3.horizontal.decrease.circle") {
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

            Spacer(minLength: 0)

            Button {
                showsDownloads = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: downloadCount > 0
                        ? "arrow.down.circle.fill"
                        : "arrow.down.circle")
                    Text("Downloads")
                    if downloadCount > 0 {
                        Text("\(downloadCount)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
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
                Button("Verify Installed", systemImage: "checkmark.seal", action: onVerify)
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
                    .font(.system(size: 15, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
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

    private let columns = Array(
        repeating: GridItem(.flexible(), alignment: .topLeading),
        count: 3
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(
                Array(presentation.facts.enumerated()),
                id: \.offset
            ) { _, fact in
                VStack(alignment: .leading, spacing: 3) {
                    Text(fact.label.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.45)
                        .foregroundStyle(.tertiary)
                    Text(fact.value)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035))
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
    let selection: ModelCatalogHierarchySelection?
    let focusedRowID: FocusState<ModelCatalogHierarchyRowID?>.Binding
    let onSelect: (ModelCatalogHierarchySelection) -> Void
    let onToggleCheckpoint: (ModelCatalogCheckpointPresentation) -> Void
    let onReset: () -> Void
    let emptyPresentation: ModelCatalogEmptyPresentation
    let row: (ModelCatalogRowPresentation, ModelCatalogArtifactRowContext?) -> Row

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        rows: [ModelCatalogRowPresentation],
        sizeLabel: String,
        hierarchyRows: [ModelCatalogHierarchyRow],
        selection: ModelCatalogHierarchySelection?,
        focusedRowID: FocusState<ModelCatalogHierarchyRowID?>.Binding,
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
        self.selection = selection
        self.focusedRowID = focusedRowID
        self.onSelect = onSelect
        self.onToggleCheckpoint = onToggleCheckpoint
        self.onReset = onReset
        self.emptyPresentation = emptyPresentation
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ModelCatalogColumnHeader()
            Divider()
            if rows.isEmpty {
                ModelCatalogEmptyState(
                    presentation: emptyPresentation,
                    onAction: onReset
                )
            } else {
                LazyVStack(spacing: 0) {
                    if hierarchyRows.isEmpty {
                        ForEach(rows) { catalogRow in
                            row(catalogRow, nil)
                                .id(ModelCatalogHierarchyRowID.standaloneArtifact(catalogRow.id))
                                .focusable()
                                .focused(
                                    focusedRowID,
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
                            .focusable()
                            .focused(focusedRowID, equals: hierarchyRow.id)
                        }
                    }
                }
                .scrollTargetLayout()
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
            return "wifi.exclamationmark"
        case .securityFailure:
            return "exclamationmark.shield"
        case .requiresNewerTextify:
            return "arrow.down.app"
        }
    }

    var title: String {
        switch self {
        case .checking:
            return "Checking signed catalog"
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
            return "Textify is verifying trusted catalog data. Model actions will appear when the check finishes."
        case let .query(state):
            return state.detail
        case let .purpose(destination):
            return destination.emptyDetail
        case let .unavailable(destination):
            return destination.unavailableDetail
        case .securityFailure:
            return "Textify rejected the candidate catalog and did not replace trusted data."
        case let .requiresNewerTextify(manifestVersion):
            return "This signed catalog uses schema version \(manifestVersion), which this version of Textify cannot present."
        }
    }

    var actionTitle: String? {
        switch self {
        case .checking, .requiresNewerTextify:
            return nil
        case let .query(state):
            return state.actionTitle
        case let .purpose(destination),
             let .unavailable(destination),
             let .securityFailure(destination):
            return destination.unavailableActionTitle
        }
    }
}

private struct ModelCatalogFamilyHeading: View {
    let family: ModelCatalogFamilyPresentation

    var body: some View {
        HStack(spacing: 12) {
            ModelProviderTile(provider: provider, isActive: false)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(family.metadata.presentation.displayName)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(family.metadata.presentation.provider.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(family.metadata.presentation.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(
                "\(family.checkpoints.count) "
                    + (family.checkpoints.count == 1 ? "checkpoint" : "checkpoints")
            )
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(checkpoint.metadata.presentation.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text("\(checkpoint.metadata.artifactIDs.count) VARIANTS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(.secondary)
                        }
                        Text(checkpoint.metadata.presentation.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ModelSelectionIndicator(isInstalled: isInstalled, isActive: showsSelectedTreatment)

                if hierarchyContext == nil {
                    ModelProviderTile(provider: model.provider, isActive: showsSelectedTreatment)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(hierarchyContext?.title ?? model.catalogDisplayName)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        if let variantLabel = hierarchyContext?.variantLabel {
                            Text(variantLabel.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundStyle(.secondary)
                        }
                        if isRevoked {
                            TextifyStatusBadge(title: "REVOKED", tone: .warning)
                        }
                        if hierarchyContext?.isRecommended == true {
                            TextifyStatusBadge(title: "RECOMMENDED", tone: .accent)
                        }
                        if hierarchyContext?.isFallback == true {
                            TextifyStatusBadge(title: "SIGNED FALLBACK", tone: .warning)
                        }
                        TextifyStatusBadge(title: model.supportTier.uppercased(), tone: tierTone)
                        if let placement, placement != .curated {
                            TextifyStatusBadge(
                                title: placement.title.uppercased(),
                                tone: placement == .custom ? .neutral : .warning
                            )
                        }
                    }
                    Text(hierarchyContext?.description ?? model.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ModelSignalMetric(level: model.qualitySignalLevel, label: model.qualityLabel)
                    .frame(width: 86, alignment: .leading)
                ModelSignalMetric(level: model.speedSignalLevel, label: model.speedLabel)
                    .frame(width: 86, alignment: .leading)
                ModelFeaturesMetric(
                    model: model,
                    sizeLabel: sizeLabel,
                    sizeDescription: sizeDescription
                )
                    .frame(width: 138, alignment: .leading)
            }

            HStack(spacing: 10) {
                Spacer()
                    .frame(width: hierarchyContext == nil ? 76 : 28)

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
            } else if install.state.isActive {
                ProgressView()
                    .controlSize(.small)
                    .tint(statusColor)
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

extension ModelProviderIdentity {
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

struct ProductionModelInstallConfiguration: Equatable {
    let manifestURL: URL
    let signatureURL: URL
    let revocationURL: URL?
    let revocationSignatureURL: URL?
    let trustedKeys: [TrustedModelManifestKey]

    init(
        manifestURL: URL,
        signatureURL: URL,
        revocationURL: URL? = nil,
        revocationSignatureURL: URL? = nil,
        trustedKeys: [TrustedModelManifestKey]
    ) {
        self.manifestURL = manifestURL
        self.signatureURL = signatureURL
        self.revocationURL = revocationURL
        self.revocationSignatureURL = revocationSignatureURL
        self.trustedKeys = trustedKeys
    }

    static let current: ProductionModelInstallConfiguration? = ProductionModelInstallConfiguration(
        manifestURL: URL(string: "https://player0109.github.io/Textify/models/manifest.json")!,
        signatureURL: URL(string: "https://player0109.github.io/Textify/models/manifest.json.sig")!,
        revocationURL: URL(string: "https://player0109.github.io/Textify/models/revocations.json")!,
        revocationSignatureURL: URL(string: "https://player0109.github.io/Textify/models/revocations.json.sig")!,
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

private struct SettingsPaneLayout<Content: View>: View {
    let title: String
    let subtitleOverride: String?
    let maxContentWidth: CGFloat
    let scrollPosition: Binding<ModelCatalogHierarchyRowID?>?
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String? = nil,
        maxContentWidth: CGFloat = TextifyWindowMetrics.readableContentWidth,
        scrollPosition: Binding<ModelCatalogHierarchyRowID?>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitleOverride = subtitle
        self.maxContentWidth = maxContentWidth
        self.scrollPosition = scrollPosition
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if let scrollPosition {
            paneScrollView
                .scrollPosition(id: scrollPosition, anchor: .top)
        } else {
            paneScrollView
        }
    }

    private var paneScrollView: some View {
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
