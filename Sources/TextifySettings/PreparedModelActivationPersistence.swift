import Foundation
import TextifyModels

public enum PreparedModelActivationPersistenceError: Error, Equatable {
    case settingsWriteFailed
}

public struct PreparedModelActivationPersistence {
    private let store: SettingsStore
    private let durabilityObserver: ModelWorkflowDurabilityObserver

    public init(
        store: SettingsStore,
        durabilityObserver: ModelWorkflowDurabilityObserver = .none
    ) {
        self.store = store
        self.durabilityObserver = durabilityObserver
    }

    public func recordPrepared(modelID: String) throws {
        try durabilityObserver.didReach(
            .activationPrepared,
            artifactID: modelID
        )
    }

    public func persistSelection(
        _ preferences: AppPreferences,
        modelID: String
    ) throws {
        store.save(preferences)
        guard store.lastError == nil else {
            throw PreparedModelActivationPersistenceError
                .settingsWriteFailed
        }
        try durabilityObserver.didReach(
            .activationPreferencePersisted,
            artifactID: modelID
        )
    }
}
