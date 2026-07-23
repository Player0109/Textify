import Foundation

public struct DiagnosticsLogEntry: Equatable, Identifiable, Sendable {
    public let id: String
    public let timestamp: String?
    public let event: String
    public let modelID: String?
    public let stage: String?
    public let reasonCode: String?
    public let json: String

    public init(
        id: String,
        timestamp: String?,
        event: String,
        modelID: String?,
        stage: String?,
        reasonCode: String?,
        json: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.event = event
        self.modelID = modelID
        self.stage = stage
        self.reasonCode = reasonCode
        self.json = json
    }
}

public struct DiagnosticsLogReader: Sendable {
    public init() {}

    public func recentEntries(
        from directory: URL,
        limit: Int = 200,
        fileManager: FileManager = .default,
        redactor: DiagnosticsRedactor = DiagnosticsRedactor()
    ) throws -> [DiagnosticsLogEntry] {
        guard limit > 0 else {
            return []
        }

        let document = try DiagnosticsExporter().exportRedactedLogs(
            from: directory,
            fileManager: fileManager,
            redactor: redactor
        )
        let entries = document.files.flatMap { file in
            file.contents
                .split(separator: "\n")
                .enumerated()
                .compactMap { index, line in
                    Self.entry(
                        json: String(line),
                        filename: file.filename,
                        lineNumber: index + 1
                    )
                }
        }
        return Array(entries.suffix(limit).reversed())
    }

    private static func entry(
        json: String,
        filename: String,
        lineNumber: Int
    ) -> DiagnosticsLogEntry? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String
        else {
            return nil
        }

        return DiagnosticsLogEntry(
            id: "\(filename):\(lineNumber)",
            timestamp: object["timestamp"] as? String,
            event: event,
            modelID: object["modelID"] as? String,
            stage: object["stage"] as? String,
            reasonCode: object["reasonCode"] as? String,
            json: json
        )
    }
}
