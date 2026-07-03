import TextifyRuntime
import XCTest

final class TextifyRuntimeSmokeTests: XCTestCase {
    func testModuleMarker() {
        XCTAssertEqual(TextifyRuntimeModule.name, "TextifyRuntime")
    }
}
