import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
    case failed(String)
}

@MainActor
protocol LaunchAtLoginManaging {
    func status() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) async -> LaunchAtLoginStatus
}

struct LaunchAtLoginController: LaunchAtLoginManaging {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    func status() -> LaunchAtLoginStatus {
        switch service.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) async -> LaunchAtLoginStatus {
        do {
            if enabled {
                try service.register()
            } else {
                try await service.unregister()
            }
            return status()
        } catch {
            return .failed(String(describing: error))
        }
    }
}
