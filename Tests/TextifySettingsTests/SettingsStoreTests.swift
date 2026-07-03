import TextifySettings
import XCTest

final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchV1Spec() throws {
        let store = SettingsStore(storage: .memory)
        let preferences = store.load()
        XCTAssertEqual(preferences.trigger, .rightCommand)
        XCTAssertEqual(preferences.microphoneSelection, .systemDefault)
        XCTAssertEqual(preferences.transcriptionLanguage, .english)
        XCTAssertEqual(preferences.modelSelectionScope, .curatedInstalledModels)
        XCTAssertFalse(preferences.showInDock)
        XCTAssertTrue(preferences.automaticallyCheckForUpdates)
        XCTAssertTrue(preferences.launchAtLoginEnabled)
        XCTAssertTrue(preferences.excludedApps.isEmpty)
    }

    func testDecodesOldLaunchAtLoginRequestedByOnboardingIntoLaunchAtLoginEnabled() throws {
        let json = """
        {
          "trigger": "rightCommand",
          "microphoneSelection": "systemDefault",
          "transcriptionLanguage": "en",
          "modelSelectionScope": "curatedInstalledModels",
          "launchAtLoginRequestedByOnboarding": false,
          "onboardingCompleted": true
        }
        """
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertFalse(preferences.launchAtLoginEnabled)
        XCTAssertTrue(preferences.onboardingCompleted)
    }

    func testResetOnboardingDoesNotDeleteUserData() throws {
        let store = SettingsStore(storage: .memory)
        var preferences = store.load()
        preferences.onboardingCompleted = true
        preferences.hasShownNoModelNotice = true
        preferences.excludedApps = [
            ExcludedApp(
                bundleIdentifier: "com.example.App",
                displayName: "Example",
                lastKnownPath: "/Applications/Example.app"
            )
        ]
        store.save(preferences)

        store.resetOnboarding()
        let reloaded = store.load()
        XCTAssertFalse(reloaded.onboardingCompleted)
        XCTAssertFalse(reloaded.hasShownNoModelNotice)
        XCTAssertEqual(reloaded.excludedApps.count, 1)
    }

    func testFileStoragePersistsAsPlainJSON() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("preferences.json")
        let store = SettingsStore(storage: .file(fileURL))
        var preferences = store.load()
        preferences.trigger = .rightOption
        preferences.showInDock = true
        preferences.activeModelID = "whisper-small-en-balanced"
        store.save(preferences)

        let reloaded = SettingsStore(storage: .file(fileURL)).load()
        XCTAssertEqual(reloaded.trigger, .rightOption)
        XCTAssertTrue(reloaded.showInDock)
        XCTAssertEqual(reloaded.activeModelID, "whisper-small-en-balanced")

        let json = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        XCTAssertTrue(json.contains("\"trigger\""))
        XCTAssertTrue(json.contains("rightOption"))
        XCTAssertTrue(json.contains("\"launchAtLoginEnabled\""))
        XCTAssertFalse(json.contains("launchAtLoginRequestedByOnboarding"))
        XCTAssertFalse(json.contains("developerModeEnabled"))
        XCTAssertFalse(json.contains("encrypted"))
    }

    func testV1DoesNotExposeArbitraryModelsOrPerAppProfiles() throws {
        XCTAssertEqual(AppPreferences.supportedTranscriptionLanguages, [.english])
        XCTAssertFalse(AppPreferences.allowsArbitraryModelImports)
        XCTAssertFalse(AppPreferences.supportsPerAppProfiles)
    }

    func testInvalidStoredPreferencesRecordsSettingsStoreError() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("preferences.json")
        try Data("{".utf8).write(to: fileURL)

        let store = SettingsStore(storage: .file(fileURL))
        let preferences = store.load()

        XCTAssertEqual(preferences, .defaults)
        XCTAssertEqual(store.lastError, .decodingFailed)
    }
}
