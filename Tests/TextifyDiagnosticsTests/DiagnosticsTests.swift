import TextifyDiagnostics
import XCTest

final class DiagnosticsTests: XCTestCase {
    func testInsertionEventContainsNoContentFields() throws {
        let event = DiagnosticEvent.insertionAttempt(
            textLengthBucket: "201-500",
            pasteboardSnapshotSucceeded: true,
            pasteboardWriteSucceeded: true,
            pasteEventPosted: true,
            fallbackAttempted: false,
            fallbackBlockedReason: "paste_outcome_unobservable",
            durationMs: 123
        )

        let data = try JSONEncoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("transcript"))
        XCTAssertFalse(json.contains("clipboard"))
        XCTAssertFalse(json.contains("bundleIdentifier"))
        XCTAssertFalse(json.contains("text\":\""))
    }

    func testDiagnosticsEventDoesNotEncodeContentFields() throws {
        let event = DiagnosticEvent.transcriptionCompleted(
            modelID: "ggml-small.en-q5_1",
            audioDurationMs: 5_000,
            inferenceDurationMs: 1_500,
            textLengthBucket: "1-50"
        )
        let data = try JSONEncoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("clipboard"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("audioSamples"))
    }

    func testExportIsSingleJSONDocument() throws {
        let exporter = DiagnosticsExporter()
        let exported = try exporter.export(events: [.appStarted(appVersion: "1.0.0", macOSVersion: "14.0")])
        XCTAssertTrue(exported.keys.contains("events"))
        XCTAssertEqual(exported["formatVersion"] as? Int, 1)
    }

    func testExcludedAppBlockLogsOnlyEventName() throws {
        let data = try JSONEncoder().encode(DiagnosticEvent.dictationBlockedExcludedApp)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["event"] as? String, "dictation_blocked_excluded_app")
        XCTAssertEqual(object.count, 1)
    }

    func testLoggerWritesOneJSONEventPerLine() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let logger = DiagnosticsLogger(directory: directory)

        try await logger.log(.appStarted(appVersion: "1.0.0", macOSVersion: "14.0"))
        try await logger.log(.modelLoad(modelID: "whisper-base-en-fast", tier: "fast", durationMs: 42, result: "ready"))

        let contents = try String(contentsOf: logger.logFileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.first == "{" && $0.last == "}" })
    }

    func testLoggerClearRemovesDiagnosticLogFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let logger = DiagnosticsLogger(directory: directory)
        try await logger.log(.appStarted(appVersion: "1.0.0", macOSVersion: "14.0"))
        try writeFile("diagnostics-extra.jsonl", contents: "{}\n", in: directory)
        try writeFile("notes.txt", contents: "keep", in: directory)

        try await logger.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: logger.logFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("diagnostics-extra.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("notes.txt").path))
    }

    func testLoggerRotateAppliesRetentionPolicy() async throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let logger = DiagnosticsLogger(directory: directory)
        let now = Date(timeIntervalSince1970: 2_000_000)
        let recentA = try writeFile("log-recent-a.jsonl", contents: String(repeating: "a", count: 40), in: directory)
        let recentB = try writeFile("diagnostics-recent-b.jsonl", contents: String(repeating: "b", count: 40), in: directory)
        let recentC = try writeFile("log-recent-c.jsonl", contents: String(repeating: "c", count: 40), in: directory)
        let old = try writeFile("log-old.jsonl", contents: String(repeating: "d", count: 40), in: directory)
        try writeFile("other.jsonl", contents: "keep", in: directory)
        try setModifiedAt(now.addingTimeInterval(-100), for: recentA)
        try setModifiedAt(now.addingTimeInterval(-50), for: recentB)
        try setModifiedAt(now.addingTimeInterval(-10), for: recentC)
        try setModifiedAt(now.addingTimeInterval(-3 * 24 * 60 * 60), for: old)

        try await logger.rotate(
            policy: DiagnosticsRetentionPolicy(maxAgeDays: 1, maxFileCount: 2, maxTotalBytes: 70),
            now: now
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recentA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recentB.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentC.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("other.jsonl").path))
    }

    func testExporterExportsOnlyDiagnosticLogsAndRedactsUnsafeFields() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try writeFile(
            "diagnostics-2026-07-03.jsonl",
            contents: #"{"event":"app_started","message":"raw text","text":"secret","appVersion":"1.0.0"}"# + "\n",
            in: directory
        )
        try writeFile(
            "other.jsonl",
            contents: #"{"event":"app_started","text":"secret"}"# + "\n",
            in: directory
        )
        try writeFile("notes.txt", contents: "secret", in: directory)

        let document = try DiagnosticsExporter().exportRedactedLogs(from: directory)

        XCTAssertEqual(document.formatVersion, 1)
        XCTAssertEqual(document.files.map(\.filename), ["diagnostics-2026-07-03.jsonl"])
        let contents = try XCTUnwrap(document.files.first?.contents)
        XCTAssertTrue(contents.contains("app_started"))
        XCTAssertTrue(contents.contains("appVersion"))
        XCTAssertFalse(contents.localizedCaseInsensitiveContains("message"))
        XCTAssertFalse(contents.localizedCaseInsensitiveContains("raw text"))
        XCTAssertFalse(contents.localizedCaseInsensitiveContains("secret"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func writeFile(_ name: String, contents: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func setModifiedAt(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
