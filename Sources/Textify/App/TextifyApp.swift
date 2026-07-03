import AppKit
import SwiftUI
import TextifySettings

@main
struct TextifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services: AppServices

    init() {
        let services = AppServices.production()
        _services = State(initialValue: services)
        AppDelegate.launchCoordinator = AppLaunchCoordinator(services: services) {
            TextifyOnboardingWindowPresenter.shared.show(services: services)
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
    }
}

enum AppLaunchAction: Equatable {
    case showOnboarding
    case startRuntime
}

enum AppLaunchPolicy {
    static func action(for preferences: AppPreferences) -> AppLaunchAction {
        preferences.onboardingCompleted ? .startRuntime : .showOnboarding
    }
}

@MainActor
final class AppLaunchCoordinator {
    private let services: AppServices
    private let showOnboarding: @MainActor () -> Void
    private var didRun = false

    init(
        services: AppServices,
        showOnboarding: @escaping @MainActor () -> Void
    ) {
        self.services = services
        self.showOnboarding = showOnboarding
    }

    func run() async {
        guard !didRun else {
            return
        }
        didRun = true

        switch AppLaunchPolicy.action(for: services.preferences) {
        case .showOnboarding:
            showOnboarding()
            await services.dictation.refreshReadiness()
        case .startRuntime:
            services.startRuntime()
        }
    }
}

@MainActor
final class TextifyOnboardingWindowPresenter {
    static let shared = TextifyOnboardingWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(services: AppServices) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Textify Onboarding"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: OnboardingRootView { [weak window] in
                window?.close()
            }
                .environment(services)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
    }
}
