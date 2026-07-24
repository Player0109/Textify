import Observation
import TextifyModels

enum ModelStorageInventoryLoadState: Equatable {
    case calculating
    case available(
        generation: UInt64,
        snapshot: ModelStorageInventorySnapshot
    )
    case unavailable(generation: UInt64)
}

@MainActor
@Observable
final class ModelStorageInventoryCoordinator {
    typealias LoadOperation = @Sendable (
        [InstalledModelRecord]
    ) async throws -> ModelStorageInventorySnapshot

    private(set) var state: ModelStorageInventoryLoadState = .calculating

    @ObservationIgnored private let loadOperation: LoadOperation
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var pendingRequest: Request?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(loadOperation: @escaping LoadOperation) {
        self.loadOperation = loadOperation
    }

    func refresh(installedRecords: [InstalledModelRecord]) {
        generation &+= 1
        pendingRequest = Request(
            generation: generation,
            installedRecords: installedRecords
        )
        startNextRequestIfNeeded()
    }

    private func startNextRequestIfNeeded() {
        guard loadTask == nil, let request = pendingRequest else {
            return
        }
        pendingRequest = nil
        let loadOperation = loadOperation
        loadTask = Task { @MainActor [weak self] in
            let result: Result<ModelStorageInventorySnapshot, Error>
            do {
                result = try await .success(
                    loadOperation(request.installedRecords)
                )
            } catch {
                result = .failure(error)
            }

            guard let self else {
                return
            }
            loadTask = nil
            if request.generation == generation {
                switch result {
                case let .success(snapshot):
                    state = .available(
                        generation: request.generation,
                        snapshot: snapshot
                    )
                case .failure:
                    state = .unavailable(
                        generation: request.generation
                    )
                }
            }
            startNextRequestIfNeeded()
        }
    }
}

private extension ModelStorageInventoryCoordinator {
    struct Request {
        let generation: UInt64
        let installedRecords: [InstalledModelRecord]
    }
}
