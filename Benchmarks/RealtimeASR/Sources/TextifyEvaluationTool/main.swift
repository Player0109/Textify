import BenchmarkMetrics
import CryptoKit
import Darwin
import Foundation

@main
struct TextifyEvaluationTool {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }

    private static func run(arguments: [String]) throws {
        guard arguments.count >= 2 else {
            throw ToolError.usage
        }

        let command = arguments[0]
        let manifestURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        if command == "validate-index" {
            guard arguments.count == 2 else { throw ToolError.usage }
            let index = try EvaluationSuiteIndex.decode(Data(contentsOf: manifestURL))
            let components = try EvaluationSuiteIndexResolver.resolve(
                index: index,
                indexURL: manifestURL
            )
            let itemCount = components.reduce(0) {
                $0 + $1.manifest.compatibleItems(
                    maxAudioSeconds: $1.component.maxAudioSeconds
                ).count
            }
            print(
                "Validated \(index.id): \(components.count) components with \(itemCount) items"
            )
            return
        }
        if command == "rate-index" {
            try rateIndex(indexURL: manifestURL, arguments: Array(arguments.dropFirst(2)))
            return
        }
        let manifest = try EvaluationSuiteManifest.decode(Data(contentsOf: manifestURL))

        switch command {
        case "validate":
            guard arguments.count == 2 else { throw ToolError.usage }
            print("Validated \(manifest.id): \(manifest.items.count) items across \(manifest.subsets.count) subsets")
        case "compatible-items":
            guard arguments.count == 4,
                  arguments[2] == "--max-audio-seconds",
                  let maximum = Int(arguments[3]),
                  maximum > 0,
                  maximum <= 60
            else {
                throw ToolError.usage
            }
            let data = try JSONEncoder().encode(
                manifest.compatibleItems(maxAudioSeconds: maximum)
            )
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        case "summarize":
            guard arguments.count == 5,
                  arguments[3] == "--max-audio-seconds",
                  let maximum = Int(arguments[4]),
                  (1 ... 60).contains(maximum)
            else {
                throw ToolError.usage
            }
            let resultDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
                .standardizedFileURL
            let results = try loadResults(from: resultDirectory)
            let report = try EvaluationReportBuilder.build(
                manifest: manifest,
                maxAudioSeconds: maximum,
                resultsByItemID: results
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
        default:
            throw ToolError.usage
        }
    }

    private static func rateIndex(indexURL: URL, arguments: [String]) throws {
        var policyURL: URL?
        var modelID: String?
        var artifactFingerprint: String?
        var measuredAt: String?
        var runDirectoryURLs: [URL] = []
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else { throw ToolError.usage }
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--policy":
                policyURL = URL(fileURLWithPath: value).standardizedFileURL
            case "--model-id":
                modelID = value
            case "--artifact-fingerprint":
                artifactFingerprint = value
            case "--measured-at":
                measuredAt = value
            case "--run-dir":
                runDirectoryURLs.append(
                    URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
                )
            default:
                throw ToolError.usage
            }
            index += 2
        }
        guard let policyURL, let modelID, let artifactFingerprint, let measuredAt else {
            throw ToolError.usage
        }

        let indexData = try Data(contentsOf: indexURL)
        let suiteIndex = try EvaluationSuiteIndex.decode(indexData)
        let resolved = try EvaluationSuiteIndexResolver.resolve(
            index: suiteIndex,
            indexURL: indexURL
        )
        let policy = try CatalogRatingPolicy.decode(Data(contentsOf: policyURL))
        let runs = try runDirectoryURLs.map { directory in
            try loadRatingRun(from: directory, components: resolved)
        }
        let rating = try CatalogRatingBuilder.build(
            policy: policy,
            index: suiteIndex,
            resolvedComponents: resolved,
            suiteIndexSHA256: SHA256.hash(data: indexData)
                .map { String(format: "%02x", $0) }
                .joined(),
            modelID: modelID,
            artifactFingerprint: artifactFingerprint,
            measuredAt: measuredAt,
            runs: runs
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(rating))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func loadRatingRun(
        from directory: URL,
        components: [ResolvedEvaluationSuiteComponent]
    ) throws -> CatalogRatingRunEvidence {
        let metadata: CatalogRatingRunMetadata
        do {
            metadata = try JSONDecoder().decode(
                CatalogRatingRunMetadata.self,
                from: Data(contentsOf: directory.appendingPathComponent("run.json"))
            )
        } catch {
            throw ToolError.invalidRunMetadata(String(describing: error))
        }
        var results: [String: [String: EvaluationRunResult]] = [:]
        var sessions: [String: EvaluationBatchSessionSnapshot] = [:]
        for resolved in components {
            let componentID = resolved.component.id
            let componentDirectory = directory
                .appendingPathComponent(componentID, isDirectory: true)
            results[componentID] = try loadResults(from: componentDirectory)
            let sessionURL = componentDirectory.appendingPathComponent("batch-session.json")
            do {
                sessions[componentID] = try JSONDecoder().decode(
                    EvaluationBatchSessionSnapshot.self,
                    from: Data(contentsOf: sessionURL)
                )
            } catch {
                throw ToolError.invalidSessionFile(componentID, String(describing: error))
            }
        }
        return CatalogRatingRunEvidence(
            metadata: metadata,
            resultsByComponentID: results,
            sessionsByComponentID: sessions
        )
    }

    private static func loadResults(
        from directory: URL
    ) throws -> [String: EvaluationRunResult] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var results: [String: EvaluationRunResult] = [:]
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension == "json"
            && file.lastPathComponent != "summary.json"
            && file.lastPathComponent != "batch-session.json"
        {
            let itemID = file.deletingPathExtension().lastPathComponent
            do {
                results[itemID] = try JSONDecoder().decode(
                    EvaluationRunResult.self,
                    from: Data(contentsOf: file)
                )
            } catch {
                throw ToolError.invalidResultFile(file.lastPathComponent, String(describing: error))
            }
        }
        return results
    }
}

private enum ToolError: Error, CustomStringConvertible {
    case usage
    case invalidResultFile(String, String)
    case invalidSessionFile(String, String)
    case invalidRunMetadata(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: TextifyEvaluationTool validate MANIFEST | validate-index INDEX | compatible-items MANIFEST --max-audio-seconds 1...60 | summarize MANIFEST RESULTS_DIR --max-audio-seconds 1...60 | rate-index INDEX --policy POLICY --model-id ID --artifact-fingerprint SHA256 --measured-at ISO8601 --run-dir DIR (repeat run dir as required by policy)"
        case let .invalidResultFile(filename, reason):
            return "Could not decode benchmark result \(filename): \(reason)"
        case let .invalidSessionFile(component, reason):
            return "Could not decode resident session for \(component): \(reason)"
        case let .invalidRunMetadata(reason):
            return "Could not decode rating run metadata: \(reason)"
        }
    }
}
