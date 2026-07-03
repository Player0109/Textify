import AppKit
import SwiftUI

struct MenuBarRoot: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings...") {
            openSettingsPane(.general)
        }
        .keyboardShortcut(",", modifiers: [.command])

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
