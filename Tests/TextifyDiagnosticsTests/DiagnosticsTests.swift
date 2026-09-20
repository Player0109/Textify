import TextifyDiagnostics
import XCTest

final class DiagnosticsTests: XCTestCase {
    func testCatalogRejectionEventIsClosedHighSeverityMetadata() throws {
        let event = DiagnosticEvent.catalogUpdateRejected(
            severity: "high",
            reasonCode: "invalid_signature",
            candidateRevision: "not-a-catalog-revision",
            acceptedRevision: "2026-07-24T00:00:00Z"
        )

        let (object, json) = try encodedJSONObject(for: event)

        XCTAssertEqual(object["event"] as? String, "catalog_update_rejected")
        XCTAssertEqual(object["severity"] as? String, "high")
        XCTAssertEqual(object["reasonCode"] as? String, "invalid_signature")
        XCTAssertEqual(object["candidateRevision"] as? String, "unknown")
        XCTAssertEqual(
            object["acceptedRevision"] as? String,
            "2026-07-24T00:00:00Z"
        )
        XCTAssertFalse(json.localizedCaseInsensitiveContains("message"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("content"))
    }

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
            textLengthBucket: "1-50",
            windowCount: 3,
            terminationReason: "trigger_released"
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
        XCTAssertEqual(object["windowCount"] as? Int, 3)
        XCTAssertEqual(object["terminationReason"] as? String, "trigger_released")
    }

