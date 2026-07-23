#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64:?public key required}"

usage() {
  cat >&2 <<'USAGE'
Usage: script/models/verify_model_manifest.sh [manifest.json] [manifest.json.sig]

Verifies the detached Textify model-manifest Ed25519 signature and the signed
production catalog policy. Set TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64 to the
base64-encoded CryptoKit raw public key representation. Optionally set
TEXTIFY_MODEL_MANIFEST_KEY_ID to require a specific signature key id.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

manifest_path="${1:-manifest.json}"
signature_path="${2:-${manifest_path}.sig}"

if [[ ! -f "$manifest_path" ]]; then
  echo "error: manifest not found: $manifest_path" >&2
  exit 1
fi

if [[ ! -f "$signature_path" ]]; then
  echo "error: signature not found: $signature_path" >&2
  exit 1
fi

swift - "$manifest_path" "$signature_path" <<'SWIFT'
import CryptoKit
import Foundation

let githubReleasePathPrefix = "/Player0109/Textify/releases/download/"
let legacyKeyID = "textify-model-manifest-2026-primary"
let legacyManifestSHA256 = "6c25788e330108a819ee394fa6351d51f5e2a5782b2b2ce54e3a65b02b07e6ec"

struct ManifestSignature: Decodable {
    let signatureVersion: Int
    let signatureType: String
    let algorithm: String
    let keyId: String
    let manifestFile: String
    let contentType: String
    let contentSHA256: String
    let signature: String
}

struct LegacyManifestSignature: Decodable {
    let signatureVersion: Int
    let keyId: String
    let algorithm: String
    let signatureBase64: String
}

struct ModelManifest: Decodable {
    let manifestVersion: Int
    let generatedAt: String
    let models: [ModelEntry]
}

struct ModelEntry: Decodable {
    let id: String
    let tier: String
    let sizeBytes: Int64
    let files: [ModelFile]
    let runtimeParameters: RuntimeParameters
    let runtime: RuntimeDescriptor?
    let capabilities: ModelCapabilities?
    let presentation: ModelPresentation?
    let minAppVersion: String
    let purpose: String?
    let benchmark: ModelBenchmark?
}

struct ModelBenchmark: Decodable {
    let schemaVersion: Int
    let policyID: String
    let suiteID: String
    let suiteIndexSHA256: String
    let modelID: String
    let engine: String
    let engineVersion: String
    let modelLicense: String
    let computeBackend: String
    let artifactFingerprint: String
    let sourceRevision: String
    let language: String
    let measuredAt: String
    let referenceHost: BenchmarkHost
    let runCount: Int
    let quality: BenchmarkQuality
    let speed: BenchmarkSpeed?
    let speedUnratedReason: String?
}

struct BenchmarkHost: Decodable {
    let chip: String
    let operatingSystem: String
    let architecture: String
}

struct BenchmarkQuality: Decodable {
    let score: Int
    let level: Int
    let label: String
    let speechItems: Int
    let noSpeechItems: Int
    let noSpeechFalsePositiveRate: Double
    let components: [BenchmarkQualityComponent]
}

struct BenchmarkQualityComponent: Decodable {
    let id: String
    let wordErrorRate: Double
    let score: Double
    let weight: Double
}

struct BenchmarkSpeed: Decodable {
    let score: Int
    let level: Int
    let label: String
    let p50ReleaseToFinalMs: Int
    let p95ReleaseToFinalMs: Int
    let p95RealTimeFactor: Double
    let relativeP95Spread: Double
}

struct ModelPresentation: Decodable {
    let expectedFinalization: String
    let accuracyTradeoff: String
    let requirements: String
}

struct ModelFile: Decodable {
    let filename: String
    let relativePath: String?
    let url: String
    let sha256: String
    let sizeBytes: Int64
}

struct RuntimeParameters: Decodable {
    let language: String
}

struct RuntimeDescriptor: Decodable {
    let engine: String
    let variant: String
    let accelerator: String
    let artifactLayout: String
}

struct ModelCapabilities: Decodable {
    let languages: [String]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func isLowercaseSHA256(_ value: String) -> Bool {
    value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
}

func lowerIsBetterScore(
    value: Double,
    excellent: Double,
    unacceptable: Double
) -> Double {
    min(100, max(0, (unacceptable - value) / (unacceptable - excellent) * 100))
}

func ratingLevel(for score: Int) -> Int {
    switch score {
    case 90...: return 5
    case 75...: return 4
    case 60...: return 3
    case 40...: return 2
    default: return 1
    }
}

func qualityLabel(for level: Int) -> String {
    [1: "Limited", 2: "Basic", 3: "Balanced", 4: "High", 5: "Highest"][level]!
}

func speedLabel(for level: Int) -> String {
    [1: "Slow", 2: "Measured", 3: "Balanced", 4: "Fast", 5: "Fastest"][level]!
}

func hasNoAuthorityOrSuffixOverrides(_ components: URLComponents) -> Bool {
    components.user == nil
        && components.password == nil
        && components.port == nil
        && components.query == nil
        && components.fragment == nil
}

func isTextifyGitHubReleaseAssetURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value),
          components.scheme == "https",
          components.host == "github.com",
          hasNoAuthorityOrSuffixOverrides(components) else {
        return false
    }
    let pathComponents = components.path.split(separator: "/")
    return components.path.hasPrefix(githubReleasePathPrefix)
        && pathComponents.count == 6
        && isSafeComponent(String(pathComponents[4]))
        && isSafeComponent(String(pathComponents[5]))
}

func isCommitPinnedHuggingFaceFileURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value),
          components.scheme == "https",
          components.host == "huggingface.co",
          hasNoAuthorityOrSuffixOverrides(components),
          !components.percentEncodedPath.contains("%"),
          !components.percentEncodedPath.contains("//"),
          !components.percentEncodedPath.hasSuffix("/") else {
        return false
    }
    let pathComponents = components.path.split(separator: "/").map(String.init)
    guard pathComponents.count >= 5,
          isSafeComponent(pathComponents[0]),
          isSafeComponent(pathComponents[1]),
          pathComponents[2] == "resolve",
          pathComponents[3].range(
              of: #"^[0-9a-f]{40}$"#,
              options: .regularExpression
          ) != nil else {
        return false
    }
    return pathComponents.dropFirst(4).allSatisfy(isSafeComponent)
}

func isApprovedModelFileURL(_ value: String) -> Bool {
    isTextifyGitHubReleaseAssetURL(value) || isCommitPinnedHuggingFaceFileURL(value)
}

func isSafeComponent(_ value: String) -> Bool {
    value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
        && value != "."
        && value != ".."
        && !value.contains("..")
}

func isSafeRelativePath(_ value: String) -> Bool {
    guard !value.isEmpty, !value.hasPrefix("/"), !value.hasSuffix("/"), !value.contains("\\") else {
        return false
    }
    return value.split(separator: "/", omittingEmptySubsequences: false)
        .allSatisfy { isSafeComponent(String($0)) }
}

func exactJSONKeys(_ data: Data, allowed: Set<String>) throws {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(object.keys) == allowed else {
        fail("signature envelope has missing or unknown fields")
    }
}

func hasExactJSONKeys(
    _ object: [String: Any],
    allowed: Set<String>,
    required: Set<String>
) -> Bool {
    let keys = Set(object.keys)
    return keys.isSubset(of: allowed) && keys.isSuperset(of: required)
}

