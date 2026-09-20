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
    @MainActor
    static var modelInstallTerminationConfirmationProvider: (@MainActor () -> Bool)?
    @MainActor
    static var modelStorageRefreshProvider: (@MainActor () -> Void)?
    @MainActor
    static var terminationHandler: (@MainActor () async -> Void)?

    private let terminationReply: @MainActor (NSApplication, Bool) -> Void
    private var terminationTask: Task<Void, Never>?
    private var isPresentingTerminationConfirmation = false

    override init() {
        terminationReply = { application, shouldTerminate in
            application.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        super.init()
    }

    init(
        _ terminationReply: @escaping @MainActor (NSApplication, Bool) -> Void
    ) {
        self.terminationReply = terminationReply
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Self.activationPolicy())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await Self.launchCoordinator?.run()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.modelStorageRefreshProvider?()
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
        guard !isPresentingTerminationConfirmation else {
            return .terminateCancel
        }
        guard terminationTask == nil else {
            return .terminateLater
        }
        if Self.modelInstallActivityProvider?() == true {
            guard confirmTerminationDuringModelInstall() else {
                return .terminateCancel
            }
        }
        guard let terminationHandler = Self.terminationHandler else {
            return .terminateNow
        }

        let terminationReply = terminationReply
        terminationTask = Task { @MainActor in
            await terminationHandler()
            terminationReply(sender, true)
        }
        return .terminateLater
    }

    @MainActor
    private func confirmTerminationDuringModelInstall() -> Bool {
        guard !isPresentingTerminationConfirmation else {
            return false
        }
        isPresentingTerminationConfirmation = true
        defer { isPresentingTerminationConfirmation = false }
        if let confirmationProvider =
            Self.modelInstallTerminationConfirmationProvider {
            return confirmationProvider()
        }

        let alert = NSAlert()
        alert.messageText = "Quit while the model is downloading?"
        alert.informativeText = "Textify will save the Downloads queue and continue it the next time you open the app."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Textify Open")
        return alert.runModal() == .alertFirstButtonReturn
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
