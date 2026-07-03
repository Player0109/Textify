import Foundation

public enum ModelStorageLayoutError: Error, Equatable {
    case unsafePathComponent(String)
    case resolvedPathEscapesLayout(String)
}

public struct ModelStorageLayout: Equatable, Sendable {
    public let rootDirectory: URL
    public var manifestsDirectory: URL { rootDirectory.appendingPathComponent("manifests", isDirectory: true) }
    public var downloadsDirectory: URL { rootDirectory.appendingPathComponent("downloads", isDirectory: true) }
    public var installedModelsDirectory: URL { rootDirectory.appendingPathComponent("installed", isDirectory: true) }
    public var installedStoreURL: URL { rootDirectory.appendingPathComponent("installed-models.json", isDirectory: false) }

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func installedModelDirectory(modelID: String) throws -> URL {
        let safeModelID = try Self.validatePathComponent(modelID)
        return try containedURL(
            installedModelsDirectory.appendingPathComponent(safeModelID, isDirectory: true),
            in: installedModelsDirectory
        )
    }

    public func installedFileURL(modelID: String, filename: String) throws -> URL {
        let safeFilename = try Self.validatePathComponent(filename)
        let modelDirectory = try installedModelDirectory(modelID: modelID)
        return try containedURL(
            modelDirectory.appendingPathComponent(safeFilename, isDirectory: false),
            in: modelDirectory
        )
    }

    public func temporaryDownloadURL(modelID: String, filename: String) throws -> URL {
        let safeModelID = try Self.validatePathComponent(modelID)
        let safeFilename = try Self.validatePathComponent(filename)
        return try containedURL(
            downloadsDirectory.appendingPathComponent("\(safeModelID)-\(safeFilename).partial", isDirectory: false),
            in: downloadsDirectory
        )
    }

    func replacementFileURL(modelID: String, filename: String) throws -> URL {
        let safeFilename = try Self.validatePathComponent(filename)
        let modelDirectory = try installedModelDirectory(modelID: modelID)
        return try containedURL(
            modelDirectory.appendingPathComponent(".\(safeFilename).installing-\(UUID().uuidString)", isDirectory: false),
            in: modelDirectory
        )
    }

    private static func validatePathComponent(_ value: String) throws -> String {
        guard !value.isEmpty,
              value != ".",
              value != "..",
              !value.contains(".."),
              !value.contains("/"),
              !value.contains("\\"),
              !value.contains(":"),
              value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
        else {
            throw ModelStorageLayoutError.unsafePathComponent(value)
        }
        return value
    }

    private func containedURL(_ url: URL, in parent: URL) throws -> URL {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        let parentPath = resolvedParent.path.hasSuffix("/")
            ? resolvedParent.path
            : resolvedParent.path + "/"
        guard resolvedURL.path == resolvedParent.path || resolvedURL.path.hasPrefix(parentPath) else {
            throw ModelStorageLayoutError.resolvedPathEscapesLayout(resolvedURL.path)
        }
        return resolvedURL
    }
}
