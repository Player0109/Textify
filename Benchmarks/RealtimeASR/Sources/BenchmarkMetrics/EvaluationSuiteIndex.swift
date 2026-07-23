import CryptoKit
import Foundation

public struct EvaluationSuiteIndex: Codable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let language: String
    public let components: [EvaluationSuiteComponent]

    public static func decode(_ data: Data) throws -> EvaluationSuiteIndex {
        let index = try JSONDecoder().decode(EvaluationSuiteIndex.self, from: data)
        try index.validate()
        return index
    }

    private func validate() throws {
        guard schemaVersion == 1 else {
            throw EvaluationSuiteIndexError.unsupportedSchemaVersion(schemaVersion)
        }
        guard language == "en" else {
            throw EvaluationSuiteIndexError.unsupportedLanguage(language)
        }
        guard !components.isEmpty else {
            throw EvaluationSuiteIndexError.emptyComponents
        }

        var componentIDs = Set<String>()
        var manifestPaths = Set<String>()
        for component in components {
            guard componentIDs.insert(component.id).inserted else {
                throw EvaluationSuiteIndexError.duplicateComponentID(component.id)
            }
            guard isSafeIndexRelativePath(component.manifest) else {
                throw EvaluationSuiteIndexError.unsafeManifestPath(component.manifest)
            }
            guard manifestPaths.insert(component.manifest).inserted else {
                throw EvaluationSuiteIndexError.duplicateManifestPath(component.manifest)
            }
            guard isIndexLowercaseHex(component.sha256, length: 64) else {
                throw EvaluationSuiteIndexError.invalidManifestSHA256(component.id)
            }
            guard (1 ... 60).contains(component.maxAudioSeconds) else {
                throw EvaluationSuiteIndexError.invalidMaximumAudioSeconds(component.id)
            }
        }
    }
}

public struct EvaluationSuiteComponent: Codable, Sendable {
    public let id: String
    public let manifest: String
    public let sha256: String
    public let maxAudioSeconds: Int
    public let metricsProfile: EvaluationMetricsProfile
}

public enum EvaluationMetricsProfile: String, Codable, Sendable {
    case standard
    case stress
    case structured
    case negativeControl = "negative-control"
}

public struct ResolvedEvaluationSuiteComponent: Sendable {
    public let component: EvaluationSuiteComponent
    public let manifestURL: URL
    public let manifest: EvaluationSuiteManifest
}

public enum EvaluationSuiteIndexResolver {
    public static func resolve(
        index: EvaluationSuiteIndex,
        indexURL: URL
    ) throws -> [ResolvedEvaluationSuiteComponent] {
        let baseURL = indexURL.deletingLastPathComponent().standardizedFileURL
        return try index.components.map { component in
            let manifestURL = baseURL
                .appendingPathComponent(component.manifest, isDirectory: false)
                .standardizedFileURL
            guard manifestURL.deletingLastPathComponent() == baseURL else {
                throw EvaluationSuiteIndexError.unsafeManifestPath(component.manifest)
            }

            let data: Data
            do {
                data = try Data(contentsOf: manifestURL)
            } catch {
                throw EvaluationSuiteIndexError.unreadableManifest(component.id)
            }
            guard sha256Hex(data) == component.sha256 else {
                throw EvaluationSuiteIndexError.manifestChecksumMismatch(component.id)
            }

            let manifest = try EvaluationSuiteManifest.decode(data)
            guard manifest.id == component.id else {
                throw EvaluationSuiteIndexError.manifestIDMismatch(
                    expected: component.id,
                    actual: manifest.id
                )
            }
            guard !manifest.compatibleItems(maxAudioSeconds: component.maxAudioSeconds).isEmpty else {
                throw EvaluationSuiteIndexError.noCompatibleItems(component.id)
            }
            try validateProfile(component.metricsProfile, manifest: manifest)
            return ResolvedEvaluationSuiteComponent(
                component: component,
                manifestURL: manifestURL,
                manifest: manifest
            )
        }
    }

    private static func validateProfile(
        _ profile: EvaluationMetricsProfile,
        manifest: EvaluationSuiteManifest
    ) throws {
        switch profile {
        case .negativeControl:
            guard manifest.subsets.allSatisfy({ $0.speechOrigin == .noSpeech }) else {
                throw EvaluationSuiteIndexError.metricsProfileMismatch(manifest.id)
            }
        case .standard, .stress, .structured:
            guard manifest.subsets.contains(where: { $0.speechOrigin != .noSpeech }) else {
                throw EvaluationSuiteIndexError.metricsProfileMismatch(manifest.id)
            }
        }
    }
}

public enum EvaluationSuiteIndexError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(Int)
    case unsupportedLanguage(String)
    case emptyComponents
    case duplicateComponentID(String)
    case unsafeManifestPath(String)
    case duplicateManifestPath(String)
    case invalidManifestSHA256(String)
    case invalidMaximumAudioSeconds(String)
    case unreadableManifest(String)
    case manifestChecksumMismatch(String)
    case manifestIDMismatch(expected: String, actual: String)
    case noCompatibleItems(String)
    case metricsProfileMismatch(String)

    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Unsupported evaluation suite index schema version: \(version)"
        case let .unsupportedLanguage(language):
            return "Evaluation suite index language must be English, received: \(language)"
        case .emptyComponents:
            return "Evaluation suite index must contain at least one component"
        case let .duplicateComponentID(id):
            return "Duplicate evaluation suite component id: \(id)"
        case let .unsafeManifestPath(path):
            return "Component manifest must be a filename in the index directory: \(path)"
        case let .duplicateManifestPath(path):
            return "Duplicate evaluation suite component manifest: \(path)"
        case let .invalidManifestSHA256(id):
            return "Component manifest has an invalid SHA-256: \(id)"
        case let .invalidMaximumAudioSeconds(id):
            return "Component maximum audio duration must be between 1 and 60 seconds: \(id)"
        case let .unreadableManifest(id):
            return "Could not read evaluation suite component manifest: \(id)"
        case let .manifestChecksumMismatch(id):
            return "Evaluation suite component manifest checksum changed: \(id)"
        case let .manifestIDMismatch(expected, actual):
            return "Evaluation suite component expected id \(expected), received \(actual)"
        case let .noCompatibleItems(id):
            return "Evaluation suite component has no compatible items: \(id)"
        case let .metricsProfileMismatch(id):
            return "Evaluation suite component does not match its metrics profile: \(id)"
        }
    }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func isIndexLowercaseHex(_ value: String, length: Int) -> Bool {
    let allowed = Set("0123456789abcdef")
    return value.count == length && value.allSatisfy(allowed.contains)
}

private func isSafeIndexRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
        return false
    }
    return path.split(separator: "/", omittingEmptySubsequences: false).count == 1
        && path != "."
        && path != ".."
}
