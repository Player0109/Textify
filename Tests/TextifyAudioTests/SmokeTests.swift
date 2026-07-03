import TextifyAudio
import XCTest

final class SmokeTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(TextifyAudioModule.name, "TextifyAudio")
    }
}
