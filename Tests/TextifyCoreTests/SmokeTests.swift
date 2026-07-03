import TextifyCore
import XCTest

final class SmokeTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(TextifyCoreModule.name, "TextifyCore")
    }
}
