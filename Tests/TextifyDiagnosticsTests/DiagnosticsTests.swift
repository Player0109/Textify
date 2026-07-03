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
        let logger = DiagnosticsLogger(directory: directory)

        try await logger.log(.appStarted(appVersion: "1.0.0", macOSVersion: "14.0"))
        try await logger.log(.modelLoad(modelID: "whisper-base-en-fast", tier: "fast", durationMs: 42, result: "ready"))

        let contents = try String(contentsOf: logger.logFileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.first == "{" && $0.last == "}" })
    }
}
