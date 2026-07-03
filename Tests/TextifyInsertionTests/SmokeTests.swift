import TextifyInsertion
import XCTest

final class SmokeTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(TextifyInsertionModule.name, "TextifyInsertion")
    }
}
