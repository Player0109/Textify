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

    public func rotate(policy: DiagnosticsRetentionPolicy = .v1_1Default, now: Date = Date()) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try diagnosticLogFiles()
        let cutoff = Calendar.current.date(byAdding: .day, value: -policy.maxAgeDays, to: now) ?? now

        for file in files where file.modifiedAt < cutoff {
            try? fileManager.removeItem(at: file.url)
        }

        let remaining = try diagnosticLogFiles().sorted { $0.modifiedAt > $1.modifiedAt }
        for file in remaining.dropFirst(policy.maxFileCount) {
            try? fileManager.removeItem(at: file.url)
        }

        var totalBytes = try diagnosticLogFiles().reduce(Int64(0)) { $0 + $1.sizeBytes }
        for file in try diagnosticLogFiles().sorted(by: { $0.modifiedAt < $1.modifiedAt }) where totalBytes > policy.maxTotalBytes {
            try? fileManager.removeItem(at: file.url)
            totalBytes -= file.sizeBytes
        }
    }

    public func clear() throws {
        for file in try diagnosticLogFiles() {
            try? fileManager.removeItem(at: file.url)
        }
    }

    private static func logFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "log-\(formatter.string(from: date)).jsonl"
    }

    private func diagnosticLogFiles() throws -> [DiagnosticLogFile] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix("diagnostics-") || $0.lastPathComponent.hasPrefix("log-") }
        .filter { $0.pathExtension == "jsonl" }
        .map { url in
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return DiagnosticLogFile(
                url: url,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                sizeBytes: Int64(values.fileSize ?? 0)
            )
        }
    }
}

private struct DiagnosticLogFile {
    let url: URL
    let modifiedAt: Date
    let sizeBytes: Int64
}
