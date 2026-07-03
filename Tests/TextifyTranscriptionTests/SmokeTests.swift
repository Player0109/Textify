import TextifyTranscription
import XCTest

final class SmokeTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(TextifyTranscriptionModule.name, "TextifyTranscription")
    }
}
