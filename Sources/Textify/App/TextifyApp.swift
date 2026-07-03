import SwiftUI

@main
struct TextifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services = AppServices()

    var body: some Scene {
        MenuBarExtra("Textify", systemImage: "text.bubble") {
            MenuBarRoot()
                .environment(services)
        }

        Settings {
            SettingsRootView()
                .environment(services)
        }

        Window("Textify Onboarding", id: "onboarding") {
            OnboardingRootView()
                .environment(services)
        }
    }
}
