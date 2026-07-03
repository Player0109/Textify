import Foundation

struct AppPaths: Equatable {
    let applicationSupportDirectory: URL
    let settingsFileURL: URL
    let modelsDirectory: URL
    let logsDirectory: URL

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
        let modelsDirectory = applicationSupportDirectory
            .appendingPathComponent("Models", isDirectory: true)
        let logsDirectory = libraryDirectory
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Textify", isDirectory: true)

        try fileManager.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )

        return AppPaths(
            applicationSupportDirectory: applicationSupportDirectory,
            settingsFileURL: applicationSupportDirectory.appendingPathComponent("settings.json"),
            modelsDirectory: modelsDirectory,
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
            applicationSupportDirectory: applicationSupportDirectory,
            settingsFileURL: applicationSupportDirectory.appendingPathComponent("settings.json"),
            modelsDirectory: applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true),
            logsDirectory: root
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("Textify", isDirectory: true)
        )
    }
}
