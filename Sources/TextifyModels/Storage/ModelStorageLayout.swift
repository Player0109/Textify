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

    public func installedArtifactURL(modelID: String, relativePath: String) throws -> URL {
        let safePath = try Self.validateRelativePath(relativePath)
        let modelDirectory = try installedModelDirectory(modelID: modelID)
        return try containedURL(
            modelDirectory.appendingPathComponent(safePath, isDirectory: false),
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

    public func downloadResumeMetadataURL(modelID: String, filename: String) throws -> URL {
        let temporaryURL = try temporaryDownloadURL(modelID: modelID, filename: filename)
        return try containedURL(
            temporaryURL.appendingPathExtension("resume.json"),
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

    func temporaryInstallationDirectory(modelID: String) throws -> URL {
        let safeModelID = try Self.validatePathComponent(modelID)
        return try containedURL(
            downloadsDirectory.appendingPathComponent(
                ".\(safeModelID).installing-\(UUID().uuidString)",
                isDirectory: true
            ),
            in: downloadsDirectory
        )
    }

    func temporaryRemovalDirectory(modelID: String) throws -> URL {
        let safeModelID = try Self.validatePathComponent(modelID)
        return try containedURL(
            downloadsDirectory.appendingPathComponent(
                ".\(safeModelID).removing-\(UUID().uuidString)",
                isDirectory: true
            ),
            in: downloadsDirectory
        )
    }

    func artifactURL(in directory: URL, relativePath: String) throws -> URL {
        let safePath = try Self.validateRelativePath(relativePath)
        return try containedURL(
            directory.appendingPathComponent(safePath, isDirectory: false),
            in: directory
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

    private static func validateRelativePath(_ value: String) throws -> String {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\\")
        else {
            throw ModelStorageLayoutError.unsafePathComponent(value)
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else {
            throw ModelStorageLayoutError.unsafePathComponent(value)
        }
        for component in components {
            _ = try validatePathComponent(String(component))
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
