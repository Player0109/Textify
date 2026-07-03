import SwiftUI

@main
struct TextifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services: AppServices

    init() {
        let services = AppServices.production()
        _services = State(initialValue: services)
        Task { @MainActor in
            services.startRuntime()
        }
    }

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
