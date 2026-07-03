import ServiceManagement
import Foundation

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unsupportedLocation
    case unavailable
    case failed(String)
}

protocol LaunchAtLoginLocationChecking {
    var isSupported: Bool { get }
}

struct LaunchAtLoginLocationChecker: LaunchAtLoginLocationChecking {
    let bundleURL: URL
    let homeDirectory: URL

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.bundleURL = bundleURL
        self.homeDirectory = homeDirectory
    }

    var isSupported: Bool {
        let appURL = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard appURL.pathExtension == "app" else {
            return false
        }

        let parent = appURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return Self.supportedApplicationDirectories(homeDirectory: homeDirectory)
            .contains(parent.path)
    }

    private static func supportedApplicationDirectories(homeDirectory: URL) -> Set<String> {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ].reduce(into: Set<String>()) { paths, url in
            paths.insert(url.resolvingSymlinksInPath().standardizedFileURL.path)
        }
    }
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
            return .unsupportedLocation
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
