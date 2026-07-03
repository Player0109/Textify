import TextifyInsertion
import XCTest

final class InsertionTargetCheckerTests: XCTestCase {
    func testCheckerCanAllowCurrentTarget() async {
        let checker = StaticTargetChecker(status: .allowed)

        let status = await checker.currentTargetStatus()

        XCTAssertEqual(status, .allowed)
    }

    func testCheckerCanBlockSecureContexts() async {
        let checker = StaticTargetChecker(status: .blocked(.secureInputEnabled))

        let status = await checker.currentTargetStatus()

        XCTAssertEqual(status, .blocked(.secureInputEnabled))
    }
}

private struct StaticTargetChecker: InsertionTargetChecking {
    let status: InsertionTargetStatus

    func currentTargetStatus() async -> InsertionTargetStatus {
        status
    }
}
