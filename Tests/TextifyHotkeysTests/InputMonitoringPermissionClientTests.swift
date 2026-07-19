@testable import TextifyHotkeys
import XCTest

final class InputMonitoringPermissionClientTests: XCTestCase {
    func testStatusUsesInjectedClosure() {
        let client = InputMonitoringPermissionClient(
            status: { .granted },
            requestAccess: { .denied }
        )

        XCTAssertEqual(client.status(), .granted)
    }

    func testRequestAccessUsesInjectedAsyncClosure() async {
        let client = InputMonitoringPermissionClient(
            status: { .unknown },
            requestAccess: { .granted }
        )

        let status = await client.requestAccess()

        XCTAssertEqual(status, .granted)
    }

    func testRequestResultMapsGrantedToGranted() {
        XCTAssertEqual(
            InputMonitoringPermissionClient.requestResult(wasGranted: true),
            .granted
        )
    }

    func testFalseRequestResultStaysUnknownInsteadOfDenied() {
        XCTAssertEqual(
            InputMonitoringPermissionClient.requestResult(wasGranted: false),
            .unknown
        )
    }
}
