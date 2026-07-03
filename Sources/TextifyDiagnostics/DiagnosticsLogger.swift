import Foundation

public actor DiagnosticsLogger {
    public nonisolated let directory: URL
    public nonisolated let logFileURL: URL

    private let encoder: JSONEncoder
    private let fileManager: FileManager

    public init(directory: URL, date: Date = Date(), fileManager: FileManager = .default) {
        self.directory = directory
        self.logFileURL = directory.appendingPathComponent(Self.logFileName(for: date), isDirectory: false)
        self.encoder = JSONEncoder()
        self.fileManager = fileManager
    }

    public func log(_ event: DiagnosticEvent) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: logFileURL.path) {
            _ = fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }

        var data = try encoder.encode(event)
        data.append(0x0A)

        let handle = try FileHandle(forWritingTo: logFileURL)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        handle.write(data)
    }

    private static func logFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "log-\(formatter.string(from: date)).jsonl"
    }
}
