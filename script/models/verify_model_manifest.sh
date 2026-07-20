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
        guard envelope.contentType == "application/vnd.textify.model-manifest+json;version=1" else {
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
    }

    if let expectedKeyID = environment["TEXTIFY_MODEL_MANIFEST_KEY_ID"],
       !expectedKeyID.isEmpty,
       keyID != expectedKeyID {
        fail("signature keyId \(keyID) does not match \(expectedKeyID)")
    }

    let manifest = try JSONDecoder().decode(ModelManifest.self, from: manifestData)
    guard manifest.manifestVersion == 1 else {
        fail("manifestVersion must be 1")
    }
    guard ISO8601DateFormatter().date(from: manifest.generatedAt) != nil else {
        fail("generatedAt must be an ISO 8601 timestamp")
    }
    guard !manifest.models.isEmpty else {
        fail("manifest catalog must contain at least one model")
    }
    var modelIDs = Set<String>()
    for model in manifest.models {
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
            || runtimeTuple == "mlx_audio|metal_gpu|model_directory" else {
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
    }

    print("Verified \(manifestURL.path) with \(manifest.models.count) model(s) and keyId \(keyID)")
} catch {
    fail(String(describing: error))
}
SWIFT
