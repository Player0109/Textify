import Foundation
import Observation
import os
import TextifyModels

struct ModelCatalogLayerVersions: Equatable, Sendable {
    let catalogIndex: UInt64
    let eligibilityIndex: UInt64
    let localStateOverlay: UInt64
    let queryResult: UInt64
}

struct ModelCatalogIndexStatistics: Equatable, Sendable {
    let families: Int
    let checkpoints: Int
    let exactArtifacts: Int
}

struct ModelCatalogDerivationRequest: Equatable, @unchecked Sendable {
    let catalogRevision: String?
    let trustedManifest: ModelManifest?
    let compatibilityContext: ModelCatalogCompatibilityContext
    let localRevision: UInt64
    let installedRecords: [InstalledModelRecord]
    let activeTranscriptionModelID: String?
    let activeVoiceCleaningModelID: String?
    let transferStatesByModelID: [String: DownloadState]
    let revocationOverlay: ModelRevocationOverlay
    let managedReadinessByModelID: [String: ModelCatalogManagedReadiness]
    let onDiskBytesByModelID: [String: Int64]
    let storageInventoryByModelID: [String: ModelStorageArtifactInventory]
    let installedSizeStatus: ModelCatalogInstalledSizeStatus
    var query: ModelCatalogQuery

    static func == (
        lhs: ModelCatalogDerivationRequest,
        rhs: ModelCatalogDerivationRequest
    ) -> Bool {
        lhs.catalogRevision == rhs.catalogRevision
            && lhs.compatibilityContext == rhs.compatibilityContext
            && lhs.localRevision == rhs.localRevision
            && lhs.installedRecords == rhs.installedRecords
            && lhs.activeTranscriptionModelID
                == rhs.activeTranscriptionModelID
            && lhs.activeVoiceCleaningModelID
                == rhs.activeVoiceCleaningModelID
            && lhs.transferStatesByModelID
                == rhs.transferStatesByModelID
            && lhs.revocationOverlay == rhs.revocationOverlay
            && lhs.managedReadinessByModelID
                == rhs.managedReadinessByModelID
            && lhs.onDiskBytesByModelID == rhs.onDiskBytesByModelID
            && lhs.storageInventoryByModelID
                == rhs.storageInventoryByModelID
            && lhs.installedSizeStatus == rhs.installedSizeStatus
            && lhs.query == rhs.query
    }
}

struct ModelCatalogDerivationSnapshot: Equatable, @unchecked Sendable {
    let versions: ModelCatalogLayerVersions
    let indexStatistics: ModelCatalogIndexStatistics
    let query: ModelCatalogQuery
    let experience: ModelCatalogExperience
}

