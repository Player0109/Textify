public struct DiagnosticsRetentionPolicy: Equatable, Sendable {
    public let maxAgeDays: Int
    public let maxFileCount: Int
    public let maxTotalBytes: Int64

    public init(maxAgeDays: Int, maxFileCount: Int, maxTotalBytes: Int64) {
        self.maxAgeDays = maxAgeDays
        self.maxFileCount = maxFileCount
        self.maxTotalBytes = maxTotalBytes
    }

    public static let v1_1Default = DiagnosticsRetentionPolicy(
        maxAgeDays: 14,
        maxFileCount: 20,
        maxTotalBytes: 10 * 1_024 * 1_024
    )
}
