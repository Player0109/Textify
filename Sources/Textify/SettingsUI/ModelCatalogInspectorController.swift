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
    typealias IntegrityVerifier = @Sendable (
        ModelCatalogArtifactVerificationRequest
    ) async throws -> Void

    private(set) var presentation: ModelCatalogInspectorPresentation?
    private(set) var localDetailsState: ModelCatalogInspectorLocalDetailsState = .notApplicable
    private(set) var verificationState: ModelCatalogInspectorVerificationState = .unavailable

    @ObservationIgnored private let verifyIntegrity: IntegrityVerifier
    @ObservationIgnored private var verificationTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0

    init(
        verifyIntegrity: @escaping IntegrityVerifier = {
            try await ModelCatalogArtifactVerifier.verify(request: $0)
        }
    ) {
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

        verificationTask?.cancel()
        verificationTask = nil
        generation &+= 1
        presentation = nextPresentation
        if case let .exactArtifact(artifact) = presentation,
           artifact.verificationRequest != nil
        {
            verificationState = .available(artifactID: artifact.id)
        } else {
            verificationState = .unavailable
        }

        guard case let .exactArtifact(artifact) = presentation else {
            localDetailsState = .notApplicable
            return
        }
        if let localDetails = artifact.localDetails {
            localDetailsState = .loaded(localDetails)
        } else if artifact.canVerify {
            localDetailsState = switch artifact.localDetailsStatus {
            case .calculating:
                .loading(artifactID: artifact.id)
            case .measured, .unavailable:
                .failed(artifactID: artifact.id)
            }
        } else {
            localDetailsState = .notApplicable
        }
    }

    func verifySelectedArtifact() {
        guard case let .exactArtifact(artifact) = presentation,
              let request = artifact.verificationRequest
        else {
            return
        }
        verificationTask?.cancel()
        let verificationGeneration = generation
        verificationState = .verifying(artifactID: artifact.id)
        verificationTask = Task { [weak self, verifyIntegrity] in
            do {
                try await verifyIntegrity(request)
                try Task.checkCancellation()
                guard let self, generation == verificationGeneration else {
                    return
                }
                verificationState = .verified(artifactID: artifact.id)
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == verificationGeneration else {
                    return
                }
                verificationState = .failed(artifactID: artifact.id)
            }
        }
    }
}
