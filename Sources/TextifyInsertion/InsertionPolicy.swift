public enum FallbackDecision: Equatable, Sendable {
    case fallbackWithUnicodeChunks(maxScalarsPerChunk: Int)
    case doNotFallback(reason: String)
}

public struct InsertionPolicy: Equatable, Sendable {
    public static let maximumFallbackScalars = 500
    public static let maximumScalarsPerFallbackChunk = 20

    public init() {}

    public func fallbackDecision(
        pasteEventPosted: Bool,
        textLength: Int,
        containsControlCharacters: Bool,
        targetStillMatches: Bool,
        secureFieldDetected: Bool
    ) -> FallbackDecision {
        if pasteEventPosted {
            return .doNotFallback(reason: "paste_outcome_unobservable")
        }

        if !targetStillMatches {
            return .doNotFallback(reason: "target_changed")
        }

        if secureFieldDetected {
            return .doNotFallback(reason: "secure_field_detected")
        }

        if textLength <= 0 {
            return .doNotFallback(reason: "empty_text")
        }

        if textLength > Self.maximumFallbackScalars {
            return .doNotFallback(reason: "text_too_long")
        }

        if containsControlCharacters {
            return .doNotFallback(reason: "control_characters_present")
        }

        return .fallbackWithUnicodeChunks(maxScalarsPerChunk: Self.maximumScalarsPerFallbackChunk)
    }
}
