import TextifySettings
import XCTest

final class SmokeTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(TextifySettingsModule.name, "TextifySettings")
    }
}
