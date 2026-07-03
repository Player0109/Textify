import TextifyHotkeys
import XCTest

final class SmokeTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(TextifyHotkeysModule.name, "TextifyHotkeys")
    }
}
