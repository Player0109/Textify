import Foundation

public enum ModelWorkflowDurableBoundary:
    String,
    CaseIterable,
    Codable,
    Sendable
{
    case queueAuthorizationPersisted
    case queueAttemptStartedPersisted
    case partialMetadataPersisted
    case installationStaged
    case installationReceiptPersisted
    case activationPrepared
    case activationPreferencePersisted
    case revocationRestorationPersisted
    case restorationIntegrityAcknowledged
    case deletionRenamedPending
    case deletionBytesRemoved
    case deletionReceiptRemoved
    case reconciliationReceiptPersisted
}

public struct ModelWorkflowDurabilityObserver: Sendable {
    public static let none = ModelWorkflowDurabilityObserver()

    private let operation:
        @Sendable (ModelWorkflowDurableBoundary, String?) throws -> Void

    public init() {
        operation = { _, _ in }
    }

    public init(
        _ operation: @escaping @Sendable (
            ModelWorkflowDurableBoundary,
            String?
        ) throws -> Void
    ) {
        self.operation = operation
    }

    public func didReach(
        _ boundary: ModelWorkflowDurableBoundary,
        artifactID: String? = nil
    ) throws {
        try operation(boundary, artifactID)
    }
}
