import TextifyDiagnostics
import XCTest

final class SmokeTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(TextifyDiagnosticsModule.name, "TextifyDiagnostics")
    }
}
