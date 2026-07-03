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
}
