import Foundation
import TextifyModels

struct AppPaths: Equatable {
    let rollbackStateLayout: ModelV3RollbackStateLayout
    let logsDirectory: URL

    var applicationSupportDirectory: URL {
        rollbackStateLayout.applicationSupportDirectory
    }
    var settingsFileURL: URL {
        rollbackStateLayout.settingsFileURL
    }
    var modelsDirectory: URL {
        rollbackStateLayout.modelStorageLayout.rootDirectory
    }
    var manifestCacheDirectory: URL {
        rollbackStateLayout.manifestCacheDirectory
    }

    static func production(fileManager: FileManager = .default) throws -> AppPaths {
        let applicationSupportBase = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let libraryDirectory = try fileManager.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try make(
            applicationSupportBase: applicationSupportBase,
            libraryDirectory: libraryDirectory,
            fileManager: fileManager
        )
    }

    static func make(
        applicationSupportBase: URL,
        libraryDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> AppPaths {
        let applicationSupportDirectory = applicationSupportBase
            .appendingPathComponent("Textify", isDirectory: true)
        let rollbackStateLayout = ModelV3RollbackStateLayout(
            applicationSupportDirectory: applicationSupportDirectory
        )
        let logsDirectory = libraryDirectory
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Textify", isDirectory: true)

        try fileManager.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: rollbackStateLayout.modelStorageLayout.rootDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: rollbackStateLayout.manifestCacheDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )

        return AppPaths(
            rollbackStateLayout: rollbackStateLayout,
            logsDirectory: logsDirectory
        )
    }

    static func temporaryFallback(fileManager: FileManager = .default) -> AppPaths {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("TextifyStartupFallback", isDirectory: true)
        if let paths = try? make(
            applicationSupportBase: root.appendingPathComponent("Application Support", isDirectory: true),
            libraryDirectory: root.appendingPathComponent("Library", isDirectory: true),
            fileManager: fileManager
        ) {
            return paths
        }

        let applicationSupportDirectory = root
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Textify", isDirectory: true)
        return AppPaths(
            rollbackStateLayout: ModelV3RollbackStateLayout(
                applicationSupportDirectory: applicationSupportDirectory
            ),
            logsDirectory: root
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("Textify", isDirectory: true)
        )
    }
}
