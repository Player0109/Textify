import Foundation

public struct DiagnosticsRedactor: Sendable {
    private let allowedKeys: Set<String>

    public init(allowedKeys: Set<String> = DiagnosticsRedactor.defaultAllowedKeys) {
        self.allowedKeys = allowedKeys
    }

    public func redactLogContents(_ contents: String) -> String {
        contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                guard !line.isEmpty else {
                    return ""
                }
                return redactJSONLine(String(line))
            }
            .joined(separator: "\n")
    }

    public func redactJSONLine(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let redacted = redactJSONObject(object),
              JSONSerialization.isValidJSONObject(redacted),
              let encoded = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]) else {
            return nil
        }

        return String(decoding: encoded, as: UTF8.self)
    }

    private func redactJSONObject(_ object: Any) -> [String: Any]? {
        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        var redacted: [String: Any] = [:]
        for (key, value) in dictionary where allowedKeys.contains(key) {
            redacted[key] = redactJSONValue(value, forKey: key)
        }
        return redacted
    }

    private func redactJSONValue(_ value: Any, forKey key: String) -> Any {
        if Self.numericMetricKeys.contains(key) {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID()
            else {
                return "unknown"
            }
            return number
        }
        if Self.booleanMetricKeys.contains(key) {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID()
            else {
                return "unknown"
            }
            return number
        }
        switch value {
        case let string as String:
            return DiagnosticsStringSanitizer.sanitize(string, forKey: key)
        case let dictionary as [String: Any]:
            var redacted: [String: Any] = [:]
            for (key, nestedValue) in dictionary where allowedKeys.contains(key) {
                redacted[key] = redactJSONValue(nestedValue, forKey: key)
            }
            return redacted
        case let array as [Any]:
            return array.map { redactJSONValue($0, forKey: key) }
        default:
            return value
        }
    }

    public static let defaultAllowedKeys: Set<String> = [
        "appLocationCategory",
        "appVersion",
        "acceptedRevision",
        "audioDurationMs",
        "accelerator",
        "averageLogProbability",
        "compressionRatio",
        "candidateRevision",
        "durationMs",
        "engine",
        "errorCode",
        "errorDomain",
        "event",
        "fallbackAttempted",
        "fallbackBlockedReason",
        "fallbackChunks",
        "inferenceDurationMs",
        "macOSVersion",
        "manifestSource",
        "modelID",
        "backendReadiness",
        "noSpeechProbability",
        "pasteEventPosted",
        "pasteOutcomeObservable",
        "pasteboardSnapshotSucceeded",
        "pasteboardWriteSucceeded",
        "requestedAction",
        "reasonCode",
        "result",
        "secureFieldDetected",
        "severity",
        "stage",
        "statusAfter",
        "statusBefore",
        "succeeded",
        "shortcutGuardSpeechDetected",
        "targetChanged",
        "textLengthBucket",
        "timestamp",
        "tier",
        "terminationReason",
        "triggerHoldDurationMs",
        "triggerToCaptureRequestMs",
        "triggerToCaptureStartMs",
        "triggerToFirstAudioMs",
        "preASROutcome",
        "windowCount"
    ]

    private static let numericMetricKeys: Set<String> = [
        "audioDurationMs",
        "averageLogProbability",
        "compressionRatio",
        "durationMs",
        "errorCode",
        "fallbackChunks",
        "inferenceDurationMs",
        "noSpeechProbability",
        "triggerHoldDurationMs",
        "triggerToCaptureRequestMs",
        "triggerToCaptureStartMs",
        "triggerToFirstAudioMs",
        "windowCount",
    ]

    private static let booleanMetricKeys: Set<String> = [
        "fallbackAttempted",
        "pasteEventPosted",
        "pasteOutcomeObservable",
        "pasteboardSnapshotSucceeded",
        "pasteboardWriteSucceeded",
        "secureFieldDetected",
        "shortcutGuardSpeechDetected",
        "succeeded",
        "targetChanged",
    ]
}

enum DiagnosticsStringSanitizer {
    static let redactedValue = "[redacted]"

    private static let forbiddenFragments = [
        "audiosamples",
        "audio samples",
        "bundleidentifier",
        "clipboard",
        "content",
        "details",
        "dictated text",
        "message",
        "raw error",
        "textify_forbidden_marker",
        "transcript"
    ]

    static func sanitize(_ value: String, forKey key: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if key == "modelID" {
            return sanitizeModelID(normalized)
        }
        if key == "timestamp"
            || key == "acceptedRevision"
            || key == "candidateRevision" {
            return sanitizeTimestamp(normalized)
        }
        if metricKeys.contains(key) {
            return unknownValue
        }

        if let allowedValues = closedValueAllowlists[key] {
            return allowedValues.contains(normalized) ? normalized : unknownValue
        }

        let lowercased = normalized.lowercased()
        if forbiddenFragments.contains(where: { lowercased.contains($0) }) {
            return redactedValue
        }

        if shouldCheckForBundleIdentifierLikeToken(forKey: key),
           containsBundleIdentifierLikeToken(normalized) {
            return redactedValue
        }

        return normalized
    }

    private static func sanitizeModelID(_ value: String) -> String {
        let allowedPrefixes = [
            "canary-",
            "cohere-",
            "custom-whisper-",
            "distil-whisper-",
            "ggml-",
            "moonshine-",
            "mossformer2-",
            "nemotron-",
            "parakeet-",
            "paraformer-",
            "qwen-",
            "qwen3-",
            "reazonspeech-",
            "sensevoice-",
            "whisper-large-",
            "whisperkit-"
        ]
        guard allowedPrefixes.contains(where: value.hasPrefix),
              value.count <= 128,
              value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
        else {
            return unknownValue
        }
        return value
    }

