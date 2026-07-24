import Foundation

public struct ModelTransferFreshnessPolicy: Equatable, Sendable {
    private static let maximumAge: TimeInterval = 12 * 60 * 60

    public init() {}

    public func isFresh(
        lastSuccessfulCheckAt: Date?,
        now: Date
    ) -> Bool {
        guard let lastSuccessfulCheckAt,
              lastSuccessfulCheckAt <= now
        else {
            return false
        }
        return now.timeIntervalSince(lastSuccessfulCheckAt)
            <= Self.maximumAge
    }
}
