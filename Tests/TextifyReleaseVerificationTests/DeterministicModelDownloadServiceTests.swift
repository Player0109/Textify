import Foundation
import XCTest
@testable import TextifyReleaseVerification

final class DeterministicModelDownloadServiceTests: XCTestCase {
    func testServiceCoversRedirectRangesValidatorChangeDisconnectAndOffline() async throws {
        let service = DeterministicModelDownloadService(payload: Data("model-bytes".utf8))
        try await service.start()
        defer { service.stop() }

        let report = try await service.exercise()

        XCTAssertTrue(report.redirectFollowed)
        XCTAssertTrue(report.validRangeResumed)
        XCTAssertTrue(report.invalidRangeRejected)
        XCTAssertTrue(report.changedValidatorRestarted)
        XCTAssertTrue(report.disconnectRetainedOnlyVerifiedPrefix)
        XCTAssertTrue(report.retrySucceeded)
        XCTAssertTrue(report.cancelRemovedPartial)
        XCTAssertTrue(report.restartRecoveredQueue)
        XCTAssertTrue(report.offlineQueueStayedDurable)
        XCTAssertTrue(report.freshnessExpiryBlockedTransfer)
    }
}
