import AppKit
import TextifySettings

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    static var launchCoordinator: AppLaunchCoordinator?
    @MainActor
    static var mainWindowOpener: (@MainActor () -> Void)?
    @MainActor
    static var mainWindowVisibilityProvider: (@MainActor () -> Bool)?
    @MainActor
    static var modelInstallActivityProvider: (@MainActor () -> Bool)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Self.activationPolicy())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await Self.launchCoordinator?.run()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows _: Bool
    ) -> Bool {
        switch AppReopenPolicy.action(
            isMainWindowVisible: Self.mainWindowVisibilityProvider?() ?? false
        ) {
        case .focusVisibleWindow:
            sender.activate(ignoringOtherApps: true)
            return true
        case .openMainWindow:
            Self.openMainWindow()
            return false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.modelInstallActivityProvider?() == true else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Quit while the model is downloading?"
        alert.informativeText = "Textify will save the Downloads queue and continue it the next time you open the app."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Textify Open")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }
        return .terminateNow
    }

    @MainActor
    static func openMainWindow() {
        mainWindowOpener?()
    }

    static func activationPolicy(
        pathFactory: () throws -> AppPaths = { try AppPaths.production() },
        fileManager: FileManager = .default
    ) -> NSApplication.ActivationPolicy {
        do {
            let paths = try pathFactory()
            let preferences = SettingsStore(
                storage: .file(paths.settingsFileURL),
                fileManager: fileManager
            ).load()
            return activationPolicy(preferences: preferences)
        } catch {
            return .regular
        }
    }

    static func activationPolicy(preferences: AppPreferences) -> NSApplication.ActivationPolicy {
        preferences.keepTextifyInDock ? .regular : .accessory
    }
}

enum AppReopenAction: Equatable {
    case focusVisibleWindow
    case openMainWindow
}

enum AppReopenPolicy {
    static func action(isMainWindowVisible: Bool) -> AppReopenAction {
        isMainWindowVisible ? .focusVisibleWindow : .openMainWindow
    }
}
