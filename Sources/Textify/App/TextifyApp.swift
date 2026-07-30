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
        AppDelegate.mainWindowOpener = {
            TextifyMainWindowPresenter.shared.show(services: services)
        }
        AppDelegate.mainWindowVisibilityProvider = {
            TextifyMainWindowPresenter.shared.isVisible
        }
        AppDelegate.modelInstallActivityProvider = {
            services.modelInstallCoordinator.isActive
        }
        AppDelegate.modelStorageRefreshProvider = {
            services.refreshModelStorageInventory()
        }
        AppDelegate.launchCoordinator = AppLaunchCoordinator(
            services: services,
            showOnboarding: {
                TextifyOnboardingWindowPresenter.shared.show(services: services)
            },
            showMainWindow: {
                AppDelegate.openMainWindow()
            }
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRoot()
                .environment(services)
        } label: {
            Label("Textify", systemImage: "waveform")
                .accessibilityLabel("Textify")
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(MenuBarPresentation.openTextifyTitle) {
                    services.settingsRouter.selectedPane = .general
                    TextifyMainWindowPresenter.shared.show(services: services)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
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
    private let showMainWindow: @MainActor () -> Void
    private var didRun = false

    init(
        services: AppServices,
        showOnboarding: @escaping @MainActor () -> Void,
        showMainWindow: @escaping @MainActor () -> Void
    ) {
        self.services = services
        self.showOnboarding = showOnboarding
        self.showMainWindow = showMainWindow
    }

    func run() async {
        guard !didRun else {
            return
        }
        didRun = true

        if services.startupIssue != nil {
            services.startRuntime()
            showMainWindow()
            return
        }

        _ = services.modelInstallCoordinator

        switch AppLaunchPolicy.action(for: services.preferences) {
        case .showOnboarding:
            showOnboarding()
            await services.dictation.refreshReadiness()
        case .startRuntime:
            services.startRuntime()
            showMainWindow()
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
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: TextifyWindowMetrics.onboardingWidth,
                height: TextifyWindowMetrics.onboardingHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Textify"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(TextifyVisualIdentity.windowSurface)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: OnboardingRootView { [weak window] in
                window?.close()
                AppDelegate.openMainWindow()
            }
                .environment(services)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
    }
}

@MainActor
final class TextifyMainWindowPresenter {
    static let shared = TextifyMainWindowPresenter()

    private(set) var window: NSWindow?
    private var windowDelegate: TextifyMainWindowSessionDelegate?

    init() {}

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(services: AppServices) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: TextifyWindowMetrics.mainWidth,
                height: TextifyWindowMetrics.mainHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Textify"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(TextifyVisualIdentity.windowSurface)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentMinSize = NSSize(
            width: TextifyWindowMetrics.mainMinimumWidth,
            height: TextifyWindowMetrics.mainMinimumHeight
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SettingsRootView()
                .environment(services)
        )
        let windowDelegate = TextifyMainWindowSessionDelegate {
            [weak services] in
            services?.resetModelCatalogPresentationSession()
        }
        window.delegate = windowDelegate
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
        self.windowDelegate = windowDelegate
    }
}

@MainActor
final class TextifyMainWindowSessionDelegate: NSObject, NSWindowDelegate {
    private let sessionDidEnd: @MainActor () -> Void

    init(sessionDidEnd: @escaping @MainActor () -> Void) {
        self.sessionDidEnd = sessionDidEnd
    }

    func windowWillClose(_ notification: Notification) {
        sessionDidEnd()
    }
}
