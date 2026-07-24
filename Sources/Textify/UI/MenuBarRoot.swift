import AppKit
import SwiftUI
import TextifyModels
import TextifyRuntime

struct MenuBarRoot: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Button(MenuBarPresentation.openTextifyTitle) {
            openSettingsPane(.general)
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        if shouldShowStatus {
            Label(statusTitle, systemImage: statusSystemImage)
                .foregroundStyle(.secondary)

            if let blockerTitle {
                Text(blockerTitle)
                    .foregroundStyle(.secondary)
            }

            Divider()
        }

        if shouldShowFinishSetup {
            Button("Finish Setup…") {
                TextifyOnboardingWindowPresenter.shared.show(services: services)
            }
        }

        if services.revokedActiveTranscriptionModelID != nil {
            Button("Choose Dictation Replacement…") {
                openReplacementPicker(for: .transcription)
            }
        }

        if services.revokedActiveVoiceCleaningModelID != nil {
            Button("Choose Voice Cleaning Replacement…") {
                openReplacementPicker(for: .voiceCleaning)
            }
        }

        Button("About Textify") {
            showAboutPanel()
        }

        Divider()

        Button("Quit Textify") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private var statusTitle: String {
        if services.runtimeIssue == .persistentStorageUnavailable {
            return "Storage Unavailable"
        }
        if services.runtimeIssue == .hotkeyMonitorUnavailable {
            return "Trigger Unavailable"
        }
        if !services.dictation.readiness.canDictate,
           services.dictation.status == .idle {
            return "Setup Required"
        }

        return services.dictation.status.menuStatusTitle
    }

    private var blockerTitle: String? {
        if let runtimeIssue = services.runtimeIssue {
            return runtimeIssue.userMessage
        }
        return services.dictation.readiness.blockers.first?.menuBlockerSummary
    }

    private var shouldShowFinishSetup: Bool {
        !services.preferences.onboardingCompleted || !services.dictation.readiness.canDictate
    }

    private var shouldShowStatus: Bool {
        services.runtimeIssue != nil
            || !services.dictation.readiness.canDictate
            || services.dictation.status != .idle
    }

    private var statusSystemImage: String {
        if services.runtimeIssue != nil || !services.dictation.readiness.canDictate {
            return "exclamationmark.circle"
        }
        switch services.dictation.status {
        case .recording:
            return "waveform"
        case .processing, .inserting:
            return "ellipsis.circle"
        default:
            return "circle.fill"
        }
    }

    private func openSettingsPane(_ pane: SettingsPane) {
        services.settingsRouter.selectedPane = pane
        TextifyMainWindowPresenter.shared.show(services: services)
    }

    private func openReplacementPicker(for purpose: ModelPurpose) {
        services.chooseReplacement(for: purpose)
        TextifyMainWindowPresenter.shared.show(services: services)
    }

    private func showAboutPanel() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "Textify"
            ]
        )
    }
}

enum MenuBarPresentation {
    static let openTextifyTitle = "Open Textify…"
}

extension DictationRuntimeStatus {
    var menuStatusTitle: String {
        switch self {
        case .idle:
            return "Ready"
        case .waitingForActivation:
            return "Waiting"
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .inserting:
            return "Typing"
        case .completed:
            return "Done"
        case .cancelled:
            return "Cancelled"
        case .blocked:
            return "Setup Required"
        case .failed:
            return "Unavailable"
        }
    }
}

extension ReadinessBlocker {
    var menuBlockerSummary: String {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access needed"
        case .accessibilityPermissionDenied:
            return "Accessibility needed"
        case .noActiveModel:
            return "Model not selected"
        case .activeModelMissing:
            return "Model not installed"
        case .activeModelNotReady:
            return "Model preparing"
        default:
            return "Model unavailable"
        }
    }
}