func validateBenchmarkJSONShapes(_ data: Data) throws {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let models = root["models"] as? [[String: Any]] else {
        fail("manifest root or models are not JSON objects")
    }
    let benchmarkRequired: Set<String> = [
        "schemaVersion", "policyID", "suiteID", "suiteIndexSHA256", "modelID",
        "engine", "engineVersion", "modelLicense", "computeBackend",
        "artifactFingerprint", "sourceRevision", "language", "measuredAt", "referenceHost",
        "runCount", "quality",
    ]
    let benchmarkAllowed = benchmarkRequired.union(["speed", "speedUnratedReason"])
    for model in models {
        guard let rawBenchmark = model["benchmark"] else {
            continue
        }
        if rawBenchmark is NSNull {
            continue
        }
        guard let benchmark = rawBenchmark as? [String: Any],
              hasExactJSONKeys(
                benchmark,
                allowed: benchmarkAllowed,
                required: benchmarkRequired
              ),
              let host = benchmark["referenceHost"] as? [String: Any],
              Set(host.keys) == ["chip", "operatingSystem", "architecture"],
              let quality = benchmark["quality"] as? [String: Any],
              Set(quality.keys) == [
                "score", "level", "label", "speechItems", "noSpeechItems",
                "noSpeechFalsePositiveRate", "components",
              ],
              let components = quality["components"] as? [[String: Any]],
              components.allSatisfy({
                Set($0.keys) == ["id", "wordErrorRate", "score", "weight"]
              }) else {
            fail("benchmark object has missing or unknown fields")
        }
        if let rawSpeed = benchmark["speed"], !(rawSpeed is NSNull) {
            guard let speed = rawSpeed as? [String: Any],
                  Set(speed.keys) == [
                    "score", "level", "label", "p50ReleaseToFinalMs",
                    "p95ReleaseToFinalMs", "p95RealTimeFactor", "relativeP95Spread",
                  ] else {
                fail("benchmark speed object has missing or unknown fields")
            }
        }
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func base64URLNoPadding(_ value: String) -> Data? {
    guard !value.isEmpty,
          !value.contains("="),
          value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
        return nil
    }
    var base64 = value.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
    return Data(base64Encoded: base64)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else {
    fail("expected manifest path and signature path")
}

let manifestURL = URL(fileURLWithPath: args[0])
let signatureURL = URL(fileURLWithPath: args[1])
let environment = ProcessInfo.processInfo.environment

guard let publicKeyBase64 = environment["TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64"],
      let publicKeyData = Data(base64Encoded: publicKeyBase64) else {
    fail("TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64 is not valid base64")
}

do {
    let manifestData = try Data(contentsOf: manifestURL)
    let signatureData = try Data(contentsOf: signatureURL)
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let signatureObject = try JSONSerialization.jsonObject(with: signatureData) as? [String: Any]
    let keyID: String
    let signedContentType: String?

    if signatureObject?["signatureBase64"] != nil {
        try exactJSONKeys(
            signatureData,
            allowed: ["signatureVersion", "keyId", "algorithm", "signatureBase64"]
        )
        let legacy = try JSONDecoder().decode(LegacyManifestSignature.self, from: signatureData)
        guard legacy.keyId == legacyKeyID,
              sha256Hex(manifestData) == legacyManifestSHA256 else {
            fail("legacy signature is permitted only for the pinned published V1.1 manifest")
        }
        guard legacy.signatureVersion == 1 else {
            fail("unsupported signatureVersion \(legacy.signatureVersion)")
        }
        guard legacy.algorithm == "Ed25519" else {
            fail("unsupported signature algorithm \(legacy.algorithm)")
        }
        guard let signatureBytes = Data(base64Encoded: legacy.signatureBase64),
              publicKey.isValidSignature(signatureBytes, for: manifestData) else {
            fail("legacy detached manifest signature rejected")
        }
        keyID = legacy.keyId
        signedContentType = nil
    } else {
        try exactJSONKeys(
            signatureData,
            allowed: [
                "signatureVersion", "signatureType", "algorithm", "keyId",
                "manifestFile", "contentType", "contentSHA256", "signature"
            ]
        )
        let envelope = try JSONDecoder().decode(ManifestSignature.self, from: signatureData)
        guard envelope.signatureVersion == 1 else {
            fail("unsupported signatureVersion \(envelope.signatureVersion)")
        }
        guard envelope.signatureType == "io.github.Player0109.Textify.model-manifest" else {
            fail("unsupported signatureType \(envelope.signatureType)")
        }
        guard envelope.algorithm == "Ed25519" else {
            fail("unsupported signature algorithm \(envelope.algorithm)")
        }
        guard envelope.manifestFile == "manifest.json" else {
            fail("manifestFile must be manifest.json")
        }
        guard envelope.contentType == "application/vnd.textify.model-manifest+json;version=1"
            || envelope.contentType == "application/vnd.textify.model-manifest+json;version=2" else {
            fail("unsupported contentType \(envelope.contentType)")
        }
        let actualSHA256 = sha256Hex(manifestData)
        guard envelope.contentSHA256 == actualSHA256 else {
            fail("contentSHA256 does not match the exact manifest bytes")
        }
        guard let signatureBytes = base64URLNoPadding(envelope.signature) else {
            fail("signature is not unpadded base64url")
        }
        let canonicalPayload = Data("""
        TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1
        signatureVersion=\(envelope.signatureVersion)
        signatureType=\(envelope.signatureType)
        algorithm=\(envelope.algorithm)
        keyId=\(envelope.keyId)
        manifestFile=\(envelope.manifestFile)
        contentType=\(envelope.contentType)
        contentSHA256=\(envelope.contentSHA256)

        """.utf8)
        guard publicKey.isValidSignature(signatureBytes, for: canonicalPayload) else {
            fail("detached manifest signature rejected")
        }
        keyID = envelope.keyId
        signedContentType = envelope.contentType
    }

    if let expectedKeyID = environment["TEXTIFY_MODEL_MANIFEST_KEY_ID"],
       !expectedKeyID.isEmpty,
       keyID != expectedKeyID {
        fail("signature keyId \(keyID) does not match \(expectedKeyID)")
    }

    try validateBenchmarkJSONShapes(manifestData)
    let manifest = try JSONDecoder().decode(ModelManifest.self, from: manifestData)
    guard manifest.manifestVersion == 1 || manifest.manifestVersion == 2 else {
        fail("manifestVersion must be 1 or 2")
    }
    if let signedContentType,
       signedContentType
        != "application/vnd.textify.model-manifest+json;version=\(manifest.manifestVersion)" {
        fail("signed contentType does not match manifestVersion")
    }
    if signedContentType == nil, manifest.manifestVersion != 1 {
        fail("legacy signatures may verify only manifestVersion 1")
    }
    guard ISO8601DateFormatter().date(from: manifest.generatedAt) != nil else {
        fail("generatedAt must be an ISO 8601 timestamp")
    }
    guard !manifest.models.isEmpty else {
        fail("manifest catalog must contain at least one model")
    }
    var modelIDs = Set<String>()
    for model in manifest.models {
        if manifest.manifestVersion == 1, model.benchmark != nil {
            fail("manifestVersion 1 cannot contain benchmark ratings")
        }
        guard isSafeComponent(model.id), modelIDs.insert(model.id).inserted else {
            fail("model ids must be unique safe path components: \(model.id)")
        }
        guard model.sizeBytes > 0, !model.files.isEmpty else {
            fail("model \(model.id) must declare a positive size and at least one file")
        }
        let supportedTiers = ["recommended", "balanced", "fast", "accurate", "specialist", "experimental"]
        guard supportedTiers.contains(model.tier.lowercased()) else {
            fail("model \(model.id) has unsupported support tier \(model.tier)")
        }
        guard model.minAppVersion.range(
            of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#,
            options: .regularExpression
        ) != nil else {
            fail("model \(model.id) has invalid minAppVersion \(model.minAppVersion)")
        }
        let runtime = model.runtime ?? RuntimeDescriptor(
            engine: "whisper_cpp",
            variant: "whisper",
            accelerator: "metal_gpu",
            artifactLayout: "single_file"
        )
        let runtimeTuple = "\(runtime.engine)|\(runtime.accelerator)|\(runtime.artifactLayout)"
        guard runtimeTuple == "whisper_cpp|metal_gpu|single_file"
            || runtimeTuple == "fluid_audio_parakeet|coreml_neural_engine|model_directory"
            || runtimeTuple == "fluid_audio_paraformer|coreml_neural_engine|model_directory"
            || runtimeTuple == "sherpa_onnx|cpu|model_directory"
            || runtimeTuple == "transcribe_cpp|metal_gpu|single_file"
            || runtimeTuple == "mlx_audio|metal_gpu|model_directory"
            || runtimeTuple == "litert_lm|metal_gpu|single_file" else {
            fail("model \(model.id) has an incompatible engine, accelerator, or artifact layout")
        }
        if let capabilities = model.capabilities,
           capabilities.languages.isEmpty || capabilities.languages.contains(where: \.isEmpty) {
            fail("model \(model.id) must declare at least one non-empty language capability")
        }
        if let presentation = model.presentation,
           presentation.expectedFinalization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || presentation.accuracyTradeoff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || presentation.requirements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fail("model \(model.id) has incomplete picker presentation metadata")
        }
        var filenames = Set<String>()
        var relativePaths = Set<String>()
        var totalSize: Int64 = 0
        for file in model.files {
            guard isSafeComponent(file.filename), filenames.insert(file.filename).inserted else {
                fail("model \(model.id) contains an unsafe or duplicate filename: \(file.filename)")
            }
            guard isApprovedModelFileURL(file.url) else {
                fail("model URL must be an immutable approved HTTPS asset URL")
            }
            guard isLowercaseSHA256(file.sha256), file.sizeBytes > 0 else {
                fail("every model file must have a positive size and 64-character lowercase SHA-256")
            }
            let nextTotal = totalSize.addingReportingOverflow(file.sizeBytes)
            guard !nextTotal.overflow else {
                fail("model \(model.id) file sizes overflow Int64")
            }
            totalSize = nextTotal.partialValue
            if runtime.artifactLayout == "single_file" {
                guard file.relativePath == nil else {
                    fail("single-file model \(model.id) cannot declare relativePath")
                }
            } else {
                guard let relativePath = file.relativePath,
                      isSafeRelativePath(relativePath),
                      relativePaths.insert(relativePath).inserted else {
                    fail("directory model \(model.id) has an unsafe, missing, or duplicate relativePath")
                }
            }
        }
        guard totalSize == model.sizeBytes else {
            fail("model \(model.id) sizeBytes does not equal the sum of its files")
        }
        if runtime.artifactLayout == "single_file", model.files.count != 1 {
            fail("single-file model \(model.id) must contain exactly one file")
        }
        if let benchmark = model.benchmark {
            let canonicalArtifacts = model.files
                .sorted {
                    ($0.relativePath ?? $0.filename) < ($1.relativePath ?? $1.filename)
                }
                .map {
                    "\($0.relativePath ?? $0.filename)\t\($0.sha256)\t\($0.sizeBytes)\n"
                }
                .joined()
            guard benchmark.schemaVersion == 1,
                  benchmark.policyID == "english-catalog-rating-v2",
                  benchmark.suiteID == "english-catalog-rating-v1",
                  benchmark.suiteIndexSHA256
                    == "77637f85b4e3fde7b15f5481804e231d720c0337d11153dc5867dee2587ddde8",
                  benchmark.modelID == model.id,
                  !benchmark.engine.isEmpty,
                  !benchmark.engineVersion.isEmpty,
                  !benchmark.modelLicense.isEmpty,
                  !benchmark.computeBackend.isEmpty,
                  (benchmark.sourceRevision.count == 40 || benchmark.sourceRevision.count == 64),
                  benchmark.sourceRevision.allSatisfy(Set("0123456789abcdef").contains),
                  benchmark.artifactFingerprint == sha256Hex(Data(canonicalArtifacts.utf8)),
                  benchmark.language == "en",
                  ISO8601DateFormatter().date(from: benchmark.measuredAt) != nil,
                  benchmark.referenceHost.chip == "Apple M4 Max",
                  benchmark.referenceHost.architecture == "arm64",
                  !benchmark.referenceHost.operatingSystem.isEmpty,
                  benchmark.runCount == 3,
                  benchmark.quality.speechItems == 732,
                  benchmark.quality.noSpeechItems == 200,
                  (0 ... 1).contains(benchmark.quality.noSpeechFalsePositiveRate),
                  benchmark.quality.components.map(\.id) == [
                      "open-asr-english-nightly-v1",
                      "edacc-english-nightly-v1",
                      "berst-english-nightly-v1",
                  ],
                  benchmark.quality.components.map(\.weight) == [0.5, 0.3, 0.2],
                  (1 ... 5).contains(benchmark.quality.level),
                  (0 ... 100).contains(benchmark.quality.score)
            else {
                fail("model \(model.id) has invalid benchmark metadata")
            }
            let anchors: [(Double, Double)] = [
                (0.05, 0.40),
                (0.12, 0.55),
                (0.18, 0.70),
            ]
            for (component, anchor) in zip(benchmark.quality.components, anchors) {
                let expected = lowerIsBetterScore(
                    value: component.wordErrorRate,
                    excellent: anchor.0,
                    unacceptable: anchor.1
                )
                guard component.wordErrorRate >= 0,
                      (0 ... 100).contains(component.score),
                      abs(component.score - expected) < 0.000_001 else {
                    fail("model \(model.id) has inconsistent benchmark component math")
                }
            }
            let expectedQualityScore = Int(
                benchmark.quality.components.reduce(0) {
                    $0 + $1.score * $1.weight
                }.rounded()
            )
            let expectedQualityLevel = ratingLevel(for: expectedQualityScore)
            guard benchmark.quality.score == expectedQualityScore,
                  benchmark.quality.level == expectedQualityLevel,
                  benchmark.quality.label == qualityLabel(for: expectedQualityLevel) else {
                fail("model \(model.id) has inconsistent benchmark quality rating")
            }
            if let speed = benchmark.speed {
                let expectedSpeedScore = Int((
                    lowerIsBetterScore(
                        value: Double(speed.p95ReleaseToFinalMs),
                        excellent: 150,
                        unacceptable: 1_200
                    ) * 0.7
                        + lowerIsBetterScore(
                            value: speed.p95RealTimeFactor,
                            excellent: 0.02,
                            unacceptable: 0.25
                        ) * 0.3
                ).rounded())
                let expectedSpeedLevel = ratingLevel(for: expectedSpeedScore)
                guard benchmark.speedUnratedReason == nil,
                      (0 ... 100).contains(speed.score),
                      (1 ... 5).contains(speed.level),
                      speed.p50ReleaseToFinalMs >= 0,
                      speed.p95ReleaseToFinalMs >= speed.p50ReleaseToFinalMs,
                      speed.p95RealTimeFactor >= 0,
                      (0 ... 0.15).contains(speed.relativeP95Spread),
                      speed.score == expectedSpeedScore,
                      speed.level == expectedSpeedLevel,
                      speed.label == speedLabel(for: expectedSpeedLevel) else {
                    fail("model \(model.id) has invalid benchmark speed metadata")
                }
            } else if benchmark.speedUnratedReason != "unstable-p95" {
                fail("model \(model.id) has no benchmark speed or stability reason")
            }
        }
    }

    print("Verified \(manifestURL.path) with \(manifest.models.count) model(s) and keyId \(keyID)")
} catch {
    fail(String(describing: error))
}
SWIFT