    func testTranscriptionCompletedClampsWindowCountAndClosesTerminationReason() throws {
        let event = DiagnosticEvent.transcriptionCompleted(
            modelID: "ggml-small.en-q5_1",
            engine: "whisper_cpp",
            accelerator: "metal_gpu",
            backendReadiness: "ready",
            audioDurationMs: 5_000,
            inferenceDurationMs: 1_500,
            textLengthBucket: "1-50",
            windowCount: -2,
            terminationReason: "released after transcript=private dictation"
        )

        let (object, json) = try encodedJSONObject(for: event)

        XCTAssertEqual(object["event"] as? String, "speech_recognition_completed")
        XCTAssertEqual(object["windowCount"] as? Int, 0)
        XCTAssertEqual(object["terminationReason"] as? String, "unknown")
        XCTAssertFalse(json.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("private dictation"))
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

    func testDictationCaptureTimingEncodesOnlyAggregateTechnicalMetrics() throws {
        let event = DiagnosticEvent.dictationCaptureTiming(
            triggerToCaptureRequestMs: 251,
            triggerToCaptureStartMs: 263,
            triggerToFirstAudioMs: 279,
            triggerHoldDurationMs: 842,
            shortcutGuardSpeechDetected: true,
            preASROutcome: "submitted_to_asr"
        )

        let (object, json) = try encodedJSONObject(for: event)

        XCTAssertEqual(object["event"] as? String, "dictation_capture_timing")
        XCTAssertEqual(object["triggerToCaptureRequestMs"] as? Int, 251)
        XCTAssertEqual(object["triggerToCaptureStartMs"] as? Int, 263)
        XCTAssertEqual(object["triggerToFirstAudioMs"] as? Int, 279)
        XCTAssertEqual(object["triggerHoldDurationMs"] as? Int, 842)
        XCTAssertEqual(object["shortcutGuardSpeechDetected"] as? Bool, true)
        XCTAssertEqual(object["preASROutcome"] as? String, "submitted_to_asr")
        XCTAssertEqual(object.count, 7)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("bundleIdentifier"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("microphone"))
    }

    func testDictationCaptureTimingOmitsMissingMetricsAndClampsNegativeDurations() throws {
        let event = DiagnosticEvent.dictationCaptureTiming(
            triggerToCaptureRequestMs: nil,
            triggerToCaptureStartMs: -2,
            triggerToFirstAudioMs: nil,
            triggerHoldDurationMs: -1,
            shortcutGuardSpeechDetected: false,
            preASROutcome: "capture_start_failed"
        )

        let (object, _) = try encodedJSONObject(for: event)

        XCTAssertNil(object["triggerToCaptureRequestMs"])
        XCTAssertEqual(object["triggerToCaptureStartMs"] as? Int, 0)
        XCTAssertNil(object["triggerToFirstAudioMs"])
        XCTAssertEqual(object["triggerHoldDurationMs"] as? Int, 0)
    }

    func testDictationCaptureTimingUsesClosedPreASROutcomes() throws {
        let allowedOutcomes = [
            "accidental_tap_discarded",
            "capture_start_failed",
            "empty_capture_discarded",
            "escape_discarded",
            "recording_error",
            "shortcut_discarded",
            "submitted_to_asr"
        ]

        for outcome in allowedOutcomes {
            let event = DiagnosticEvent.dictationCaptureTiming(
                triggerToCaptureRequestMs: nil,
                triggerToCaptureStartMs: nil,
                triggerToFirstAudioMs: nil,
                triggerHoldDurationMs: nil,
                shortcutGuardSpeechDetected: false,
                preASROutcome: outcome
            )
            let (object, _) = try encodedJSONObject(for: event)
            XCTAssertEqual(object["preASROutcome"] as? String, outcome)
        }

        let unknownEvent = DiagnosticEvent.dictationCaptureTiming(
            triggerToCaptureRequestMs: nil,
            triggerToCaptureStartMs: nil,
            triggerToFirstAudioMs: nil,
            triggerHoldDurationMs: nil,
            shortcutGuardSpeechDetected: false,
            preASROutcome: "failed while recording private dictation"
        )
        let (unknownObject, unknownJSON) = try encodedJSONObject(for: unknownEvent)
        XCTAssertEqual(unknownObject["preASROutcome"] as? String, "unknown")
        XCTAssertFalse(unknownJSON.localizedCaseInsensitiveContains("private dictation"))
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

    func testRedactorNormalizesStringsInjectedIntoMetricKeys() throws {
        let line = #"""
        {"event":"dictation_capture_timing","durationMs":"ordinary free-form value","triggerToCaptureRequestMs":"private timing details","triggerToCaptureStartMs":"12","triggerToFirstAudioMs":"transcript=secret","triggerHoldDurationMs":"842","shortcutGuardSpeechDetected":"true","preASROutcome":"submitted_to_asr"}
        """#

        let redacted = try XCTUnwrap(DiagnosticsRedactor().redactJSONLine(line))
        let data = try XCTUnwrap(redacted.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        for key in [
            "durationMs",
            "triggerToCaptureRequestMs",
            "triggerToCaptureStartMs",
            "triggerToFirstAudioMs",
            "triggerHoldDurationMs",
            "shortcutGuardSpeechDetected"
        ] {
            XCTAssertEqual(object[key] as? String, "unknown")
        }
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("free-form"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("private timing"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("transcript"))
    }

    func testRedactorRejectsStructuredOrMismatchedMetricValues() throws {
        let line = #"""
        {"event":"dictation_capture_timing","triggerToCaptureRequestMs":[12,13],"triggerToCaptureStartMs":{"value":14},"triggerToFirstAudioMs":true,"triggerHoldDurationMs":842,"shortcutGuardSpeechDetected":1,"preASROutcome":"submitted_to_asr"}
        """#

        let redacted = try XCTUnwrap(
            DiagnosticsRedactor().redactJSONLine(line)
        )
        let data = try XCTUnwrap(redacted.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["triggerToCaptureRequestMs"] as? String, "unknown")
        XCTAssertEqual(object["triggerToCaptureStartMs"] as? String, "unknown")
        XCTAssertEqual(object["triggerToFirstAudioMs"] as? String, "unknown")
        XCTAssertEqual(object["triggerHoldDurationMs"] as? Int, 842)
        XCTAssertEqual(object["shortcutGuardSpeechDetected"] as? String, "unknown")
    }

    func testRedactorPreservesAggregateSessionFieldsAndRemovesInjectedContent() throws {
        let line = #"""
        {"event":"speech_recognition_completed","modelID":"ggml-small.en-q5_1","engine":"whisper_cpp","accelerator":"metal_gpu","backendReadiness":"ready","audioDurationMs":65000,"inferenceDurationMs":3500,"textLengthBucket":"51-200","windowCount":3,"terminationReason":"session_limit_reached","text":"secret transcript","content":"private dictation"}
        """#

        let redacted = try XCTUnwrap(DiagnosticsRedactor().redactJSONLine(line))
        let data = try XCTUnwrap(redacted.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["windowCount"] as? Int, 3)
        XCTAssertEqual(object["terminationReason"] as? String, "session_limit_reached")
        XCTAssertNil(object["text"])
        XCTAssertNil(object["content"])
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("secret transcript"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("private dictation"))
    }

    func testRedactorRejectsFreeFormAggregateSessionFields() throws {
        let line = #"""
        {"event":"speech_recognition_completed","windowCount":"three windows containing transcript=secret","terminationReason":"stopped while dictating private content"}
        """#

        let redacted = try XCTUnwrap(DiagnosticsRedactor().redactJSONLine(line))
        let data = try XCTUnwrap(redacted.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["windowCount"] as? String, "unknown")
        XCTAssertEqual(object["terminationReason"] as? String, "unknown")
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(redacted.localizedCaseInsensitiveContains("private content"))
    }

    func testExporterPreservesCaptureMetricsAndRemovesInjectedIdentityAndContent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            "diagnostics-capture.jsonl",
            contents: #"{"event":"dictation_capture_timing","triggerToCaptureRequestMs":251,"triggerToCaptureStartMs":263,"triggerToFirstAudioMs":279,"triggerHoldDurationMs":842,"shortcutGuardSpeechDetected":true,"preASROutcome":"submitted_to_asr","bundleIdentifier":"com.example.Target","text":"secret transcript"}"# + "\n",
            in: directory
        )

        let document = try DiagnosticsExporter().exportRedactedLogs(from: directory)
        let contents = try XCTUnwrap(document.files.first?.contents)
        let line = try XCTUnwrap(contents.split(separator: "\n").first)
        let data = try XCTUnwrap(String(line).data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["triggerToCaptureRequestMs"] as? Int, 251)
        XCTAssertEqual(object["triggerToCaptureStartMs"] as? Int, 263)
        XCTAssertEqual(object["triggerToFirstAudioMs"] as? Int, 279)
        XCTAssertEqual(object["triggerHoldDurationMs"] as? Int, 842)
        XCTAssertEqual(object["shortcutGuardSpeechDetected"] as? Bool, true)
        XCTAssertEqual(object["preASROutcome"] as? String, "submitted_to_asr")
        XCTAssertNil(object["bundleIdentifier"])
        XCTAssertNil(object["text"])
        XCTAssertFalse(contents.contains("com.example.Target"))
        XCTAssertFalse(contents.localizedCaseInsensitiveContains("secret transcript"))
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
