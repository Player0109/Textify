import TextifyDiagnostics
import XCTest

final class DiagnosticsTests: XCTestCase {
    func testVoiceCleaningEventContainsOnlyTechnicalMetadata() throws {
        let event = DiagnosticEvent.voiceCleaning(
            modelID: "mossformer2-se-fp16",
            durationMs: 42,
            result: "raw_audio_fallback"
        )

        let data = try JSONEncoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("voice_cleaning"))
        XCTAssertFalse(json.contains("samples"))
        XCTAssertFalse(json.contains("transcript"))
        XCTAssertFalse(json.contains("audioData"))
    }
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
            engine: "whisper_cpp",
            accelerator: "metal_gpu",
            backendReadiness: "ready",
            audioDurationMs: 5_000,
            inferenceDurationMs: 1_500,
            textLengthBucket: "1-50"
        )
        let data = try JSONEncoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertFalse(json.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("clipboard"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("audioSamples"))
        XCTAssertEqual(object["engine"] as? String, "whisper_cpp")
        XCTAssertEqual(object["accelerator"] as? String, "metal_gpu")
        XCTAssertEqual(object["backendReadiness"] as? String, "ready")
    }

    func testRuntimeFailurePreservesClosedQwenFailureMetadata() throws {
        let event = DiagnosticEvent.runtimeFailure(
            modelID: "qwen3-asr-1.7b-bf16",
            engine: "transcribe_cpp",
            accelerator: "metal_gpu",
            stage: "model_prepare",
            reasonCode: "automatic_language_detection_required"
        )

        let (object, json) = try encodedJSONObject(for: event)

        XCTAssertEqual(object["event"] as? String, "runtime_failure")
        XCTAssertEqual(object["modelID"] as? String, "qwen3-asr-1.7b-bf16")
        XCTAssertEqual(object["engine"] as? String, "transcribe_cpp")
        XCTAssertEqual(object["stage"] as? String, "model_prepare")
        XCTAssertEqual(
            object["reasonCode"] as? String,
            "automatic_language_detection_required"
        )
        XCTAssertFalse(json.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("message"))
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
        try await logger.log(
            .modelLoad(
                modelID: "whisper-base-en-fast",
                tier: "fast",
                engine: "whisper_cpp",
                accelerator: "metal_gpu",
                durationMs: 42,
                result: "ready"
            )
        )

        let contents = try String(contentsOf: logger.logFileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.first == "{" && $0.last == "}" })
    }

    func testLoggerAddsATimestampWithoutChangingTheClosedEventPayload() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let timestamp = Date(timeIntervalSince1970: 1_787_478_400)
        let logger = DiagnosticsLogger(
            directory: directory,
            date: timestamp,
            now: { timestamp }
        )

        try await logger.log(.dictationBlockedExcludedApp)

        let contents = try String(contentsOf: logger.logFileURL, encoding: .utf8)
        let line = try XCTUnwrap(contents.split(separator: "\n").first)
        let data = try XCTUnwrap(String(line).data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["event"] as? String, "dictation_blocked_excluded_app")
        XCTAssertNotNil(object["timestamp"] as? String)
        XCTAssertEqual(object.count, 2)
    }

    func testRecentLogReaderReturnsNewestRedactedEntries() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            "log-2026-07-22.jsonl",
            contents: #"{"event":"model_load","modelID":"ggml-small.en-q5_1","result":"ready","message":"secret"}"# + "\n",
            in: directory
        )
        try writeFile(
            "log-2026-07-23.jsonl",
            contents: [
                #"{"event":"runtime_failure","modelID":"qwen3-asr-1.7b-bf16","engine":"transcribe_cpp","accelerator":"metal_gpu","stage":"model_prepare","reasonCode":"automatic_language_detection_required","timestamp":"2026-07-23T08:48:00.000Z","text":"secret"}"#,
                #"{"event":"app_started","appVersion":"1.1.0","timestamp":"2026-07-23T08:49:00.000Z"}"#
            ].joined(separator: "\n") + "\n",
            in: directory
        )

        let entries = try DiagnosticsLogReader().recentEntries(
            from: directory,
            limit: 2
        )

        XCTAssertEqual(entries.map(\.event), ["app_started", "runtime_failure"])
        XCTAssertEqual(entries[1].modelID, "qwen3-asr-1.7b-bf16")
        XCTAssertEqual(entries[1].reasonCode, "automatic_language_detection_required")
        XCTAssertFalse(entries.map(\.json).joined().contains("secret"))
        XCTAssertFalse(entries.map(\.json).joined().contains(#""text""#))
    }

    func testLoggerRollsDailyAndAppliesRetentionWithoutRestart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MutableDiagnosticsClock(date: Date())
        let logger = DiagnosticsLogger(
            directory: directory,
            date: clock.date,
            now: { clock.date }
        )

        try await logger.log(.appStarted(appVersion: "1.0.0", macOSVersion: "14.0"))
        let firstLogURL = logger.logFileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstLogURL.path))

        clock.advance(days: 15)
        try await logger.log(.appStarted(appVersion: "1.0.0", macOSVersion: "14.0"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstLogURL.path))
        let remainingLogs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "jsonl" }
        XCTAssertEqual(remainingLogs.count, 1)
        XCTAssertNotEqual(remainingLogs.first, firstLogURL)
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

    func testLoggerClearThrowsWhenDiagnosticDeletionFails() async throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let logger = DiagnosticsLogger(
            directory: directory,
            fileDeleter: AlwaysFailingDiagnosticsFileDeleter()
        )
        try await logger.log(.appStarted(appVersion: "1.0.0", macOSVersion: "14.0"))

        do {
            try await logger.clear()
            XCTFail("Expected clear to throw when deleting a diagnostic file fails.")
        } catch let error as DiagnosticsLoggerError {
            XCTAssertEqual(error.failedURLs.map(\.lastPathComponent), [logger.logFileURL.lastPathComponent])
        }
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

    func testRedactorRedactsForbiddenContentInsideAllowedStringValues() throws {
        let line = #"""
        {"event":"app_started","fallbackBlockedReason":"transcript=hello clipboard=copy TEXTIFY_FORBIDDEN_MARKER","result":"raw error from com.example.TargetApp","appVersion":"1.0.0"}
        """#

        let redacted = try XCTUnwrap(DiagnosticsRedactor().redactJSONLine(line))

        XCTAssertTrue(redacted.contains("app_started"))
        XCTAssertTrue(redacted.contains("1.0.0"))
        XCTAssertTrue(redacted.contains(#""fallbackBlockedReason":"unknown""#))
        XCTAssertTrue(redacted.contains(#""result":"unknown""#))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("clipboard"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("TEXTIFY_FORBIDDEN_MARKER"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("raw error"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("com.example.TargetApp"))
    }

    func testDiagnosticEventSanitizesUnsafeAllowedStringValues() throws {
        let event = DiagnosticEvent.modelLoad(
            modelID: "ggml-small.en-q5_1",
            tier: "fast",
            engine: "whisper_cpp",
            accelerator: "metal_gpu",
            durationMs: 42,
            result: "raw error transcript=hello"
        )

        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)

        XCTAssertTrue(json.contains(#""result":"unknown""#))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("raw error"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("transcript"))
    }

    func testDiagnosticEventsNormalizeSensitiveModelIDAndErrorDomainValues() throws {
        let sensitiveValues: [(value: String, leakedFragments: [String])] = [
            (
                "/Users/alice/Library/Application Support/Textify/model.bin",
                ["/Users/alice", "Library/Application Support", "model.bin"]
            ),
            (
                "~/Library/Application Support/Textify/model.bin",
                ["~/Library", "Library/Application Support", "model.bin"]
            ),
            (
                "/Applications/Foo.app",
                ["/Applications/Foo.app", "Foo.app"]
            ),
            (
                "Preview",
                ["Preview"]
            ),
            (
                "whisper_init_from_file_with_params_no_state: failed to open /Users/alice/model.bin",
                ["whisper_init_from_file", "failed to open", "/Users/alice", "model.bin"]
            )
        ]

        for testCase in sensitiveValues {
            let modelLoad = DiagnosticEvent.modelLoad(
                modelID: testCase.value,
                tier: "fast",
                engine: "whisper_cpp",
                accelerator: "metal_gpu",
                durationMs: 42,
                result: "ready"
            )
            let (modelLoadObject, modelLoadJSON) = try encodedJSONObject(for: modelLoad)
            XCTAssertEqual(modelLoadObject["modelID"] as? String, "unknown")
            assertNoFragments(testCase.leakedFragments, in: modelLoadJSON)

            let launchAtLogin = DiagnosticEvent.launchAtLoginChange(
                requestedAction: "enable",
                statusBefore: "notRegistered",
                statusAfter: "error",
                appLocationCategory: "applications",
                succeeded: false,
                errorDomain: testCase.value,
                errorCode: 1
            )
            let (launchObject, launchJSON) = try encodedJSONObject(for: launchAtLogin)
            XCTAssertEqual(launchObject["errorDomain"] as? String, "unknown")
            assertNoFragments(testCase.leakedFragments, in: launchJSON)
        }
    }

    func testDiagnosticEventsPreserveClosedModelIDAndErrorDomainValues() throws {
        let modelLoad = DiagnosticEvent.modelLoad(
            modelID: "ggml-small.en-q5_1",
            tier: "balanced",
            engine: "whisper_cpp",
            accelerator: "metal_gpu",
            durationMs: 42,
            result: "ready"
        )
        let (modelLoadObject, _) = try encodedJSONObject(for: modelLoad)
        XCTAssertEqual(modelLoadObject["modelID"] as? String, "ggml-small.en-q5_1")

        let launchAtLogin = DiagnosticEvent.launchAtLoginChange(
            requestedAction: "enable",
            statusBefore: "notRegistered",
            statusAfter: "requiresApproval",
            appLocationCategory: "applications",
            succeeded: false,
            errorDomain: "SMAppServiceErrorDomain",
            errorCode: 1
        )
        let (launchObject, _) = try encodedJSONObject(for: launchAtLogin)
        XCTAssertEqual(launchObject["errorDomain"] as? String, "SMAppServiceErrorDomain")
    }

    func testDiagnosticEventsNormalizeScaffoldModelIDs() throws {
        let scaffoldModelIDs = [
            "whisper-base-en-fast",
            "whisper-medium-en-accurate",
            "whisper-small-en-balanced"
        ]

        for modelID in scaffoldModelIDs {
            let modelLoad = DiagnosticEvent.modelLoad(
                modelID: modelID,
                tier: "balanced",
                engine: "whisper_cpp",
                accelerator: "metal_gpu",
                durationMs: 42,
                result: "ready"
            )
            let (object, json) = try encodedJSONObject(for: modelLoad)

            XCTAssertEqual(object["modelID"] as? String, "unknown")
            XCTAssertFalse(json.contains(modelID))
        }
    }

    func testExporterNormalizesSensitiveModelIDAndErrorDomainValues() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let sensitiveValues = [
            "/Users/alice/Library/Application Support/Textify/model.bin",
            "~/Library/Application Support/Textify/model.bin",
            "/Applications/Foo.app",
            "Preview",
            "whisper_init_from_file_with_params_no_state: failed to open /Users/alice/model.bin"
        ]
        let logContents = try sensitiveValues.map { value in
            try jsonLine([
                "event": "model_load",
                "modelID": value,
                "errorDomain": value,
                "tier": "fast",
                "durationMs": 42,
                "result": "ready"
            ])
        }
        .joined(separator: "\n") + "\n"
        try writeFile("diagnostics-sensitive.jsonl", contents: logContents, in: directory)

        let document = try DiagnosticsExporter().exportRedactedLogs(from: directory)

        let contents = try XCTUnwrap(document.files.first?.contents)
        let redactedLines = contents.split(separator: "\n").map(String.init)
        XCTAssertEqual(redactedLines.count, sensitiveValues.count)
        for line in redactedLines {
            let data = try XCTUnwrap(line.data(using: .utf8))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["modelID"] as? String, "unknown")
            XCTAssertEqual(object["errorDomain"] as? String, "unknown")
        }
        assertNoFragments([
            "/Users/alice",
            "~/Library",
            "Library/Application Support",
            "/Applications/Foo.app",
            "Foo.app",
            "Preview",
            "whisper_init_from_file",
            "failed to open",
            "model.bin"
        ], in: contents)
    }

    func testResultWithRawPathOrOrdinaryPhraseIsNormalized() throws {
        let event = DiagnosticEvent.modelLoad(
            modelID: "ggml-small.en-q5_1",
            tier: "fast",
            engine: "whisper_cpp",
            accelerator: "metal_gpu",
            durationMs: 42,
            result: "/Users/alice/Library/Application Support/Textify/model load failed"
        )

        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)

        XCTAssertTrue(json.contains(#""result":"unknown""#))
        XCTAssertFalse(json.contains("/Users/alice"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("Library/Application Support"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("model load failed"))
    }

    func testUnknownFallbackBlockedReasonIsNormalized() throws {
        let event = DiagnosticEvent.insertionAttempt(
            textLengthBucket: "1-50",
            pasteboardSnapshotSucceeded: true,
            pasteboardWriteSucceeded: true,
            pasteEventPosted: false,
            fallbackAttempted: false,
            fallbackBlockedReason: "target editor rejected paste because the note is locked",
            durationMs: 12
        )

        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)

        XCTAssertTrue(json.contains(#""fallbackBlockedReason":"unknown""#))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("target editor"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("note is locked"))
    }

    func testInsertionAttemptNormalizesUnexpectedTextLengthBucket() throws {
        let event = DiagnosticEvent.insertionAttempt(
            textLengthBucket: "approximately one paragraph",
            pasteboardSnapshotSucceeded: true,
            pasteboardWriteSucceeded: true,
            pasteEventPosted: true,
            fallbackAttempted: false,
            fallbackBlockedReason: nil,
            durationMs: 12
        )

        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)

        XCTAssertTrue(json.contains(#""textLengthBucket":"unknown""#))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("approximately one paragraph"))
    }

    func testRedactorNormalizesUnknownEnumLikeAllowedStringValues() throws {
        let line = #"""
        {"event":"model_load","result":"operation failed while opening /Users/alice/model.bin","fallbackBlockedReason":"target editor rejected paste because the note is locked","textLengthBucket":"approximately one paragraph","appVersion":"1.0.0"}
        """#

        let redacted = try XCTUnwrap(DiagnosticsRedactor().redactJSONLine(line))

        XCTAssertTrue(redacted.contains(#""result":"unknown""#))
        XCTAssertTrue(redacted.contains(#""fallbackBlockedReason":"unknown""#))
        XCTAssertTrue(redacted.contains(#""textLengthBucket":"unknown""#))
        XCTAssertFalse(redacted.contains("/Users/alice"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("target editor"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("approximately one paragraph"))
    }

    func testExporterSkipsSymlinkedAndNonRegularMatchingLogFiles() throws {
        let directory = try makeTemporaryDirectory()
        let outsideDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outsideDirectory)
        }
        try writeFile(
            "diagnostics-real.jsonl",
            contents: #"{"event":"app_started","appVersion":"1.0.0"}"# + "\n",
            in: directory
        )
        let matchingDirectory = directory.appendingPathComponent("log-directory.jsonl", isDirectory: true)
        try FileManager.default.createDirectory(at: matchingDirectory, withIntermediateDirectories: true)
        let outsideLog = try writeFile(
            "outside.jsonl",
            contents: #"{"event":"app_started","appVersion":"leak"}"# + "\n",
            in: outsideDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("diagnostics-symlink.jsonl"),
            withDestinationURL: outsideLog
        )

        let document = try DiagnosticsExporter().exportRedactedLogs(from: directory)

        XCTAssertEqual(document.files.map(\.filename), ["diagnostics-real.jsonl"])
        XCTAssertFalse(document.files.first?.contents.contains("leak") ?? true)
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

    private func encodedJSONObject(for event: DiagnosticEvent) throws -> ([String: Any], String) {
        let data = try JSONEncoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (object, json)
    }

    private func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func assertNoFragments(
        _ fragments: [String],
        in string: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for fragment in fragments {
            XCTAssertFalse(string.contains(fragment), "Leaked fragment: \(fragment)", file: file, line: line)
        }
    }
}

private final class MutableDiagnosticsClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(date: Date) {
        value = date
    }

    var date: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(days: Int) {
        lock.lock()
        value = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: days, to: value) ?? value
        lock.unlock()
    }
}

private struct AlwaysFailingDiagnosticsFileDeleter: DiagnosticsFileDeleting {
    func removeItem(at url: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
