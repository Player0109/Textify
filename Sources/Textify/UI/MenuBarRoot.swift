import AppKit
import SwiftUI
import TextifyModels
import TextifyRuntime

struct MenuBarRoot: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Button {
            openSettingsPane(.general)
        } label: {
            Label(
                MenuBarPresentation.openTextifyTitle,
                systemImage: "macwindow"
            )
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        if shouldShowStatus {
            Label(statusTitle, systemImage: statusSystemImage)
                .foregroundStyle(.secondary)

            if let blockerTitle {
                Label(blockerTitle, systemImage: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
            }

            Divider()
        }

        if shouldShowFinishSetup {
            Button {
                TextifyOnboardingWindowPresenter.shared.show(services: services)
            } label: {
                Label("Finish Setup…", systemImage: "checklist")
            }
        }

        if services.revokedActiveTranscriptionModelID != nil {
            Button {
                openReplacementPicker(for: .transcription)
            } label: {
                Label("Replace Dictation Model…", systemImage: "waveform")
            }
        }

        if services.revokedActiveVoiceCleaningModelID != nil {
            Button {
                openReplacementPicker(for: .voiceCleaning)
            } label: {
                Label(
                    "Replace Voice Cleaner…",
                    systemImage: "waveform.path.ecg"
                )
            }
        }

        Button {
            showAboutPanel()
        } label: {
            Label("About Textify", systemImage: "info.circle")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Textify", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private var statusTitle: String {
        if services.runtimeIssue == .persistentStorageUnavailable {
            return "Storage Unavailable"
        }
        if services.runtimeIssue == .modelTrustUnavailable {
            return "Model Trust Unavailable"
        }
        if services.runtimeIssue == .retiredModelCleanupFailed {
            return "Model Cleanup Required"
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
            return runtimeIssue.menuBlockerSummary
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

extension AppRuntimeIssue {
    var menuBlockerSummary: String {
        switch self {
        case .persistentStorageUnavailable:
            return "Check storage permissions"
        case .modelTrustUnavailable:
            return "Reinstall from a verified release"
        case .retiredModelCleanupFailed:
            return "Reopen Textify to retry cleanup"
        case .hotkeyMonitorUnavailable:
            return "Retry the trigger in Textify"
        }
    }
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
