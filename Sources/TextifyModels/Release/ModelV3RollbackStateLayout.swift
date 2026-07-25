import Foundation

public struct ModelV3RollbackStateLayout: Equatable, Sendable {
    public let applicationSupportDirectory: URL

    public var settingsFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("settings.json")
    }

    public var modelStorageLayout: ModelStorageLayout {
        ModelStorageLayout(
            rootDirectory: applicationSupportDirectory.appendingPathComponent(
                "Models",
                isDirectory: true
            )
        )
    }

    public var manifestCacheDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(
            "ManifestCache",
            isDirectory: true
        )
    }

    public var catalogStateFileURL: URL {
        manifestCacheDirectory.appendingPathComponent("catalog-state.json")
    }

    public var revocationStateFileURL: URL {
        manifestCacheDirectory.appendingPathComponent(
            "revocation-state.json"
        )
    }

    public init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
    }
}
