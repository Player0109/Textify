import XCTest
@testable import TextifyReleaseVerification

final class ModelWorkflowFaultCampaignTests: XCTestCase {
    func testCampaignCoversEveryDurableBoundaryAndRequiredFault() throws {
        let report = try ModelWorkflowFaultCampaign(seed: 24).run(operationCount: 1_000)

        XCTAssertEqual(Set(report.coveredBoundaries), Set(ModelWorkflowDurableBoundary.allCases))
        XCTAssertEqual(Set(report.injectedFaults), Set(ModelWorkflowInjectedFault.allCases))
        XCTAssertEqual(report.operationCount, 1_000)
        XCTAssertTrue(report.invariantViolations.isEmpty)
        XCTAssertEqual(report.unexplainedManagedBytes, 0)
    }

    func testEvidenceIsDeterministicForASeed() throws {
        let first = try ModelWorkflowFaultCampaign(seed: 867_5309).run(operationCount: 1_000)
        let second = try ModelWorkflowFaultCampaign(seed: 867_5309).run(operationCount: 1_000)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.reportSHA256.count, 64)
    }

    func testSecurityAndPrivacyProbesAreComplete() throws {
        let report = try ModelWorkflowFaultCampaign(seed: 24).run(operationCount: 20)

        XCTAssertEqual(Set(report.securityProbes.map(\.probe)), Set(ModelWorkflowSecurityProbe.allCases))
        XCTAssertTrue(report.securityProbes.allSatisfy(\.passed))
        XCTAssertTrue(report.catalogRequests.allSatisfy { request in
            request.method == "GET"
                && request.bodyBytes == 0
                && request.query == nil
                && request.localIdentityHeaders.isEmpty
        })
        XCTAssertFalse(report.exportedDiagnostics.containsFullSHA256)
    }
}
