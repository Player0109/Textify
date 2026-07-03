import Foundation

public struct DiagnosticsExportDocument: Equatable, Codable, Sendable {
    public let formatVersion: Int
    public let files: [DiagnosticsExportFile]

    public init(formatVersion: Int, files: [DiagnosticsExportFile]) {
        self.formatVersion = formatVersion
        self.files = files
    }
}

public struct DiagnosticsExportFile: Equatable, Codable, Sendable {
    public let filename: String
    public let contents: String

    public init(filename: String, contents: String) {
        self.filename = filename
        self.contents = contents
    }
}

public struct DiagnosticsExporter: Sendable {
    public init() {}

    public func export(events: [DiagnosticEvent]) throws -> [String: Any] {
        let encodedEvents = try events.map(Self.jsonObject)
        let document: [String: Any] = [
            "formatVersion": 1,
            "events": encodedEvents
        ]

        guard JSONSerialization.isValidJSONObject(document) else {
            throw DiagnosticsExporterError.invalidJSONObject
        }

        return document
    }

    public func exportRedactedLogs(
        from directory: URL,
        fileManager: FileManager = .default,
        redactor: DiagnosticsRedactor = DiagnosticsRedactor()
    ) throws -> DiagnosticsExportDocument {
        guard fileManager.fileExists(atPath: directory.path) else {
            return DiagnosticsExportDocument(formatVersion: 1, files: [])
        }

        let rootDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "jsonl" }
        .filter { $0.lastPathComponent.hasPrefix("diagnostics-") || $0.lastPathComponent.hasPrefix("log-") }
        .filter { try Self.isExportableRegularFile($0, rootDirectory: rootDirectory) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let files = try urls.map { url in
            let contents = try String(contentsOf: url, encoding: .utf8)
            return DiagnosticsExportFile(
                filename: url.lastPathComponent,
                contents: redactor.redactLogContents(contents)
            )
        }

        return DiagnosticsExportDocument(formatVersion: 1, files: files)
    }

    private static func isExportableRegularFile(_ url: URL, rootDirectory: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            return false
        }

        let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = rootDirectory.path.hasSuffix("/") ? rootDirectory.path : "\(rootDirectory.path)/"
        return resolvedPath.hasPrefix(rootPath)
    }

    private static func jsonObject(for event: DiagnosticEvent) throws -> [String: Any] {
        let data = try JSONEncoder().encode(event)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DiagnosticsExporterError.invalidEventObject
        }
        return object
    }
}

public enum DiagnosticsExporterError: Error, Equatable {
    case invalidEventObject
    case invalidJSONObject
}
