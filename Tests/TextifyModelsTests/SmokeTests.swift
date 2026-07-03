import TextifyModels
import XCTest

final class SmokeTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(TextifyModelsModule.name, "TextifyModels")
    }
}
