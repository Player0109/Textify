import Foundation

public struct ModelStorageLayout: Equatable, Sendable {
    public let rootDirectory: URL
    public var manifestsDirectory: URL { rootDirectory.appendingPathComponent("manifests", isDirectory: true) }
    public var downloadsDirectory: URL { rootDirectory.appendingPathComponent("downloads", isDirectory: true) }
    public var installedModelsDirectory: URL { rootDirectory.appendingPathComponent("installed", isDirectory: true) }
    public var installedStoreURL: URL { rootDirectory.appendingPathComponent("installed-models.json", isDirectory: false) }

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func installedModelDirectory(modelID: String) -> URL {
        installedModelsDirectory.appendingPathComponent(modelID, isDirectory: true)
    }

    public func installedFileURL(modelID: String, filename: String) -> URL {
        installedModelDirectory(modelID: modelID).appendingPathComponent(filename, isDirectory: false)
    }

    public func temporaryDownloadURL(modelID: String, filename: String) -> URL {
        downloadsDirectory.appendingPathComponent("\(modelID)-\(filename).partial", isDirectory: false)
    }
}