actor ModelCatalogDerivationEngine {
    typealias BeforeDerivation =
        @Sendable (ModelCatalogDerivationRequest) async throws -> Void

    private struct CatalogIndex: Sendable {
        let version: UInt64
        let revision: String?
        let presentation: ModelCatalogPresentationIndex

        var statistics: ModelCatalogIndexStatistics {
            ModelCatalogIndexStatistics(
                families: presentation.familiesByID.count,
                checkpoints: presentation.checkpointsByID.count,
                exactArtifacts: presentation.artifactsByID.count
            )
        }
    }

    private struct EligibilityIndex: @unchecked Sendable {
        let version: UInt64
        let catalogVersion: UInt64
        let context: ModelCatalogCompatibilityContext
        let compatibilityByModelID: [String: ModelCatalogCompatibility]
        let checkpointResolutions:
            [String: ModelCatalogCheckpointResolution]
    }

    private struct LocalStateOverlay: @unchecked Sendable {
        let version: UInt64
        let revision: UInt64
        let installedRecords: [InstalledModelRecord]
        let activePreferences: ModelCatalogActivePreferences
        let transferStatesByModelID: [String: DownloadState]
        let revocationOverlay: ModelRevocationOverlay
        let managedReadinessByModelID:
            [String: ModelCatalogManagedReadiness]
        let onDiskBytesByModelID: [String: Int64]
        let storageInventoryByModelID:
            [String: ModelStorageArtifactInventory]
        let installedSizeStatus: ModelCatalogInstalledSizeStatus
    }

    private struct QueryKey: Equatable, @unchecked Sendable {
        let catalogVersion: UInt64
        let eligibilityVersion: UInt64
        let installedRecords: [InstalledModelRecord]
        let activeTranscriptionModelID: String?
        let activeVoiceCleaningModelID: String?
        let transferStatesByModelID: [String: DownloadState]
        let revocationOverlay: ModelRevocationOverlay
        let managedReadinessByModelID:
            [String: ModelCatalogManagedReadiness]
        let onDiskBytesByModelID: [String: Int64]
        let storageInventoryByModelID:
            [String: ModelStorageArtifactInventory]
        let installedSizeStatus: ModelCatalogInstalledSizeStatus
        let query: ModelCatalogQuery
    }

    private struct QueryResult: @unchecked Sendable {
        let version: UInt64
        let key: QueryKey
        let baseExperience: ModelCatalogExperience
    }

    private let beforeDerivation: BeforeDerivation
    private var catalogIndex: CatalogIndex?
    private var eligibilityIndex: EligibilityIndex?
    private var localStateOverlay: LocalStateOverlay?
    private var queryResult: QueryResult?

    init(
        beforeDerivation: @escaping BeforeDerivation = { _ in }
    ) {
        self.beforeDerivation = beforeDerivation
    }

    func derive(
        _ request: ModelCatalogDerivationRequest
    ) async throws -> ModelCatalogDerivationSnapshot {
        try await beforeDerivation(request)
        try Task.checkCancellation()

        let trace = ModelCatalogPerformanceTrace.begin("derive")
        defer { ModelCatalogPerformanceTrace.end("derive", trace) }

        let catalog = try deriveCatalogIndex(from: request)
        let eligibility = try deriveEligibilityIndex(
            catalog: catalog,
            context: request.compatibilityContext
        )
        let localState = deriveLocalStateOverlay(from: request)
        try Task.checkCancellation()
        let query = try deriveQueryResult(
            catalog: catalog,
            eligibility: eligibility,
            localState: localState,
            query: request.query
        )
        try Task.checkCancellation()

        let experience = query.baseExperience.applyingTransferStates(
            localState.transferStatesByModelID
        )
        return ModelCatalogDerivationSnapshot(
            versions: ModelCatalogLayerVersions(
                catalogIndex: catalog.version,
                eligibilityIndex: eligibility.version,
                localStateOverlay: localState.version,
                queryResult: query.version
            ),
            indexStatistics: catalog.statistics,
            query: request.query,
            experience: experience
        )
    }

    private func deriveCatalogIndex(
        from request: ModelCatalogDerivationRequest
    ) throws -> CatalogIndex {
        if let catalogIndex,
           catalogIndex.revision == request.catalogRevision {
            return catalogIndex
        }
        try Task.checkCancellation()
        let trace = ModelCatalogPerformanceTrace.begin("catalog-index")
        defer { ModelCatalogPerformanceTrace.end("catalog-index", trace) }
        let next = CatalogIndex(
            version: (catalogIndex?.version ?? 0) &+ 1,
            revision: request.catalogRevision,
            presentation: ModelCatalogPresentationIndex(
                trustedManifest: request.trustedManifest
            )
        )
        catalogIndex = next
        return next
    }

    private func deriveEligibilityIndex(
        catalog: CatalogIndex,
        context: ModelCatalogCompatibilityContext
    ) throws -> EligibilityIndex {
        if let eligibilityIndex,
           eligibilityIndex.catalogVersion == catalog.version,
           eligibilityIndex.context == context {
            return eligibilityIndex
        }
        try Task.checkCancellation()
        let trace = ModelCatalogPerformanceTrace.begin("eligibility-index")
        defer {
            ModelCatalogPerformanceTrace.end("eligibility-index", trace)
        }
        let resolver = ModelCatalogCompatibilityResolver(context: context)
        let next = EligibilityIndex(
            version: (eligibilityIndex?.version ?? 0) &+ 1,
            catalogVersion: catalog.version,
            context: context,
            compatibilityByModelID:
                resolver.compatibilityByModelID(
                    in: catalog.presentation.trustedManifest
                ) ?? [:],
            checkpointResolutions:
                resolver.checkpointResolutions(
                    in: catalog.presentation.trustedManifest
                ) ?? [:]
        )
        eligibilityIndex = next
        return next
    }

    private func deriveLocalStateOverlay(
        from request: ModelCatalogDerivationRequest
    ) -> LocalStateOverlay {
        if let localStateOverlay,
           localStateOverlay.revision == request.localRevision,
           localStateOverlay.installedRecords == request.installedRecords,
           localStateOverlay.activePreferences
                == activePreferences(from: request),
           localStateOverlay.transferStatesByModelID
                == request.transferStatesByModelID,
           localStateOverlay.revocationOverlay == request.revocationOverlay,
           localStateOverlay.managedReadinessByModelID
                == request.managedReadinessByModelID,
           localStateOverlay.onDiskBytesByModelID
                == request.onDiskBytesByModelID,
           localStateOverlay.storageInventoryByModelID
                == request.storageInventoryByModelID,
           localStateOverlay.installedSizeStatus
                == request.installedSizeStatus {
            return localStateOverlay
        }
        let trace = ModelCatalogPerformanceTrace.begin("local-overlay")
        defer { ModelCatalogPerformanceTrace.end("local-overlay", trace) }
        let next = LocalStateOverlay(
            version: (localStateOverlay?.version ?? 0) &+ 1,
            revision: request.localRevision,
            installedRecords: request.installedRecords,
            activePreferences: activePreferences(from: request),
            transferStatesByModelID: request.transferStatesByModelID,
            revocationOverlay: request.revocationOverlay,
            managedReadinessByModelID: request.managedReadinessByModelID,
            onDiskBytesByModelID: request.onDiskBytesByModelID,
            storageInventoryByModelID: request.storageInventoryByModelID,
            installedSizeStatus: request.installedSizeStatus
        )
        localStateOverlay = next
        return next
    }

    private func deriveQueryResult(
        catalog: CatalogIndex,
        eligibility: EligibilityIndex,
        localState: LocalStateOverlay,
        query: ModelCatalogQuery
    ) throws -> QueryResult {
        let normalizedTransfers = localState.transferStatesByModelID.mapValues {
            DownloadState(
                modelID: $0.modelID,
                phase: $0.phase,
                message: $0.phase.rawValue,
                attemptID: $0.attemptID
            )
        }
        let key = QueryKey(
            catalogVersion: catalog.version,
            eligibilityVersion: eligibility.version,
            installedRecords: localState.installedRecords,
            activeTranscriptionModelID:
                localState.activePreferences.transcriptionModelID,
            activeVoiceCleaningModelID:
                localState.activePreferences.voiceCleaningModelID,
            transferStatesByModelID: normalizedTransfers,
            revocationOverlay: localState.revocationOverlay,
            managedReadinessByModelID:
                localState.managedReadinessByModelID,
            onDiskBytesByModelID: localState.onDiskBytesByModelID,
            storageInventoryByModelID:
                localState.storageInventoryByModelID,
            installedSizeStatus: localState.installedSizeStatus,
            query: query
        )
        if let queryResult, queryResult.key == key {
            return queryResult
        }
        try Task.checkCancellation()
        let trace = ModelCatalogPerformanceTrace.begin("query-result")
        defer { ModelCatalogPerformanceTrace.end("query-result", trace) }
        let next = QueryResult(
            version: (queryResult?.version ?? 0) &+ 1,
            key: key,
            baseExperience: ModelCatalogExperience(
                catalogIndex: catalog.presentation,
                compatibilityByModelID:
                    eligibility.compatibilityByModelID,
                checkpointResolutions:
                    eligibility.checkpointResolutions,
                installedRecords: localState.installedRecords,
                activePreferences: localState.activePreferences,
                transferStatesByModelID: normalizedTransfers,
                revocationOverlay: localState.revocationOverlay,
                managedReadinessByModelID:
                    localState.managedReadinessByModelID,
                onDiskBytesByModelID: localState.onDiskBytesByModelID,
                storageInventoryByModelID:
                    localState.storageInventoryByModelID,
                installedSizeStatus: localState.installedSizeStatus,
                query: query
            )
        )
        queryResult = next
        return next
    }

    private func activePreferences(
        from request: ModelCatalogDerivationRequest
    ) -> ModelCatalogActivePreferences {
        ModelCatalogActivePreferences(
            transcriptionModelID: request.activeTranscriptionModelID,
            voiceCleaningModelID: request.activeVoiceCleaningModelID
        )
    }
}

