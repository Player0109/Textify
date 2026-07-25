import Foundation

public struct ModelInstallationExpansionEntry: Equatable, Sendable {
    public let relativePath: String
    public let expandedBytes: Int64

    public init(relativePath: String, expandedBytes: Int64) {
        self.relativePath = relativePath
        self.expandedBytes = expandedBytes
    }
}

public enum ModelInstallationExpansionError: Error, Equatable {
    case entryCountExceeded(maximum: Int, actual: Int)
    case expandedBytesExceeded(maximum: Int64, actual: Int64)
    case pathDepthExceeded(maximum: Int, actual: Int)
    case unsafePath(String)
}

public struct ModelInstallationExpansionPolicy:
    Equatable,
    Sendable
{
    public static let maximumEntryCount = 4096
    public static let maximumPathDepth = 16

    public let maximumEntryCount: Int
    public let maximumExpandedBytes: Int64
    public let maximumPathDepth: Int

    public init(
        maximumEntryCount: Int = Self.maximumEntryCount,
        maximumExpandedBytes: Int64,
        maximumPathDepth: Int = Self.maximumPathDepth
    ) {
        self.maximumEntryCount = max(0, maximumEntryCount)
        self.maximumExpandedBytes = max(0, maximumExpandedBytes)
        self.maximumPathDepth = max(0, maximumPathDepth)
    }

    public func validate(
        _ entries: [ModelInstallationExpansionEntry]
    ) throws {
        guard entries.count <= maximumEntryCount else {
            throw ModelInstallationExpansionError.entryCountExceeded(
                maximum: maximumEntryCount,
                actual: entries.count
            )
        }
        var expandedBytes: Int64 = 0
        for entry in entries {
            let components = entry.relativePath.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            guard entry.expandedBytes >= 0,
                  !entry.relativePath.hasPrefix("/"),
                  !components.isEmpty,
                  components.allSatisfy({
                      !$0.isEmpty && $0 != "." && $0 != ".."
                  })
            else {
                throw ModelInstallationExpansionError.unsafePath(
                    entry.relativePath
                )
            }
            guard components.count <= maximumPathDepth else {
                throw ModelInstallationExpansionError
                    .pathDepthExceeded(
                        maximum: maximumPathDepth,
                        actual: components.count
                    )
            }
            let next = expandedBytes.addingReportingOverflow(
                entry.expandedBytes
            )
            guard !next.overflow,
                  next.partialValue <= maximumExpandedBytes
            else {
                throw ModelInstallationExpansionError
                    .expandedBytesExceeded(
                        maximum: maximumExpandedBytes,
                        actual: next.overflow
                            ? .max
                            : next.partialValue
                    )
            }
            expandedBytes = next.partialValue
        }
    }
}
