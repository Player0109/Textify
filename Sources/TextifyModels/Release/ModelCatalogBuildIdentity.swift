import CryptoKit
import Foundation

public struct ModelCatalogBuildIdentity:
    Codable,
    CustomStringConvertible,
    Equatable,
    Sendable
{
    public let bundleIdentifier: String
    public let shortVersion: String
    public let bundleVersion: String
    public let executableSHA256: String

    public var description: String {
        "\(bundleIdentifier)/\(shortVersion)/\(bundleVersion)"
            + "@sha256:\(executableSHA256)"
    }

    public static func load(
        fromAppBundle appBundleURL: URL
    ) throws -> ModelCatalogBuildIdentity {
        let infoURL = appBundleURL.appendingPathComponent(
            "Contents/Info.plist"
        )
        let infoData = try Data(contentsOf: infoURL)
        guard let info = try PropertyListSerialization.propertyList(
            from: infoData,
            format: nil
        ) as? [String: Any],
        let bundleIdentifier = info["CFBundleIdentifier"] as? String,
        !bundleIdentifier.isEmpty,
        let shortVersion = info["CFBundleShortVersionString"] as? String,
        !shortVersion.isEmpty,
        let bundleVersion = info["CFBundleVersion"] as? String,
        !bundleVersion.isEmpty,
        let executableName = info["CFBundleExecutable"] as? String,
        !executableName.isEmpty
        else {
            throw ModelCatalogBuildIdentityError.invalidInfoPlist
        }
        let executableURL = appBundleURL.appendingPathComponent(
            "Contents/MacOS/\(executableName)"
        )
        let executableData = try Data(contentsOf: executableURL)
        guard !executableData.isEmpty else {
            throw ModelCatalogBuildIdentityError.emptyExecutable
        }
        return ModelCatalogBuildIdentity(
            bundleIdentifier: bundleIdentifier,
            shortVersion: shortVersion,
            bundleVersion: bundleVersion,
            executableSHA256: SHA256.hash(data: executableData)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }

    public static func loadVerified(
        fromAppBundle appBundleURL: URL
    ) throws -> ModelCatalogBuildIdentity {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--verify",
            "--deep",
            "--strict",
            appBundleURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit,
              process.terminationStatus == 0
        else {
            throw ModelCatalogBuildIdentityError
                .invalidCodeSignature(process.terminationStatus)
        }
        return try load(fromAppBundle: appBundleURL)
    }

    init(
        bundleIdentifier: String,
        shortVersion: String,
        bundleVersion: String,
        executableSHA256: String
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.bundleVersion = bundleVersion
        self.executableSHA256 = executableSHA256
    }
}

public enum ModelCatalogBuildIdentityError: Error, Equatable, Sendable {
    case invalidInfoPlist
    case emptyExecutable
    case invalidCodeSignature(Int32)
}
