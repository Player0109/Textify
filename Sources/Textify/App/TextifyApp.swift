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
        AppDelegate.terminationHandler = {
            await services.shutdownForTermination()
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
    private var windowDelegate: TextifyMainWindowSessionDelegate?

    private init() {}

    func show(services: AppServices) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            services.setOnboardingWindowVisibility(
                TextifyMainWindowSessionDelegate.isActuallyVisible(window)
            )
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
        let windowDelegate = TextifyMainWindowSessionDelegate(
            sessionDidEnd: {},
            visibilityDidChange: { [weak services] isVisible in
                services?.setOnboardingWindowVisibility(isVisible)
            }
        )
        window.delegate = windowDelegate
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
        self.windowDelegate = windowDelegate
        services.setOnboardingWindowVisibility(
            TextifyMainWindowSessionDelegate.isActuallyVisible(window)
        )
    }
}

@MainActor
final class TextifyMainWindowPresenter {
    static let shared = TextifyMainWindowPresenter()

    private(set) var window: NSWindow?
    private var windowDelegate: TextifyMainWindowSessionDelegate?

    init() {}

    var isVisible: Bool {
        guard let window else {
            return false
        }
        return TextifyMainWindowSessionDelegate.isActuallyVisible(window)
    }

    func show(services: AppServices) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            services.setMainWindowVisibility(
                TextifyMainWindowSessionDelegate.isActuallyVisible(window)
            )
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
        let windowDelegate = TextifyMainWindowSessionDelegate(
            sessionDidEnd: { [weak services] in
                services?.resetModelCatalogPresentationSession()
            },
            visibilityDidChange: { [weak services] isVisible in
                services?.setMainWindowVisibility(isVisible)
            }
        )
        window.delegate = windowDelegate
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
        self.windowDelegate = windowDelegate
        services.setMainWindowVisibility(
            TextifyMainWindowSessionDelegate.isActuallyVisible(window)
        )
    }
}

@MainActor
final class TextifyMainWindowSessionDelegate: NSObject, NSWindowDelegate {
    private let sessionDidEnd: @MainActor () -> Void
    private let visibilityDidChange: @MainActor (Bool) -> Void

    init(
        sessionDidEnd: @escaping @MainActor () -> Void,
        visibilityDidChange: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.sessionDidEnd = sessionDidEnd
        self.visibilityDidChange = visibilityDidChange
    }

    func windowWillClose(_ notification: Notification) {
        visibilityDidChange(false)
        sessionDidEnd()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        reportVisibility(notification)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        visibilityDidChange(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        reportVisibility(notification)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        reportVisibility(notification)
    }

    private func reportVisibility(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        visibilityDidChange(Self.isActuallyVisible(window))
    }

    static func isActuallyVisible(_ window: NSWindow) -> Bool {
        window.isVisible
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
    }
}