    private static func sanitizeTimestamp(_ value: String) -> String {
        guard value.count <= 32,
              value.range(
                  of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$"#,
                  options: .regularExpression
              ) != nil
        else {
            return unknownValue
        }
        return value
    }

    private static let unknownValue = "unknown"

    private static let metricKeys: Set<String> = [
        "audioDurationMs",
        "averageLogProbability",
        "compressionRatio",
        "durationMs",
        "errorCode",
        "fallbackAttempted",
        "fallbackChunks",
        "inferenceDurationMs",
        "noSpeechProbability",
        "pasteEventPosted",
        "pasteOutcomeObservable",
        "pasteboardSnapshotSucceeded",
        "pasteboardWriteSucceeded",
        "secureFieldDetected",
        "shortcutGuardSpeechDetected",
        "succeeded",
        "targetChanged",
        "triggerHoldDurationMs",
        "triggerToCaptureRequestMs",
        "triggerToCaptureStartMs",
        "triggerToFirstAudioMs",
        "windowCount"
    ]

    private static let closedValueAllowlists: [String: Set<String>] = [
        "appLocationCategory": [
            "applications",
            "not_found",
            "unsupported",
            "user_applications",
            unknownValue
        ],
        "accelerator": [
            "coreml_neural_engine",
            "cpu",
            "metal_gpu",
            unknownValue
        ],
        "backendReadiness": [
            "failed",
            "ready",
            unknownValue
        ],
        "engine": [
            "fluid_audio_parakeet",
            "fluid_audio_paraformer",
            "litert_lm",
            "mlx_audio",
            "sherpa_onnx",
            "transcribe_cpp",
            "whisper_cpp",
            unknownValue
        ],
        "event": [
            "app_started",
            "catalog_update_rejected",
            "dictation_blocked_excluded_app",
            "dictation_capture_timing",
            "insertion_attempt",
            "launch_at_login_change",
            "model_load",
            "runtime_failure",
            "speech_recognition_completed",
            "speech_recognition_discarded",
            "voice_cleaning",
            unknownValue
        ],
        "errorDomain": [
            "NSCocoaErrorDomain",
            "NSOSStatusErrorDomain",
            "NSPOSIXErrorDomain",
            "SMAppServiceErrorDomain",
            unknownValue
        ],
        "fallbackBlockedReason": [
            "control_characters_present",
            "empty_text",
            "paste_outcome_unobservable",
            "secure_field_detected",
            "target_changed",
            "text_too_long",
            unknownValue
        ],
        "manifestSource": [
            "bundled",
            "cached",
            "remote",
            unknownValue
        ],
        "preASROutcome": [
            "accidental_tap_discarded",
            "capture_start_failed",
            "empty_capture_discarded",
            "escape_discarded",
            "recording_error",
            "shortcut_discarded",
            "submitted_to_asr",
            unknownValue
        ],
        "requestedAction": [
            "disable",
            "enable",
            unknownValue
        ],
        "reasonCode": [
            "audio_too_long",
            "automatic_language_detection_required",
            "automatic_language_detection_unsupported",
            "bundled_catalog_invalid",
            "cache_corruption",
            "empty_audio",
            "incompatible_runtime_configuration",
            "inference_failed",
            "invalid_signature",
            "invalid_audio_format",
            "missing_model",
            "missing_runtime",
            "model_load_failed",
            "model_warmup_failed",
            "rollback",
            "runtime_not_loaded",
            "runtime_unavailable",
            "schema_validation",
            "strict_decoding",
            "unsupported_language",
            "unsupported_variant",
            unknownValue
        ],
        "severity": [
            "high",
            unknownValue
        ],
        "result": [
            "cleaned",
            "failed",
            "failure",
            "missing_model",
            "raw_audio_fallback",
            "ready",
            "success",
            "unavailable",
            "unloaded",
            unknownValue
        ],
        "stage": [
            "inference",
            "model_prepare",
            unknownValue
        ],
        "statusAfter": [
            "enabled",
            "error",
            "notFound",
            "notRegistered",
            "requiresApproval",
            unknownValue
        ],
        "statusBefore": [
            "enabled",
            "error",
            "notFound",
            "notRegistered",
            "requiresApproval",
            unknownValue
        ],
        "textLengthBucket": [
            "0",
            "1-50",
            "51-200",
            "201-500",
            "501+",
            unknownValue
        ],
        "terminationReason": [
            "session_limit_reached",
            "trigger_released",
            unknownValue
        ],
        "tier": [
            "accurate",
            "balanced",
            "custom",
            "experimental",
            "fast",
            "recommended",
            "specialist",
            unknownValue
        ]
    ]

    private static func shouldCheckForBundleIdentifierLikeToken(forKey key: String) -> Bool {
        key != "appVersion" && key != "macOSVersion"
    }

    private static func containsBundleIdentifierLikeToken(_ value: String) -> Bool {
        value
            .split(whereSeparator: { character in
                !(character.isLetter || character.isNumber || character == "." || character == "-" || character == "_")
            })
            .contains(where: isBundleIdentifierLikeToken)
    }

    private static func isBundleIdentifierLikeToken(_ token: Substring) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 3 else {
            return false
        }

        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
            }
        }
    }
}
