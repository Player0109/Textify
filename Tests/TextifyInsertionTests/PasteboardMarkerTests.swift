import Foundation
import TextifyInsertion
import XCTest

final class PasteboardMarkerTests: XCTestCase {
    func testPrivatePasteboardTypeIsStable() {
        XCTAssertEqual(PasteboardMarker.pasteboardType, "io.github.Player0109.Textify.private-marker")
    }

    func testMarkerStoresUUID() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
        let marker = PasteboardMarker(uuid: uuid)

        XCTAssertEqual(marker.uuid, uuid)
    }
}