@MainActor
@Observable
final class ModelCatalogDerivationCoordinator {
    private(set) var snapshot: ModelCatalogDerivationSnapshot?
    private(set) var publishedGeneration: UInt64 = 0
    private(set) var isDeriving = false

    @ObservationIgnored private let engine: ModelCatalogDerivationEngine
    @ObservationIgnored private let searchDebounceNanoseconds: UInt64
    @ObservationIgnored private var requestedGeneration: UInt64 = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastSubmittedQuery: ModelCatalogQuery?
    @ObservationIgnored private var lastSubmittedRequest:
        ModelCatalogDerivationRequest?

    init(
        engine: ModelCatalogDerivationEngine = ModelCatalogDerivationEngine(),
        searchDebounceNanoseconds: UInt64 = 125_000_000,
        initialSnapshot: ModelCatalogDerivationSnapshot? = nil
    ) {
        self.engine = engine
        self.searchDebounceNanoseconds = searchDebounceNanoseconds
        snapshot = initialSnapshot
    }

    func submit(_ request: ModelCatalogDerivationRequest) {
        guard request != lastSubmittedRequest
                || (snapshot == nil && task == nil)
        else {
            return
        }
        lastSubmittedRequest = request
        requestedGeneration &+= 1
        let generation = requestedGeneration
        let previousSearch = lastSubmittedQuery?.searchText
        lastSubmittedQuery = request.query
        task?.cancel()
        isDeriving = true
        task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                if let previousSearch,
                   previousSearch != request.query.searchText,
                   searchDebounceNanoseconds > 0 {
                    try await Task.sleep(
                        nanoseconds: searchDebounceNanoseconds
                    )
                }
                let result = try await engine.derive(request)
                try Task.checkCancellation()
                guard generation == requestedGeneration else {
                    return
                }
                let trace = ModelCatalogPerformanceTrace.begin("publish")
                snapshot = result
                publishedGeneration = generation
                isDeriving = false
                task = nil
                ModelCatalogPerformanceTrace.end("publish", trace)
            } catch {
                guard generation == requestedGeneration else {
                    return
                }
                isDeriving = false
                task = nil
                lastSubmittedRequest = nil
            }
        }
    }

    func cancel() {
        requestedGeneration &+= 1
        task?.cancel()
        task = nil
        isDeriving = false
        lastSubmittedRequest = nil
    }

    func waitUntilSettled() async {
        while task != nil {
            await Task.yield()
        }
    }
}

