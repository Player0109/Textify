import Foundation

public struct ExcludedApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String {
        bundleIdentifier
    }

    public var bundleIdentifier: String
    public var displayName: String
    public var cachedIconData: Data?
    public var lastKnownPath: String?

    public init(
        bundleIdentifier: String,
        displayName: String,
        cachedIconData: Data? = nil,
        lastKnownPath: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.cachedIconData = cachedIconData
        self.lastKnownPath = lastKnownPath
    }
}
