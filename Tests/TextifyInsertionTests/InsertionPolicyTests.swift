import TextifyInsertion
import XCTest

final class InsertionPolicyTests: XCTestCase {
    func testDoesNotFallbackAfterPasteWasPosted() {
        let decision = InsertionPolicy().fallbackDecision(
            pasteEventPosted: true,
            textLength: 50,
            containsControlCharacters: false,
            targetStillMatches: true,
            secureFieldDetected: false
        )
        XCTAssertEqual(decision, .doNotFallback(reason: "paste_outcome_unobservable"))
    }

    func testFallbackAllowedOnlyForShortPlainTextBeforePaste() {
        let decision = InsertionPolicy().fallbackDecision(
            pasteEventPosted: false,
            textLength: 120,
            containsControlCharacters: false,
            targetStillMatches: true,
            secureFieldDetected: false
        )
        XCTAssertEqual(decision, .fallbackWithUnicodeChunks(maxScalarsPerChunk: 20))
    }
}
