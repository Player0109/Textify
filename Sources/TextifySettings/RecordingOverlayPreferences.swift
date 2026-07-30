public struct RecordingOverlayPreferences: Codable, Equatable, Sendable {
    public static let xOffsetRange = -2_000.0...2_000.0
    public static let yOffsetRange = -2_000.0...2_000.0
    public static let scaleRange = 0.5...2.0

    public static let defaults = RecordingOverlayPreferences()

    public var xOffset: Double
    public var yOffset: Double
    public var scale: Double

    public init(
        xOffset: Double = 0,
        yOffset: Double = 0,
        scale: Double = 1
    ) {
        self.xOffset = Self.clamp(xOffset, to: Self.xOffsetRange)
        self.yOffset = Self.clamp(yOffset, to: Self.yOffsetRange)
        self.scale = Self.clamp(scale, to: Self.scaleRange)
    }

    public func normalized() -> RecordingOverlayPreferences {
        RecordingOverlayPreferences(
            xOffset: xOffset,
            yOffset: yOffset,
            scale: scale
        )
    }

    private enum CodingKeys: String, CodingKey {
        case xOffset
        case yOffset
        case scale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            xOffset: try container.decodeIfPresent(
                Double.self,
                forKey: .xOffset
            ) ?? Self.defaults.xOffset,
            yOffset: try container.decodeIfPresent(
                Double.self,
                forKey: .yOffset
            ) ?? Self.defaults.yOffset,
            scale: try container.decodeIfPresent(
                Double.self,
                forKey: .scale
            ) ?? Self.defaults.scale
        )
    }

    public func encode(to encoder: Encoder) throws {
        let normalized = normalized()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(normalized.xOffset, forKey: .xOffset)
        try container.encode(normalized.yOffset, forKey: .yOffset)
        try container.encode(normalized.scale, forKey: .scale)
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>
    ) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
