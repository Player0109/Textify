import XCTest
@testable import Textify

final class AppCompositionTests: XCTestCase {
    @MainActor
    func testProductionCompositionBuildsRuntimeServices() {
        let services = AppServices.production()

        XCTAssertEqual(services.paths.settingsFileURL.lastPathComponent, "settings.json")
        XCTAssertEqual(services.preferences, services.settingsStore.load())
        XCTAssertEqual(services.dictation.status, .idle)
    }

    func testAppPathsProductionUsesTextifySupportLocations() throws {
        let paths = try AppPaths.production()

        XCTAssertEqual(paths.applicationSupportDirectory.lastPathComponent, "Textify")
        XCTAssertEqual(paths.settingsFileURL.lastPathComponent, "settings.json")
        XCTAssertEqual(paths.modelsDirectory.lastPathComponent, "Models")
        XCTAssertEqual(paths.logsDirectory.lastPathComponent, "Textify")
    }

    func testLaunchAtLoginStatusIsEquatable() {
        XCTAssertEqual(LaunchAtLoginStatus.enabled, .enabled)
        XCTAssertNotEqual(LaunchAtLoginStatus.failed("first"), .failed("second"))
    }
}
