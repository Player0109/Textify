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
            redacted[key] = redactJSONValue(value)
        }
        return redacted
    }

    private func redactJSONValue(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            var redacted: [String: Any] = [:]
            for (key, nestedValue) in dictionary where allowedKeys.contains(key) {
                redacted[key] = redactJSONValue(nestedValue)
            }
            return redacted
        case let array as [Any]:
            return array.map(redactJSONValue)
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
