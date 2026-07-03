import Foundation

public enum DiagnosticEvent: Encodable, Sendable {
    case appStarted(appVersion: String, macOSVersion: String)
    case insertionAttempt(
        textLengthBucket: String,
        pasteboardSnapshotSucceeded: Bool,
        pasteboardWriteSucceeded: Bool,
        pasteEventPosted: Bool,
        fallbackAttempted: Bool,
        fallbackBlockedReason: String?,
        durationMs: Int
    )
    case dictationBlockedExcludedApp
    case transcriptionCompleted(
        modelID: String,
        audioDurationMs: Int,
        inferenceDurationMs: Int,
        textLengthBucket: String
    )
    case launchAtLoginChange(
        requestedAction: String,
        statusBefore: String,
        statusAfter: String,
        appLocationCategory: String,
        succeeded: Bool,
        errorDomain: String?,
        errorCode: Int?
    )
    case modelLoad(modelID: String, tier: String, durationMs: Int, result: String)

    private enum CodingKeys: String, CodingKey {
        case event
        case appVersion
        case macOSVersion
        case textLengthBucket
        case pasteboardSnapshotSucceeded
        case pasteboardWriteSucceeded
        case pasteEventPosted
        case fallbackAttempted
        case fallbackBlockedReason
        case durationMs
        case audioDurationMs
        case inferenceDurationMs
        case requestedAction
        case statusBefore
        case statusAfter
        case appLocationCategory
        case succeeded
        case errorDomain
        case errorCode
        case modelID
        case tier
        case result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .appStarted(appVersion, macOSVersion):
            try container.encode("app_started", forKey: .event)
            try container.encode(appVersion, forKey: .appVersion)
            try container.encode(macOSVersion, forKey: .macOSVersion)

        case let .insertionAttempt(
            textLengthBucket,
            pasteboardSnapshotSucceeded,
            pasteboardWriteSucceeded,
            pasteEventPosted,
            fallbackAttempted,
            fallbackBlockedReason,
            durationMs
        ):
            try container.encode("insertion_attempt", forKey: .event)
            try container.encode(textLengthBucket, forKey: .textLengthBucket)
            try container.encode(pasteboardSnapshotSucceeded, forKey: .pasteboardSnapshotSucceeded)
            try container.encode(pasteboardWriteSucceeded, forKey: .pasteboardWriteSucceeded)
            try container.encode(pasteEventPosted, forKey: .pasteEventPosted)
            try container.encode(fallbackAttempted, forKey: .fallbackAttempted)
            try container.encodeIfPresent(sanitize(fallbackBlockedReason, forKey: .fallbackBlockedReason), forKey: .fallbackBlockedReason)
            try container.encode(durationMs, forKey: .durationMs)

        case .dictationBlockedExcludedApp:
            try container.encode("dictation_blocked_excluded_app", forKey: .event)

        case let .transcriptionCompleted(
            modelID,
            audioDurationMs,
            inferenceDurationMs,
            textLengthBucket
        ):
            try container.encode("speech_recognition_completed", forKey: .event)
            try container.encode(sanitize(modelID, forKey: .modelID), forKey: .modelID)
            try container.encode(audioDurationMs, forKey: .audioDurationMs)
            try container.encode(inferenceDurationMs, forKey: .inferenceDurationMs)
            try container.encode(sanitize(textLengthBucket, forKey: .textLengthBucket), forKey: .textLengthBucket)

        case let .launchAtLoginChange(
            requestedAction,
            statusBefore,
            statusAfter,
            appLocationCategory,
            succeeded,
            errorDomain,
            errorCode
        ):
            try container.encode("launch_at_login_change", forKey: .event)
            try container.encode(sanitize(requestedAction, forKey: .requestedAction), forKey: .requestedAction)
            try container.encode(sanitize(statusBefore, forKey: .statusBefore), forKey: .statusBefore)
            try container.encode(sanitize(statusAfter, forKey: .statusAfter), forKey: .statusAfter)
            try container.encode(sanitize(appLocationCategory, forKey: .appLocationCategory), forKey: .appLocationCategory)
            try container.encode(succeeded, forKey: .succeeded)
            try container.encodeIfPresent(sanitize(errorDomain, forKey: .errorDomain), forKey: .errorDomain)
            try container.encodeIfPresent(errorCode, forKey: .errorCode)

        case let .modelLoad(modelID, tier, durationMs, result):
            try container.encode("model_load", forKey: .event)
            try container.encode(sanitize(modelID, forKey: .modelID), forKey: .modelID)
            try container.encode(sanitize(tier, forKey: .tier), forKey: .tier)
            try container.encode(durationMs, forKey: .durationMs)
            try container.encode(sanitize(result, forKey: .result), forKey: .result)
        }
    }

    private func sanitize(_ value: String, forKey key: CodingKeys) -> String {
        DiagnosticsStringSanitizer.sanitize(value, forKey: key.rawValue)
    }

    private func sanitize(_ value: String?, forKey key: CodingKeys) -> String? {
        value.map { sanitize($0, forKey: key) }
    }
}