@MainActor
@Observable
final class ModelCatalogFeatureModel {
    let purpose: ModelPurpose
    var discoveryQuery: ModelCatalogQuery
    var browseAllLanguages = false
    var checkpointOrderIDs: [String] = []
    var refreshCheckpointOrderOnNextEntry = false
    var hierarchyState = ModelCatalogHierarchyState()
    var reconciledCatalogExperience: ModelCatalogExperience?
    var viewportRestorationGeneration: UInt64 = 0
    let inspectorController = ModelCatalogInspectorController()
    var verificationRestorationIDsByArtifact: [String: [String]] = [:]
    var announcementTracker = ModelCatalogAnnouncementTracker()
    var showsInspector = false

    @ObservationIgnored private let derivationCoordinator:
        ModelCatalogDerivationCoordinator

    init(
        purpose: ModelPurpose,
        engine: ModelCatalogDerivationEngine,
        searchDebounceNanoseconds: UInt64,
        initialSnapshot: ModelCatalogDerivationSnapshot? = nil
    ) {
        self.purpose = purpose
        discoveryQuery = ModelCatalogQuery(purpose: purpose)
        reconciledCatalogExperience = initialSnapshot?.experience
        derivationCoordinator = ModelCatalogDerivationCoordinator(
            engine: engine,
            searchDebounceNanoseconds: searchDebounceNanoseconds,
            initialSnapshot: initialSnapshot
        )
    }

    var snapshot: ModelCatalogDerivationSnapshot? {
        derivationCoordinator.snapshot
    }

    var publishedGeneration: UInt64 {
        derivationCoordinator.publishedGeneration
    }

    func submit(_ request: ModelCatalogDerivationRequest) {
        derivationCoordinator.submit(request)
    }

    func waitUntilSettled() async {
        await derivationCoordinator.waitUntilSettled()
    }

}

@MainActor
final class ModelCatalogFeatureStore {
    private let transcription: ModelCatalogFeatureModel
    private let voiceCleaning: ModelCatalogFeatureModel

    init(
        engine: ModelCatalogDerivationEngine =
            ModelCatalogDerivationEngine(),
        searchDebounceNanoseconds: UInt64 = 125_000_000,
        initialSnapshots: [
            ModelPurpose: ModelCatalogDerivationSnapshot
        ] = [:]
    ) {
        transcription = ModelCatalogFeatureModel(
            purpose: .transcription,
            engine: engine,
            searchDebounceNanoseconds: searchDebounceNanoseconds,
            initialSnapshot: initialSnapshots[.transcription]
        )
        voiceCleaning = ModelCatalogFeatureModel(
            purpose: .voiceCleaning,
            engine: engine,
            searchDebounceNanoseconds: searchDebounceNanoseconds,
            initialSnapshot: initialSnapshots[.voiceCleaning]
        )
    }

    func feature(for purpose: ModelPurpose) -> ModelCatalogFeatureModel {
        switch purpose {
        case .transcription:
            transcription
        case .voiceCleaning:
            voiceCleaning
        }
    }

    var retainedSnapshots: [
        ModelPurpose: ModelCatalogDerivationSnapshot
    ] {
        var snapshots: [
            ModelPurpose: ModelCatalogDerivationSnapshot
        ] = [:]
        snapshots[.transcription] = transcription.snapshot
        snapshots[.voiceCleaning] = voiceCleaning.snapshot
        return snapshots
    }
}

enum ModelCatalogPerformanceTrace {
    private static let signposter = OSSignposter(
        subsystem: "io.github.Player0109.Textify",
        category: "ModelCatalog"
    )

    static func begin(
        _ name: StaticString
    ) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func end(
        _ name: StaticString,
        _ state: OSSignpostIntervalState
    ) {
        signposter.endInterval(name, state)
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
