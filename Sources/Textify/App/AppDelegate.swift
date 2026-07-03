import AppKit
import TextifySettings

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    static var launchCoordinator: AppLaunchCoordinator?

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
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else {
            return true
        }

        sender.sendAction(Self.showSettingsSelector, to: nil, from: nil)
        sender.activate(ignoringOtherApps: true)
        return false
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
            return .accessory
        }
    }

    static func activationPolicy(preferences: AppPreferences) -> NSApplication.ActivationPolicy {
        preferences.showInDock ? .regular : .accessory
    }

    private static let showSettingsSelector = Selector(("showSettingsWindow:"))
}
