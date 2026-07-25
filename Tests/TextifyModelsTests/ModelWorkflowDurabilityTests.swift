import Foundation
import TextifyModels
import XCTest

final class ModelWorkflowDurabilityTests: XCTestCase {
    func testObserverIsInertByDefault() throws {
        try ModelWorkflowDurabilityObserver.none.didReach(
            .installationReceiptPersisted,
            artifactID: "artifact"
        )
    }

    func testObserverCarriesExactBoundaryAndArtifactIdentity() throws {
        let recorder = ModelWorkflowBoundaryRecorder()
        try recorder.observer.didReach(
            .activationPreferencePersisted,
            artifactID: "artifact-a"
        )

        XCTAssertEqual(
            recorder.events,
            [
                ModelWorkflowBoundaryEvent(
                    boundary: .activationPreferencePersisted,
                    artifactID: "artifact-a"
                ),
            ]
        )
    }
}

struct ModelWorkflowBoundaryEvent: Equatable {
    let boundary: ModelWorkflowDurableBoundary
    let artifactID: String?
}

final class ModelWorkflowBoundaryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [ModelWorkflowBoundaryEvent] = []

    var observer: ModelWorkflowDurabilityObserver {
        ModelWorkflowDurabilityObserver { [weak self] boundary, artifactID in
            self?.append(boundary: boundary, artifactID: artifactID)
        }
    }

    var events: [ModelWorkflowBoundaryEvent] {
        lock.withLock { recordedEvents }
    }

    private func append(
        boundary: ModelWorkflowDurableBoundary,
        artifactID: String?
    ) {
        lock.withLock {
            recordedEvents.append(
                ModelWorkflowBoundaryEvent(
                    boundary: boundary,
                    artifactID: artifactID
                )
            )
        }
    }
}
