import Foundation
import TextifyInsertion
import XCTest

final class PasteInsertionServiceTests: XCTestCase {
    func testEmptyTextTouchesNothing() async {
        let pasteboard = FakePasteboardClient()
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: ""))

        XCTAssertEqual(outcome, .notInserted(.emptyText))
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(poster.pasteCount, 0)
    }

    func testAccessibilityNotTrustedTouchesNothing() async {
        let pasteboard = FakePasteboardClient()
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .notTrusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(outcome, .notInserted(.accessibilityNotTrusted))
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(poster.pasteCount, 0)
    }

    func testBlockedTargetTouchesNothing() async {
        let pasteboard = FakePasteboardClient()
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .blocked(.secureFieldFocused)),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(outcome, .notInserted(.blockedTarget(.secureFieldFocused)))
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(poster.pasteCount, 0)
    }

    func testSnapshotFailureStopsBeforePasteboardWrite() async {
        let pasteboard = FakePasteboardClient(snapshotError: TestInsertionError.operationFailed)
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(outcome, .notInserted(.pasteboardSnapshotFailed))
        XCTAssertEqual(pasteboard.writeCount, 0)
        XCTAssertEqual(poster.pasteCount, 0)
    }

    func testPasteboardWriteFailureStopsBeforePasteEvent() async {
        let pasteboard = FakePasteboardClient(writeError: TestInsertionError.operationFailed)
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(outcome, .notInserted(.pasteboardWriteFailed))
        XCTAssertEqual(pasteboard.writeCount, 1)
        XCTAssertEqual(poster.pasteCount, 0)
    }

    func testPasteEventFailureRestoresWhenMarkerStillPresent() async {
        let pasteboard = FakePasteboardClient(markerStillPresent: true)
        let poster = FakeEventPoster(error: TestInsertionError.operationFailed)
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(outcome, .notInserted(.pasteEventFailed))
        XCTAssertEqual(pasteboard.restoreCount, 1)
    }

    func testSuccessfulPasteRestoresWhenMarkerStillPresent() async {
        let pasteboard = FakePasteboardClient(markerStillPresent: true)
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(poster.pasteCount, 1)
        XCTAssertEqual(outcome, .pasted(PasteInsertionReport(pasteboardRestored: true, pasteboardRestoreFailed: false)))
    }

    func testSuccessfulPasteDoesNotRestoreWhenMarkerIsGone() async {
        let pasteboard = FakePasteboardClient(markerStillPresent: false)
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(outcome, .pasted(PasteInsertionReport(pasteboardRestored: false, pasteboardRestoreFailed: false)))
        XCTAssertEqual(pasteboard.restoreCount, 0)
    }

    func testSuccessfulPasteSkipsRestoreWhenChangeCountChangedEvenIfMarkerRemains() async {
        let pasteboard = FakePasteboardClient(
            markerStillPresent: true,
            writeChangeCount: 8,
            currentChangeCount: 9
        )
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(outcome, .pasted(PasteInsertionReport(pasteboardRestored: false, pasteboardRestoreFailed: false)))
        XCTAssertEqual(pasteboard.restoreCount, 0)
    }

    func testSuccessfulPasteReportsRestoreFailure() async {
        let pasteboard = FakePasteboardClient(
            markerStillPresent: true,
            restoreError: TestInsertionError.operationFailed
        )
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(outcome, .pasted(PasteInsertionReport(pasteboardRestored: false, pasteboardRestoreFailed: true)))
    }

    func testPasteboardWriteFailureRestoresSnapshotAndDoesNotPostPaste() async {
        let pasteboard = FakePasteboardClient(
            changeCountAfterFailedWrite: 8,
            writeError: TestInsertionError.operationFailed
        )
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(outcome, .notInserted(.pasteboardWriteFailed))
        XCTAssertEqual(pasteboard.restoreCount, 1)
        XCTAssertEqual(poster.pasteCount, 0)
    }
}

private enum TestInsertionError: Error {
    case operationFailed
}

private final class FakePasteboardClient: PasteboardClient, @unchecked Sendable {
    var snapshotCount = 0
    var writeCount = 0
    var markerCheckCount = 0
    var restoreCount = 0
    var writtenText: String?
    var writtenMarker: PasteboardMarker?

    private let markerStillPresent: Bool
    private let writeChangeCount: Int
    private var currentChangeCountValue: Int
    private let changeCountAfterFailedWrite: Int?
    private let snapshotError: (any Error)?
    private let writeError: (any Error)?
    private let containsMarkerError: (any Error)?
    private let restoreError: (any Error)?

    init(
        markerStillPresent: Bool = true,
        writeChangeCount: Int = 8,
        currentChangeCount: Int? = nil,
        changeCountAfterFailedWrite: Int? = nil,
        snapshotError: (any Error)? = nil,
        writeError: (any Error)? = nil,
        containsMarkerError: (any Error)? = nil,
        restoreError: (any Error)? = nil
    ) {
        self.markerStillPresent = markerStillPresent
        self.writeChangeCount = writeChangeCount
        self.currentChangeCountValue = currentChangeCount ?? writeChangeCount
        self.changeCountAfterFailedWrite = changeCountAfterFailedWrite
        self.snapshotError = snapshotError
        self.writeError = writeError
        self.containsMarkerError = containsMarkerError
        self.restoreError = restoreError
    }

    func snapshot() async throws -> PasteboardSnapshot {
        snapshotCount += 1
        if let snapshotError {
            throw snapshotError
        }
        return PasteboardSnapshot(
            items: [
                PasteboardItemSnapshot(
                    representationsByType: ["public.utf8-plain-text": Data("previous".utf8)]
                )
            ],
            changeCount: 7
        )
    }

    func clearAndWritePlainText(_ text: String, marker: PasteboardMarker) async throws -> PasteboardWriteResult {
        writeCount += 1
        if let writeError {
            if let changeCountAfterFailedWrite {
                currentChangeCountValue = changeCountAfterFailedWrite
            }
            throw writeError
        }
        writtenText = text
        writtenMarker = marker
        return PasteboardWriteResult(changeCount: writeChangeCount)
    }

    func containsMarker(_ marker: PasteboardMarker) async throws -> Bool {
        markerCheckCount += 1
        if let containsMarkerError {
            throw containsMarkerError
        }
        return markerStillPresent && marker == writtenMarker
    }

    func currentChangeCount() async -> Int {
        currentChangeCountValue
    }

    func restore(
        _ snapshot: PasteboardSnapshot,
        ifCurrentChangeCountMatches expectedChangeCount: Int
    ) async throws -> Bool {
        guard currentChangeCountValue == expectedChangeCount else {
            return false
        }
        restoreCount += 1
        if let restoreError {
            throw restoreError
        }
        return true
    }
}

private final class FakeEventPoster: EventPoster, @unchecked Sendable {
    var pasteCount = 0

    private let error: (any Error)?

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func postPasteCommand() async throws {
        pasteCount += 1
        if let error {
            throw error
        }
    }
}

private struct FakeTargetChecker: InsertionTargetChecking {
    let status: InsertionTargetStatus

    func currentTargetStatus() async -> InsertionTargetStatus {
        status
    }
}
