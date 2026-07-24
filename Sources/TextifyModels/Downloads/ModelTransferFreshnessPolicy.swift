import Foundation

public struct ModelTransferFreshnessPolicy: Equatable, Sendable {
    public static let defaultMaximumAge: TimeInterval = 12 * 60 * 60

    public let maximumAge: TimeInterval

    public init(maximumAge: TimeInterval = Self.defaultMaximumAge) {
        self.maximumAge = maximumAge
    }

    public func isFresh(
        lastSuccessfulCheckAt: Date?,
        now: Date
    ) -> Bool {
        guard maximumAge >= 0,
              let lastSuccessfulCheckAt,
              lastSuccessfulCheckAt <= now
        else {
            return false
        }
        return now.timeIntervalSince(lastSuccessfulCheckAt) <= maximumAge
    }
}
