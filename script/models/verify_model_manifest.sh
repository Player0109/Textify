#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64:?public key required}"

usage() {
  cat >&2 <<'USAGE'
Usage: script/models/verify_model_manifest.sh [manifest.json] [manifest.json.sig]

Verifies the detached Textify model-manifest Ed25519 signature and the V1.1
production manifest policy. Set TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64 to the
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

let requiredModelID = "ggml-small.en-q5_1"
let requiredFilename = "ggml-small.en-q5_1.bin"
let githubReleasePathPrefix = "/Player0109/Textify/releases/download/"

struct ManifestSignature: Decodable {
    let signatureVersion: Int
    let keyId: String
    let algorithm: String
    let signatureBase64: String
}

struct ModelManifest: Decodable {
    let manifestVersion: Int
    let models: [ModelEntry]
}

struct ModelEntry: Decodable {
    let id: String
    let files: [ModelFile]
    let runtimeParameters: RuntimeParameters
}

struct ModelFile: Decodable {
    let filename: String
    let url: String
    let sha256: String
}

struct RuntimeParameters: Decodable {
    let language: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func isLowercaseSHA256(_ value: String) -> Bool {
    value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
}

func isTextifyGitHubReleaseAssetURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value),
          components.scheme == "https",
          components.host == "github.com" else {
        return false
    }
    return components.path.hasPrefix(githubReleasePathPrefix)
        && components.path.hasSuffix("/\(requiredFilename)")
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
    let signature = try JSONDecoder().decode(ManifestSignature.self, from: signatureData)

    guard signature.signatureVersion == 1 else {
        fail("unsupported signatureVersion \(signature.signatureVersion)")
    }
    guard signature.algorithm == "Ed25519" else {
        fail("unsupported signature algorithm \(signature.algorithm)")
    }
    if let expectedKeyID = environment["TEXTIFY_MODEL_MANIFEST_KEY_ID"],
       !expectedKeyID.isEmpty,
       signature.keyId != expectedKeyID {
        fail("signature keyId \(signature.keyId) does not match \(expectedKeyID)")
    }
    guard let signatureBytes = Data(base64Encoded: signature.signatureBase64) else {
        fail("signatureBase64 is not valid base64")
    }

    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    guard publicKey.isValidSignature(signatureBytes, for: manifestData) else {
        fail("detached manifest signature rejected")
    }

    let manifest = try JSONDecoder().decode(ModelManifest.self, from: manifestData)
    guard manifest.manifestVersion == 1 else {
        fail("manifestVersion must be 1")
    }
    guard manifest.models.count == 1 else {
        fail("manifest must contain exactly one model, found \(manifest.models.count)")
    }
    let model = manifest.models[0]
    guard model.id == requiredModelID else {
        fail("model id must be \(requiredModelID), found \(model.id)")
    }
    guard model.runtimeParameters.language == "en" else {
        fail("model runtime language must be en")
    }
    guard model.files.count == 1 else {
        fail("model must contain exactly one file, found \(model.files.count)")
    }
    let file = model.files[0]
    guard file.filename == requiredFilename else {
        fail("model filename must be \(requiredFilename), found \(file.filename)")
    }
    guard isTextifyGitHubReleaseAssetURL(file.url) else {
        fail("model URL must be an HTTPS Textify GitHub Release asset URL")
    }
    guard isLowercaseSHA256(file.sha256) else {
        fail("model sha256 must be present as 64 lowercase hex characters")
    }

    print("Verified \(manifestURL.path) for \(model.id) with keyId \(signature.keyId)")
} catch {
    fail(String(describing: error))
}
SWIFT
