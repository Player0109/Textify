import AppKit
import SwiftUI

struct MenuBarRoot: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
#if DEBUG
        Button("Run Mock Dictation") {
            Task {
                await services.runMockDictation()
            }
        }
        .disabled(!services.canRunMockDictation)

        if let title = services.mockDictationStatus.menuTitle {
            Text(title)
                .foregroundStyle(.secondary)
        }

        Divider()
#endif

        Button("Settings...") {
            openSettingsPane(.general)
        }
        .keyboardShortcut(",", modifiers: [.command])

        Button("Show Onboarding") {
            openWindow(id: "onboarding")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Button("Check for Updates...") {
            services.updateStatus = .unavailable("Sparkle is not wired in this mock build.")
        }
        .disabled(true)

        Button("About Textify") {
            showAboutPanel()
        }

        Divider()

        Button("Quit Textify") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func openSettingsPane(_ pane: SettingsPane) {
        services.settingsRouter.selectedPane = pane
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func showAboutPanel() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "Textify",
                .applicationVersion: "0.1.0"
            ]
        )
    }
}
