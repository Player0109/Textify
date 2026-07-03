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
        "audioDurationMs",
        "averageLogProbability",
        "compressionRatio",
        "durationMs",
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
        "noSpeechProbability",
        "pasteEventPosted",
        "pasteOutcomeObservable",
        "pasteboardSnapshotSucceeded",
        "pasteboardWriteSucceeded",
        "requestedAction",
        "result",
        "secureFieldDetected",
        "statusAfter",
        "statusBefore",
        "succeeded",
        "targetChanged",
        "textLengthBucket",
        "tier"
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

    private static let unknownValue = "unknown"

    private static let closedValueAllowlists: [String: Set<String>] = [
        "appLocationCategory": [
            "applications",
            "not_found",
            "unsupported",
            "user_applications",
            unknownValue
        ],
        "event": [
            "app_started",
            "dictation_blocked_excluded_app",
            "insertion_attempt",
            "launch_at_login_change",
            "model_load",
            "speech_recognition_completed",
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
        "modelID": [
            "ggml-small.en-q5_1",
            "whisper-base-en-fast",
            "whisper-medium-en-accurate",
            "whisper-small-en-balanced",
            unknownValue
        ],
        "requestedAction": [
            "disable",
            "enable",
            unknownValue
        ],
        "result": [
            "failed",
            "failure",
            "missing_model",
            "ready",
            "success",
            "unavailable",
            "unloaded",
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
        "tier": [
            "accurate",
            "balanced",
            "fast",
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
