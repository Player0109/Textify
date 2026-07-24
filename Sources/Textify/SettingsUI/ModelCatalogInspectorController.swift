import Observation

enum ModelCatalogInspectorLocalDetailsState: Equatable {
    case notApplicable
    case loading(artifactID: String)
    case loaded(ModelCatalogArtifactLocalDetails)
    case failed(artifactID: String)
}

enum ModelCatalogInspectorVerificationState: Equatable {
    case unavailable
    case available(artifactID: String)
    case verifying(artifactID: String)
    case verified(artifactID: String)
    case failed(artifactID: String)
}

@MainActor
@Observable
final class ModelCatalogInspectorController {
    typealias LocalDetailsLoader = @Sendable (
        ModelCatalogArtifactInspectionRequest
    ) async throws -> ModelCatalogArtifactLocalDetails
    typealias IntegrityVerifier = @Sendable (
        ModelCatalogArtifactVerificationRequest
    ) async throws -> Void

    private(set) var presentation: ModelCatalogInspectorPresentation?
    private(set) var localDetailsState: ModelCatalogInspectorLocalDetailsState = .notApplicable
    private(set) var verificationState: ModelCatalogInspectorVerificationState = .unavailable

    @ObservationIgnored private let loadLocalDetails: LocalDetailsLoader
    @ObservationIgnored private let verifyIntegrity: IntegrityVerifier
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var verificationTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0

    init(
        loadLocalDetails: @escaping LocalDetailsLoader = {
            try await ModelCatalogArtifactInventoryReader.load(request: $0)
        },
        verifyIntegrity: @escaping IntegrityVerifier = {
            try await ModelCatalogArtifactVerifier.verify(request: $0)
        }
    ) {
        self.loadLocalDetails = loadLocalDetails
        self.verifyIntegrity = verifyIntegrity
    }

    func select(
        _ selection: ModelCatalogHierarchySelection?,
        in experience: ModelCatalogExperience
    ) {
        let nextPresentation = selection.flatMap {
            experience.inspectorPresentation(for: $0)
        }
        guard nextPresentation != presentation else {
            return
        }

        loadTask?.cancel()
        loadTask = nil
        verificationTask?.cancel()
        verificationTask = nil
        generation &+= 1
        let selectionGeneration = generation
        presentation = nextPresentation
        if case let .exactArtifact(artifact) = presentation,
           artifact.verificationRequest != nil {
            verificationState = .available(artifactID: artifact.id)
        } else {
            verificationState = .unavailable
        }

        guard case let .exactArtifact(artifact) = presentation,
              let request = artifact.localInspectionRequest
        else {
            localDetailsState = .notApplicable
            return
        }

        localDetailsState = .loading(artifactID: artifact.id)
        loadTask = Task { [weak self, loadLocalDetails] in
            do {
                let details = try await loadLocalDetails(request)
                try Task.checkCancellation()
                guard let self, self.generation == selectionGeneration else {
                    return
                }
                self.localDetailsState = .loaded(details)
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.generation == selectionGeneration else {
                    return
                }
                self.localDetailsState = .failed(artifactID: request.artifactID)
            }
        }
    }

    func verifySelectedArtifact() {
        guard case let .exactArtifact(artifact) = presentation,
              let request = artifact.verificationRequest else {
            return
        }
        verificationTask?.cancel()
        let verificationGeneration = generation
        verificationState = .verifying(artifactID: artifact.id)
        verificationTask = Task { [weak self, verifyIntegrity] in
            do {
                try await verifyIntegrity(request)
                try Task.checkCancellation()
                guard let self, self.generation == verificationGeneration else {
                    return
                }
                self.verificationState = .verified(artifactID: artifact.id)
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.generation == verificationGeneration else {
                    return
                }
                self.verificationState = .failed(artifactID: artifact.id)
            }
        }
    }
}
