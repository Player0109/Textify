import TextifyAudio
import XCTest

final class MicrophonePermissionClientTests: XCTestCase {
    func testUsesInjectedPermissionClosures() async {
        let client = MicrophonePermissionClient(
            status: { .notDetermined },
            requestAccess: { .granted }
        )

        XCTAssertEqual(client.status(), .notDetermined)
        let requestStatus = await client.requestAccess()
        XCTAssertEqual(requestStatus, .granted)
    }
}
